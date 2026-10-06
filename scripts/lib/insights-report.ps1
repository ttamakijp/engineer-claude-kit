#requires -Version 5.1
# insights-report.ps1
# Provides: Format-InsightsReport - render Get-UsageMetrics (and, when supplied,
#           Get-RuleMetrics) output as the Markdown insights report body.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0014 / ADR-0015.
#
# Why a separate file: usage-insights.ps1 reached the 500-line hard cap of the
# kit's own file-granularity rule once rule-firing metrics were added, so the
# rendering concern was split from collection and aggregation. Dot-sourced by
# usage-insights.ps1 AFTER $ScriptVersion, plain-language.ps1 and kit-updater.ps1,
# all of which this renderer references at call time.

function Format-InsightsReport {
    # Render metrics as a Markdown report string.
    param(
        [Parameter(Mandatory)]$Metrics,
        [string]$Kind = 'weekly',
        [string]$DateStr,
        [int]$WindowDays = 7,
        [string]$CostTrend = 'n/a',
        [int]$KitBehind = -1,  # commits behind origin; >0 prepends a banner, <=0 omits it
        $RuleMetrics,          # Get-RuleMetrics output; $null omits the section entirely
        $RuleBaseline          # stored baseline for delta columns; $null omits deltas
    )
    if (-not $DateStr) { $DateStr = (Get-Date).ToString('yyyy-MM-dd') }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Usage Insights ($DateStr, $Kind)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Window: last $WindowDays day(s). Assistant turns: $($Metrics.WindowTurns). User prompts: $($Metrics.UserPrompts).")
    [void]$sb.AppendLine("")

    if ($KitBehind -gt 0) { [void]$sb.AppendLine((Format-KitBehindBanner -KitBehind $KitBehind)); [void]$sb.AppendLine("") }  # G6h kit-behind banner

    # Append a plain-language blockquote (Get-PlainLanguageHint) after a finding when
    # that finding's condition holds. The technical metric line is always emitted
    # separately first; the hint augments it, never replaces it. See ADR-0014.
    $appendHint = {
        param([bool]$When, [string]$Cat)
        if ($When) { [void]$sb.AppendLine((Get-PlainLanguageHint -Category $Cat)) }
    }

    # Opus share of model cost (drives the OpusHeavy hint; cost-aware only).
    $opusCost = 0.0; $modelCost = 0.0
    foreach ($k in $Metrics.PerModel.Keys) {
        $modelCost += [double]$Metrics.PerModel[$k].Cost
        if ($k -eq 'Opus') { $opusCost = [double]$Metrics.PerModel[$k].Cost }
    }
    $opusPct = if ($modelCost -gt 0) { [math]::Round(100.0 * $opusCost / $modelCost, 1) } else { 0.0 }
    $costRising = $CostTrend.StartsWith('+') -and ($CostTrend -notmatch '^\+0(\.0+)?\s')

    # Key findings (first 3-5 lines are what the session-start hint surfaces).
    [void]$sb.AppendLine("## Key findings")
    [void]$sb.AppendLine("")
    $costLine = if ($Metrics.CostAvailable) { "Est. cost: USD $($Metrics.TotalCost) ($CostTrend)" } else { "Est. cost: unavailable (pricing.psd1 not loaded)" }
    [void]$sb.AppendLine("- $costLine")
    & $appendHint ($Metrics.CostAvailable -and $costRising) 'CostRising'
    if ($Metrics.CostAvailable) {
        [void]$sb.AppendLine("- Opus cost share: $opusPct% of model cost")
        & $appendHint ($opusPct -ge 60) 'OpusHeavy'
    }
    [void]$sb.AppendLine("- Haiku delegation: $($Metrics.HaikuRatePct)% ($($Metrics.HaikuTurns)/$($Metrics.WindowTurns) turns)")
    & $appendHint ($Metrics.WindowTurns -gt 0 -and $Metrics.HaikuTurns -eq 0) 'HaikuZero'
    [void]$sb.AppendLine("- Cache cold-read share: $($Metrics.ColdReadPct)% (higher = more cache misses)")
    & $appendHint ($Metrics.ColdReadPct -ge 50) 'ColdHeavy'
    [void]$sb.AppendLine("- Token-waste score: $($Metrics.WasteScore)/100 ($($Metrics.HeavyTurns) heavy-output turns)")
    & $appendHint ($Metrics.WasteScore -ge 30) 'WasteHigh'
    [void]$sb.AppendLine("- Stuck candidates: $($Metrics.StuckCandidates.Count)")
    & $appendHint ($Metrics.StuckCandidates.Count -gt 0) 'StuckSession'
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("## Model usage")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Model | Turns | Input | Output | CacheCreate | CacheRead | Est. Cost (USD) |")
    [void]$sb.AppendLine("|---|---|---|---|---|---|---|")
    foreach ($key in ($Metrics.PerModel.Keys | Sort-Object)) {
        $b = $Metrics.PerModel[$key]
        [void]$sb.AppendLine("| $($b.Family) | $($b.Turns) | $($b.Input) | $($b.Output) | $($b.CacheCreate) | $($b.CacheRead) | $([math]::Round($b.Cost, 4)) |")
    }
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("## Cache efficiency")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- Total cache-read tokens: $($Metrics.TotalReadTokens)")
    [void]$sb.AppendLine("- Cold-read share: $($Metrics.ColdReadPct)% (reads >5min after the prior turn; likely re-paid)")
    [void]$sb.AppendLine("")

    if ($Metrics.StuckCandidates.Count -gt 0) {
        [void]$sb.AppendLine("## Stuck candidates")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| Gap (min) | After turn at |")
        [void]$sb.AppendLine("|---|---|")
        foreach ($s in $Metrics.StuckCandidates) {
            [void]$sb.AppendLine("| $([math]::Round($s.Minutes, 1)) | $($s.Timestamp.ToString('yyyy-MM-dd HH:mm')) |")
        }
        [void]$sb.AppendLine("")
    }

    if ($Metrics.Patterns.Count -gt 0) {
        [void]$sb.AppendLine("## Repeated workflow prompts")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| Count | Prompt prefix |")
        [void]$sb.AppendLine("|---|---|")
        foreach ($p in $Metrics.Patterns) {
            $safe = ($p.Prefix -replace '\|', '\|')
            [void]$sb.AppendLine("| $($p.Count) | $safe |")
        }
        & $appendHint $true 'RepeatedPattern'
        [void]$sb.AppendLine("")
    }

    # Rule-firing metrics (ADR-0015). Omitted when the caller did not collect them,
    # so an older caller sees byte-identical output.
    if ($RuleMetrics) {
        [void]$sb.Append((Format-RuleMetricsSection -RuleMetrics $RuleMetrics -Baseline $RuleBaseline))
    }

    [void]$sb.AppendLine("## Notes")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- Source: ~/.claude/projects/*.jsonl (Claude Code transcripts; Dispatch out of scope)")
    [void]$sb.AppendLine("- Pricing: scripts/pricing.psd1 (concept figures, web confirmation pending)")
    [void]$sb.AppendLine("- Generated by usage-insights.ps1 v$ScriptVersion")
    return $sb.ToString()
}
