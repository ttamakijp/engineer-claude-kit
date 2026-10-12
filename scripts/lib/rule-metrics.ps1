#requires -Version 5.1
# rule-metrics.ps1
# Provides: rule-firing metrics over the transcript rows collected by
#           Get-InsightsScope -IncludeRuleMetrics (usage-insights.ps1).
# ASCII only (no Japanese in code, comments, or strings). See ADR-0015 section E.
#
# Functions:
#   Get-RuleMetrics            - aggregate M1 / M2 / M3 from 'meta' rows
#   Format-RuleMetricsSection  - render the metrics as a Markdown section
#   Read-RuleMetricsBaseline   - load a stored baseline (or $null)
#   Write-RuleMetricsBaseline  - store the current metrics as the baseline
#
# Why a separate file: usage-insights.ps1 sits at the 500-line hard cap of the
# kit's own file-granularity rule, so this logic is dot-sourced instead of
# appended. Mirrors the models-config.ps1 / plain-language.ps1 extractions.
#
# Measurement model (why 'meta' rows exist at all):
# An assistant message is written to the transcript as ONE JSONL ROW PER CONTENT
# BLOCK (thinking, text, tool_use), not one row per turn. Reconstructing a
# logical turn therefore means grouping consecutive assistant rows by requestId.
# Measured on real transcripts: 1,775 assistant rows collapsed to 992 logical
# turns. Anchoring a metric on "the first assistant row after a prompt" sees the
# thinking block and finds text in 1 of 70 cases; the same metric at logical-turn
# level finds it in 38 of 69. Every metric below is defined on logical turns.
#
# These metrics are PROXIES for instruction adherence, not ground truth: the
# transcript records no trace of which instruction files were loaded. They exist
# to compare a baseline against a later window, so treat the delta as the signal
# and the absolute value as indicative only.

# Tool names that count as a sub-agent launch. The harness names this tool 'Agent'
# in some builds and 'Task' in others; match both so the metric does not silently
# read zero on one of them.
$script:RuleMetricsAgentTools = @('Agent', 'Task')

# Sub-agents that CLAUDE.md section 3.1 designates for mandatory delegation.
$script:RuleMetricsHaikuAgents = @('commit-msg', 'lint-helper', 'log-summary')

# Shell tools whose command text is inspected for 'git commit'.
$script:RuleMetricsShellTools = @('Bash', 'PowerShell')

# Tools that mutate files; used by the strict variant of M1.
$script:RuleMetricsEditTools = @('Edit', 'Write', 'NotebookEdit')

# A tool result at or above this size is treated as log-summary eligible. Chosen
# from the observed distribution of result sizes (median 1,338 chars, p90 8,324),
# so the threshold selects roughly the top decile rather than a round guess.
$script:RuleMetricsLargeResultChars = 8000

# Conventional Commits subject form: type(scope)?!?: description
$script:RuleMetricsCCPattern = '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?: .+'

# 'git commit' only counts at a command position: the start of the command, the
# start of a line, or immediately after a shell separator. Matching the bare
# phrase anywhere picked up prose and source code that merely mention it (a
# patch script whose replacement text contained the words, for instance), which
# then scored a line of code as a non-conforming commit subject.
$script:RuleMetricsGitCommitPattern = '(?m)(^|[;&|(]\s*)\s*git\s+commit\b'

function Get-CommitSubject {
    # Extract the subject line from a shell command that runs git commit.
    # Returns $null when no subject is present in the command text (for example
    # 'git commit --amend --no-edit', or a message piped in from a file).
    param([string]$Command)

    if (-not $Command) { return $null }
    if ($Command -notmatch $script:RuleMetricsGitCommitPattern) { return $null }

    # -m "subject" / -m 'subject'. The character class excludes newlines on
    # purpose: [^"] runs happily past the end of the line and swallows a whole
    # heredoc body, which turned conforming commits into apparent violations on
    # the 'git commit -m "$(cat <<TAG ... )"' form.
    $inline = $null
    if ($Command -match 'git\s+commit[^\r\n]*?-m\s+"([^"\r\n]+)"') { $inline = $Matches[1] }
    elseif ($Command -match "git\s+commit[^\r\n]*?-m\s+'([^'\r\n]+)'") { $inline = $Matches[1] }

    # A capture that only opens a command substitution is not the subject; the
    # real subject is the first line of the heredoc it reads from, handled below.
    if ($inline -and $inline -notmatch '^\s*\$\(') { return $inline }

    # Multi-line forms where the message arrives on stdin or through a heredoc
    # ('-F -', or -m "$(cat <<TAG ...)"): the subject is the first non-empty line
    # after the line that launches git commit.
    $lines = $Command -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $script:RuleMetricsGitCommitPattern) {
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                if ($lines[$j].Trim()) { return $lines[$j].Trim() }
            }
            break
        }
    }
    return $null
}

function Get-RuleMetrics {
    # Aggregate rule-firing metrics from the 'meta' rows of Get-InsightsScope.
    # Rows of any other Role are ignored, so passing the full entry array is safe.
    # Returns an ordered hashtable; Eligible counts of 0 yield a rate of 0.0 and
    # an Available flag of $false so the report can say "not exercised" rather
    # than implying 0% adherence.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()]$Entries
    )

    $meta = @($Entries | Where-Object { $_.Role -eq 'meta' })

    # ---- M1: plan-first rate (CLAUDE.md section 2) ----
    # For each real user prompt, reconstruct the first logical turn that follows
    # it and check whether a text block precedes the first tool_use.
    $m1Eligible = 0; $m1Hit = 0; $m1StrictHit = 0
    foreach ($group in ($meta | Group-Object SessionId)) {
        $rows = @($group.Group | Sort-Object Timestamp, BlockIndex)
        for ($i = 0; $i -lt $rows.Count; $i++) {
            if (-not $rows[$i].IsUserPrompt) { continue }

            # Find the first assistant row after this prompt and take its turn id.
            $j = $i + 1
            while ($j -lt $rows.Count -and $rows[$j].Kind -ne 'assistant') { $j++ }
            if ($j -ge $rows.Count) { continue }
            $turnId = [string]$rows[$j].RequestId
            if (-not $turnId) { continue }

            $m1Eligible++
            $textAt = -1; $toolAt = -1; $hasEdit = $false
            $k = $j; $pos = 0
            while ($k -lt $rows.Count -and [string]$rows[$k].RequestId -eq $turnId) {
                $bt = [string]$rows[$k].BlockType
                if ($bt -eq 'text' -and $textAt -lt 0) { $textAt = $pos }
                if ($bt -eq 'tool_use') {
                    if ($toolAt -lt 0) { $toolAt = $pos }
                    if ($script:RuleMetricsEditTools -contains [string]$rows[$k].ToolName) { $hasEdit = $true }
                }
                $pos++
                $k++
            }
            $textFirst = ($textAt -ge 0) -and (($toolAt -lt 0) -or ($textAt -lt $toolAt))
            if ($textFirst) {
                $m1Hit++
                if (-not $hasEdit) { $m1StrictHit++ }
            }
        }
    }

    # ---- M2: Haiku delegation rate (CLAUDE.md section 3.1) ----
    $m2CommitEligible = 0; $m2LogEligible = 0
    $m2Delegations = @{}
    foreach ($agent in $script:RuleMetricsHaikuAgents) { $m2Delegations[$agent] = 0 }
    $m2Other = 0

    # ---- M3: Conventional Commits adherence (commit-convention rule) ----
    $m3Total = 0; $m3Extracted = 0; $m3Conforming = 0
    $m3Offenders = @()

    foreach ($row in $meta) {
        $tool = [string]$row.ToolName

        if ($script:RuleMetricsAgentTools -contains $tool) {
            $sub = [string]$row.SubagentType
            if ($script:RuleMetricsHaikuAgents -contains $sub) {
                $m2Delegations[$sub] = $m2Delegations[$sub] + 1
            } elseif ($sub) {
                $m2Other++
            }
        }

        if ($script:RuleMetricsShellTools -contains $tool) {
            $cmd = [string]$row.BashCommand
            if ($cmd -match $script:RuleMetricsGitCommitPattern) {
                $m2CommitEligible++
                $m3Total++
                $subject = Get-CommitSubject -Command $cmd
                if ($subject) {
                    $m3Extracted++
                    if ($subject -match $script:RuleMetricsCCPattern) {
                        $m3Conforming++
                    } elseif ($m3Offenders.Count -lt 5) {
                        # Collapse whitespace before sampling: a stray newline here
                        # would break the Markdown list the report renders.
                        $trimmed = ($subject -replace '\s+', ' ').Trim()
                        if ($trimmed.Length -gt 60) { $trimmed = $trimmed.Substring(0, 60) }
                        $m3Offenders += $trimmed
                    }
                }
            }
        }

        if ([int]$row.ResultChars -ge $script:RuleMetricsLargeResultChars) { $m2LogEligible++ }
    }

    $m2Hit = 0
    foreach ($agent in $script:RuleMetricsHaikuAgents) { $m2Hit += $m2Delegations[$agent] }
    $m2Eligible = $m2CommitEligible + $m2LogEligible

    return [ordered]@{
        Available          = ($meta.Count -gt 0)
        MetaRows           = $meta.Count

        PlanFirstEligible  = $m1Eligible
        PlanFirstHits      = $m1Hit
        PlanFirstStrict    = $m1StrictHit
        PlanFirstRate      = (Get-RuleRate -Hits $m1Hit -Eligible $m1Eligible)
        PlanFirstStrictRate = (Get-RuleRate -Hits $m1StrictHit -Eligible $m1Eligible)

        DelegationEligible = $m2Eligible
        DelegationCommitEligible = $m2CommitEligible
        DelegationLogEligible    = $m2LogEligible
        DelegationHits     = $m2Hit
        DelegationByAgent  = $m2Delegations
        DelegationOther    = $m2Other
        DelegationRate     = (Get-RuleRate -Hits $m2Hit -Eligible $m2Eligible)

        CommitTotal        = $m3Total
        CommitExtracted    = $m3Extracted
        CommitConforming   = $m3Conforming
        CommitRate         = (Get-RuleRate -Hits $m3Conforming -Eligible $m3Extracted)
        CommitOffenders    = $m3Offenders
    }
}

function Get-RuleRate {
    # Percentage with one decimal; 0.0 when the denominator is 0 (never divide).
    param([int]$Hits, [int]$Eligible)
    if ($Eligible -le 0) { return 0.0 }
    return [math]::Round(100.0 * $Hits / $Eligible, 1)
}

function Get-RuleVerdict {
    # Map an adherence rate to a coarse status used by the reduction decision in
    # ADR-0015 step 5. 'not exercised' is deliberately distinct from 'unmet': a
    # rule with no eligible events tells us nothing and must not be deleted on
    # that basis.
    param([double]$Rate, [int]$Eligible)
    if ($Eligible -le 0) { return 'not exercised' }
    if ($Rate -ge 80) { return 'met' }
    if ($Rate -ge 30) { return 'partial' }
    return 'unmet'
}

function Format-RuleMetricsSection {
    # Render the rule-firing metrics as a Markdown section. When a baseline is
    # supplied, each rate also carries its delta against the baseline so the
    # post-reduction comparison in ADR-0015 step 5 is readable at a glance.
    param(
        [Parameter(Mandatory)]$RuleMetrics,
        $Baseline
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("## Rule firing metrics")
    [void]$sb.AppendLine("")

    if (-not $RuleMetrics.Available) {
        [void]$sb.AppendLine("- No transcript rows in scope; metrics unavailable for this window.")
        [void]$sb.AppendLine("")
        return $sb.ToString()
    }

    [void]$sb.AppendLine("| Rule | Adherence | Eligible | Status |")
    [void]$sb.AppendLine("|---|---|---|---|")

    $specs = @(
        [ordered]@{ Key = 'PlanFirstRate';  Name = 'plan-first (CLAUDE.md 2)';     Hits = $RuleMetrics.PlanFirstHits;    Eligible = $RuleMetrics.PlanFirstEligible },
        [ordered]@{ Key = 'DelegationRate'; Name = 'haiku-delegation (CLAUDE.md 3.1)'; Hits = $RuleMetrics.DelegationHits; Eligible = $RuleMetrics.DelegationEligible },
        [ordered]@{ Key = 'CommitRate';     Name = 'commit-convention';            Hits = $RuleMetrics.CommitConforming; Eligible = $RuleMetrics.CommitExtracted }
    )

    foreach ($spec in $specs) {
        $rate = [double]$RuleMetrics[$spec.Key]
        $verdict = Get-RuleVerdict -Rate $rate -Eligible $spec.Eligible
        $delta = ''
        $baseProp = $null
        if ($Baseline) { $baseProp = $Baseline.PSObject.Properties[$spec.Key] }
        if ($baseProp -and $null -ne $baseProp.Value) {
            $diff = [math]::Round($rate - [double]$baseProp.Value, 1)
            if ($diff -gt 0) { $delta = " (+$diff pt)" }
            elseif ($diff -lt 0) { $delta = " ($diff pt)" }
            else { $delta = " (+/-0 pt)" }
        }
        [void]$sb.AppendLine("| $($spec.Name) | $rate%$delta | $($spec.Hits)/$($spec.Eligible) | $verdict |")
    }
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("Detail:")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- plan-first strict (no Edit/Write in the same turn): $($RuleMetrics.PlanFirstStrictRate)% ($($RuleMetrics.PlanFirstStrict)/$($RuleMetrics.PlanFirstEligible))")
    $byAgent = @()
    foreach ($agent in ($RuleMetrics.DelegationByAgent.Keys | Sort-Object)) {
        $byAgent += ("$agent=" + $RuleMetrics.DelegationByAgent[$agent])
    }
    [void]$sb.AppendLine("- delegation by sub-agent: $($byAgent -join ', ') (other sub-agents: $($RuleMetrics.DelegationOther))")
    [void]$sb.AppendLine("- delegation eligibility split: git-commit=$($RuleMetrics.DelegationCommitEligible), large-output=$($RuleMetrics.DelegationLogEligible)")
    $unextractable = $RuleMetrics.CommitTotal - $RuleMetrics.CommitExtracted
    [void]$sb.AppendLine("- commit subjects: $($RuleMetrics.CommitExtracted) extracted of $($RuleMetrics.CommitTotal) git-commit calls ($unextractable without an inline subject)")
    if ($RuleMetrics.CommitOffenders.Count -gt 0) {
        $samples = @()
        foreach ($o in $RuleMetrics.CommitOffenders) { $samples += ($o -replace '\|', '\|') }
        [void]$sb.AppendLine("- non-conforming subjects (sample): $($samples -join ' / ')")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("These are proxies, not ground truth: the transcript records no trace of which")
    [void]$sb.AppendLine("instruction files were loaded. Read the delta against the baseline, not the")
    [void]$sb.AppendLine("absolute value. 'not exercised' means no eligible event occurred and is never")
    [void]$sb.AppendLine("evidence that a rule can be deleted. See ADR-0015 section E.")
    [void]$sb.AppendLine("")
    return $sb.ToString()
}

function Read-RuleMetricsBaseline {
    # Load the stored baseline. Returns $null when absent or unreadable so the
    # report simply omits deltas instead of failing the run.
    param([string]$Path)
    if (-not $Path) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-RuleMetricsBaseline {
    # Persist the current rates as the baseline for later comparison. Only the
    # three rates plus provenance are stored; the full metric object is not, so a
    # later schema change cannot make an old baseline unreadable.
    #
    # Two files are written: $Path is the active comparison target (overwritten
    # each time), and a dated sibling is kept as an archive. ADR-0015 compares
    # three snapshots -- before distribution, after distribution, after reduction
    # -- to separate the effect of deploying rules from the effect of trimming
    # them, which a single overwritten file cannot support.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$RuleMetrics,
        [string]$DateStr,
        [int]$WindowDays = 7,
        [switch]$NoArchive
    )
    if (-not $DateStr) { $DateStr = (Get-Date).ToString('yyyy-MM-dd') }
    $payload = [ordered]@{
        RecordedOn          = $DateStr
        WindowDays          = $WindowDays
        PlanFirstRate       = $RuleMetrics.PlanFirstRate
        PlanFirstStrictRate = $RuleMetrics.PlanFirstStrictRate
        PlanFirstEligible   = $RuleMetrics.PlanFirstEligible
        DelegationRate      = $RuleMetrics.DelegationRate
        DelegationEligible  = $RuleMetrics.DelegationEligible
        CommitRate          = $RuleMetrics.CommitRate
        CommitExtracted     = $RuleMetrics.CommitExtracted
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $json = $payload | ConvertTo-Json -Depth 3
    Write-Utf8NoBom -Path $Path -Content $json

    if (-not $NoArchive) {
        # <name>-<date>.json beside the active baseline. Re-running on the same
        # day replaces that day's archive, which keeps one entry per day rather
        # than one per invocation.
        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $ext = [System.IO.Path]::GetExtension($Path)
        $archiveName = "$leaf-$DateStr$ext"
        $archive = if ($dir) { Join-Path $dir $archiveName } else { $archiveName }
        if ($archive -ne $Path) { Write-Utf8NoBom -Path $archive -Content $json }
    }
    return $Path
}

function New-RuleMetricsRow {
    # Project one transcript row into the flat shape Get-RuleMetrics consumes.
    # Returns $null for rows that carry nothing a rule metric looks at.
    #
    # An assistant message occupies one row PER CONTENT BLOCK, so BlockType is
    # singular here and the logical turn is rebuilt downstream by grouping on
    # RequestId. See the measurement note in lib/rule-metrics.ps1.
    param(
        [Parameter(Mandatory)]$Obj,
        [Parameter(Mandatory)][datetime]$Timestamp
    )

    $kind = [string]$Obj.type
    if ($kind -ne 'assistant' -and $kind -ne 'user') { return $null }

    $blockType = ''
    $toolName = ''
    $subagentType = ''
    $bashCommand = ''
    $textHead = ''
    $isUserPrompt = $false
    $resultChars = 0

    if ($kind -eq 'assistant') {
        # One block per row in practice; loop anyway so a multi-block row (older
        # transcript formats) still reports its tool_use rather than being skipped.
        foreach ($block in @($Obj.message.content)) {
            $bt = [string]$block.type
            if (-not $blockType) { $blockType = $bt }
            if ($bt -eq 'text' -and -not $textHead) {
                $head = ''
                foreach ($candidate in (([string]$block.text) -split "`r?`n")) {
                    if ($candidate.Trim()) { $head = $candidate.Trim(); break }
                }
                if ($head.Length -gt 160) { $head = $head.Substring(0, 160) }
                $textHead = $head
            }
            if ($bt -eq 'tool_use') {
                $blockType = 'tool_use'
                $toolName = [string]$block.name
                if ($block.input) {
                    if ($block.input.subagent_type) { $subagentType = [string]$block.input.subagent_type }
                    if ($block.input.command) { $bashCommand = [string]$block.input.command }
                }
            }
        }
    } else {
        # A user row is either a real prompt or the carrier of a tool result. Only
        # real prompts anchor the plan-first metric, and only tool results feed the
        # large-output eligibility count.
        $isToolResult = [bool]$Obj.toolUseResult
        $content = $Obj.message.content
        if (-not $isToolResult -and $content -isnot [string]) {
            foreach ($block in @($content)) {
                if ([string]$block.type -eq 'tool_result') { $isToolResult = $true }
            }
        }
        if ($isToolResult) {
            if ($Obj.toolUseResult) {
                try {
                    $resultChars = ($Obj.toolUseResult | ConvertTo-Json -Depth 4 -Compress).Length
                } catch {
                    $resultChars = 0
                }
            }
        } elseif ($content) {
            $isUserPrompt = $true
        }
    }

    return [PSCustomObject]@{
        Role         = 'meta'
        Kind         = $kind
        Timestamp    = $Timestamp
        SessionId    = [string]$Obj.sessionId
        RequestId    = [string]$Obj.requestId
        BlockIndex   = [int]($Obj.apiBlockIndex | ForEach-Object { if ($_) { $_ } else { 0 } })
        IsSidechain  = [bool]$Obj.isSidechain
        BlockType    = $blockType
        ToolName     = $toolName
        SubagentType = $subagentType
        BashCommand  = $bashCommand
        TextHead     = $textHead
        IsUserPrompt = $isUserPrompt
        ResultChars  = $resultChars
    }
}
