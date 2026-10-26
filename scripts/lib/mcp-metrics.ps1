#requires -Version 5.1
# mcp-metrics.ps1
# Provides: counting of delegation that went to a local-llm MCP server.
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
# Dependencies: the 'meta' rows of Get-InsightsScope -IncludeRuleMetrics.

# Tool names arrive as mcp__<server>__<tool>. Measured on this machine the
# local-llm server exposes mcp__local-llm__local_llm__<tool> -- the server
# segment is whatever the user wrote in their MCP configuration, so match on the
# tool segment, which the server itself prefixes with local_llm__.
$script:McpLocalLlmPattern = 'local_llm__'

# health is an availability probe, not delegated work. Counting it would inflate
# the delegation figure with calls that produced no output: 2 of the 9 calls in
# the snapshot-3 window were health.
$script:McpLocalLlmProbePattern = 'local_llm__health$'

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
    # Count local-llm delegation: how many work calls went to the server, broken
    # down by tool, with health probes kept separate.
    #
    # Returns an ordered hashtable with ADR-0016's field names. Zero rows yield
    # zeroed counters rather than $null, so callers can merge unconditionally.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()]$Entries,
        [string]$ProjectFilter
    )

    $meta = @($Entries | Where-Object { $_.Role -eq 'meta' })
    if ($ProjectFilter) {
        $meta = @($meta | Where-Object { [string]$_.Cwd -and ([string]$_.Cwd).Contains($ProjectFilter) })
    }

    $byTool = @{}
    $calls = 0
    $probes = 0

    foreach ($row in $meta) {
        $tool = [string]$row.ToolName
        if (-not $tool) { continue }
        if ($tool -notmatch $script:McpLocalLlmPattern) { continue }
        if ($tool -match $script:McpLocalLlmProbePattern) {
            $probes++
            continue
        }
        $calls++
        $short = Get-McpShortToolName -ToolName $tool
        if (-not $byTool.ContainsKey($short)) { $byTool[$short] = 0 }
        $byTool[$short] = $byTool[$short] + 1
    }

    return [ordered]@{
        DelegationLocalLlm       = $calls
        DelegationLocalLlmProbes = $probes
        DelegationLocalLlmByTool = $byTool
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

    return $lines
}
