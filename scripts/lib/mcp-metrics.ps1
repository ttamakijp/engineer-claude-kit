#requires -Version 5.1
# mcp-metrics.ps1
# Provides: counting of delegation that went to a local-llm MCP server, and the
#           handler mix (which model actually did the light work).
# ASCII only (no Japanese in code, comments, or strings). See ADR-0016 decision C.
#
# Why this exists:
# Get-RuleMetrics only ever looked at Agent / Task launches and their
# subagent_type, so every mcp__* call was invisible to it. That is what made
# "delegation 0%" wrong in a specific way in the snapshot-3 window: 9 calls had
# gone to local-llm (5 generate_commit_message, 2 chat, 2 health) and the metric
# counted none of them. The number was not measuring "no delegation happened",
# it was measuring "no delegation to the two tool names I know about happened".
#
# Dependencies: the 'meta' rows of Get-InsightsScope -IncludeRuleMetrics, which
# must carry Model (added for this file; see New-RuleMetricsRow). Get-ModelFamily
# and the $script:RuleMetrics* constants are used when present and fall back to
# local copies, so this file can be dot-sourced on its own in a test.

# Tool names arrive as mcp__<server>__<tool>. Measured on this machine the
# local-llm server exposes mcp__local-llm__local_llm__<tool> -- the server
# segment is whatever the user wrote in their MCP configuration, so match on the
# tool segment, which the server itself prefixes with local_llm__.
$script:McpLocalLlmPattern = 'local_llm__'

# health is an availability probe, not delegated work. Counting it would inflate
# the delegation figure with calls that produced no output: 2 of the 9 calls in
# the snapshot-3 window were health.
$script:McpLocalLlmProbePattern = 'local_llm__health$'

function Get-McpModelFamily {
    # Thin wrapper so this file does not depend on dot-source order.
    param([string]$Model)
    if (Get-Command -Name Get-ModelFamily -ErrorAction SilentlyContinue) {
        return (Get-ModelFamily $Model)
    }
    if ([string]::IsNullOrWhiteSpace($Model)) { return $null }
    $m = $Model.ToLowerInvariant()
    if ($m -like '*opus*')   { return 'Opus' }
    if ($m -like '*sonnet*') { return 'Sonnet' }
    if ($m -like '*haiku*')  { return 'Haiku' }
    return $null
}

function Get-McpShortToolName {
    # mcp__local-llm__local_llm__chat -> chat. The server segment varies per
    # user, so a baseline keyed on the full name would not compare across
    # machines.
    param([string]$ToolName)
    $i = $ToolName.LastIndexOf($script:McpLocalLlmPattern)
    if ($i -lt 0) { return $ToolName }
    return $ToolName.Substring($i + $script:McpLocalLlmPattern.Length)
}

function Get-McpDelegationStats {
    # Count local-llm delegation, and partition the light work in the window by
    # which model handled it.
    #
    # DelegationDisplaced is a HANDLER MIX, not a per-event displacement claim:
    #   Local  - a local-llm work call
    #   Haiku  - an Agent / Task launch into a Haiku sub-agent
    #   Opus   - a large tool output the main agent absorbed itself, on an Opus turn
    #   Sonnet - the same, on a Sonnet turn
    # ADR-0016 unresolved question 3 is that "local-llm did it, so Opus did not"
    # cannot be decided per event from a transcript. It can be read as a delta:
    # if Local rises while Opus falls across two snapshots, that is work moving.
    # A single snapshot's Local count is an upper bound on what was displaced and
    # the lower bound is 0, so it must never be reported as a point estimate.
    #
    # Returns an ordered hashtable with ADR-0016's field names. Zero rows yield
    # zeroed counters rather than $null, so callers can merge unconditionally.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()]$Entries,
        [string]$ProjectFilter
    )

    $haikuAgents = if ($script:RuleMetricsHaikuAgents) { $script:RuleMetricsHaikuAgents } else { @('log-summary') }
    $legacyAgents = if ($script:RuleMetricsLegacyHaikuAgents) { $script:RuleMetricsLegacyHaikuAgents } else { @('commit-msg', 'lint-helper') }
    $agentTools = if ($script:RuleMetricsAgentTools) { $script:RuleMetricsAgentTools } else { @('Agent', 'Task') }
    $largeChars = if ($script:RuleMetricsLargeResultChars) { $script:RuleMetricsLargeResultChars } else { 8000 }
    $haikuNames = @($haikuAgents) + @($legacyAgents)

    $meta = @($Entries | Where-Object { $_.Role -eq 'meta' })
    if ($ProjectFilter) {
        $meta = @($meta | Where-Object { [string]$_.Cwd -and ([string]$_.Cwd).Contains($ProjectFilter) })
    }

    $byTool = @{}
    $displaced = [ordered]@{ Local = 0; Haiku = 0; Opus = 0; Sonnet = 0; Unknown = 0 }
    $calls = 0
    $probes = 0
    # Rows arrive in timestamp order. A tool_result row carries no model of its
    # own, so the turn that asked for it supplies the family.
    $lastFamily = $null

    foreach ($row in $meta) {
        $family = Get-McpModelFamily ([string]$row.Model)
        if ($family) { $lastFamily = $family }

        $tool = [string]$row.ToolName
        if ($tool) {
            if ($tool -match $script:McpLocalLlmPattern) {
                if ($tool -match $script:McpLocalLlmProbePattern) {
                    $probes++
                } else {
                    $calls++
                    $short = Get-McpShortToolName -ToolName $tool
                    if (-not $byTool.ContainsKey($short)) { $byTool[$short] = 0 }
                    $byTool[$short] = $byTool[$short] + 1
                    $displaced['Local'] = $displaced['Local'] + 1
                }
                continue
            }
            if (@($agentTools) -contains $tool -and (@($haikuNames) -contains [string]$row.SubagentType)) {
                $displaced['Haiku'] = $displaced['Haiku'] + 1
                continue
            }
        }

        # A large output that was not handed to anyone is work the main agent
        # absorbed. This is the bucket local-llm is meant to drain.
        if ([int]$row.ResultChars -ge $largeChars) {
            if ($lastFamily -and $displaced.Contains($lastFamily)) {
                $displaced[$lastFamily] = $displaced[$lastFamily] + 1
            } else {
                $displaced['Unknown'] = $displaced['Unknown'] + 1
            }
        }
    }

    return [ordered]@{
        DelegationLocalLlm       = $calls
        DelegationLocalLlmProbes = $probes
        DelegationLocalLlmByTool = $byTool
        DelegationDisplaced      = $displaced
    }
}

function Format-McpDelegationLines {
    # Report lines for the rule-firing section. Returns an empty array when no
    # local-llm call occurred, so a user without local-llm sees nothing new.
    param([Parameter(Mandatory)]$McpStats)

    $lines = @()
    $calls = [int]$McpStats.DelegationLocalLlm
    $probes = [int]$McpStats.DelegationLocalLlmProbes
    if ($calls -le 0 -and $probes -le 0) { return $lines }

    $tools = @()
    foreach ($k in ($McpStats.DelegationLocalLlmByTool.Keys | Sort-Object)) {
        $tools += ("$k=" + $McpStats.DelegationLocalLlmByTool[$k])
    }
    $detail = if ($tools.Count -gt 0) { " ($($tools -join ', '))" } else { '' }
    $lines += "- local-llm delegation: $calls work call(s)$detail, plus $probes health probe(s) not counted as work"

    $disp = @()
    foreach ($k in $McpStats.DelegationDisplaced.Keys) {
        if ([int]$McpStats.DelegationDisplaced[$k] -gt 0) { $disp += ("$k=" + $McpStats.DelegationDisplaced[$k]) }
    }
    if ($disp.Count -gt 0) {
        $lines += "- light-work handler mix: $($disp -join ', ')"
        $lines += "  Read this as a delta against the previous snapshot. A single window's"
        $lines += "  Local count is an upper bound on displaced work; the lower bound is 0."
    }
    return $lines
}
