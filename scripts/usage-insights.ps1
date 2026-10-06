#requires -Version 5.1
# usage-insights.ps1
# Provides: usage analysis over ~/.claude/projects/*.jsonl transcripts, emitting a
#           Markdown insights report (model efficiency, cache efficiency, token
#           waste, stuck candidates, Haiku delegation, cost trend) to ~/.claude/insights/.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0014.
#
# Functions (dot-source friendly; the main body runs only on direct invocation):
#   Get-InsightsScope   - collect transcript entries within the last N days
#   Get-UsageMetrics    - aggregate tokens / cost / cache / stuck / delegation
#   Write-InsightsReport  - write <date>-<kind>.md + latest.md
#
# Dot-sourced from lib/ (split out to stay inside the kit's own 500-line
# file-granularity cap once rule-firing metrics landed; see ADR-0015):
#   lib/insights-report.ps1 - Format-InsightsReport (Markdown rendering)
#   lib/rule-metrics.ps1    - Get-RuleMetrics / New-RuleMetricsRow /
#                             Format-RuleMetricsSection / baseline read+write,
#                             driven by Get-InsightsScope -IncludeRuleMetrics
#
# Scope note: only ~/.claude/projects/ (Claude Code transcripts) are read. Dispatch
# transcripts live outside that tree and are therefore out of scope by construction.

[CmdletBinding()]
param(
    [ValidateSet('Daily', 'Weekly')]
    [string]$Window = 'Weekly',

    [string]$OutputDir,

    [string]$PricingFile,

    # Suppress console chatter (for scheduled-task / unattended runs).
    [switch]$Quiet,

    # Store this run's rule-firing rates as the baseline that later runs compare
    # against (ADR-0015 step 2). Overwrites any existing baseline, so it is opt-in.
    [switch]$WriteBaseline
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = "0.1.0"

# Cross-platform home resolution: this script builds ~/.claude paths from
# $env:USERPROFILE (Windows). On Linux/macOS that is null, so fall back to $HOME
# (matches apply-claude-kit.ps1). Needed for systemd/cron unattended runs where the
# environment is minimal. See engineer-claude-kit Arch adaptation.
if (-not $env:USERPROFILE) { $env:USERPROFILE = $env:HOME }

# UTF-8 (no BOM) file I/O. The report is user-visible markdown, so write it without
# a BOM on every PowerShell version (CP932 default on PS 5.1 would mojibake). See
# ADR-0003 section C. Dot-sourced so the helper functions land in this scope.
. (Join-Path (Join-Path $PSScriptRoot "lib") "encoding-helper.ps1")
# Plain-language hint renderer (Get-PlainLanguageHint). Loaded after the encoding
# helper so its Read-Utf8NoBom dependency is in scope. See ADR-0014.
. (Join-Path (Join-Path $PSScriptRoot "lib") "plain-language.ps1")
# Rule-firing metrics (Get-RuleMetrics / Format-RuleMetricsSection / baseline I/O).
# Loaded after the encoding helper because Write-RuleMetricsBaseline writes via
# Write-Utf8NoBom. See ADR-0015 section E.
. (Join-Path (Join-Path $PSScriptRoot "lib") "rule-metrics.ps1")
# Optional: kit-updater.ps1 (G6b); absent on legacy installs -> banner skipped (ADR-0014 G6h).
$kitUpdaterPath = Join-Path (Join-Path $PSScriptRoot "lib") "kit-updater.ps1"
if (Test-Path -LiteralPath $kitUpdaterPath) { try { . $kitUpdaterPath } catch { } }
# Report renderer (Format-InsightsReport). Loaded last: it calls into
# Get-PlainLanguageHint, Format-KitBehindBanner and Format-RuleMetricsSection, and
# reads $ScriptVersion, all of which are established above.
. (Join-Path (Join-Path $PSScriptRoot "lib") "insights-report.ps1")

# --- helpers ---

function Get-ModelFamily {
    # Map a raw model id (e.g. "claude-opus-4-7") to a pricing family key.
    param([string]$Model)
    if ([string]::IsNullOrWhiteSpace($Model)) { return $null }
    $m = $Model.ToLowerInvariant()
    if ($m -like '*opus*')   { return 'Opus' }
    if ($m -like '*sonnet*') { return 'Sonnet' }
    if ($m -like '*haiku*')  { return 'Haiku' }
    return $null
}

function Import-Pricing {
    # Load pricing.psd1 (concept per-M-token prices). Returns $null if absent so
    # callers can degrade to token-only insights.
    param([string]$Path)
    if (-not $Path) {
        $Path = Join-Path $PSScriptRoot "pricing.psd1"
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Import-PowerShellDataFile -LiteralPath $Path
}

function Get-InsightsScope {
    # Collect normalized transcript entries within the last $WindowDays days.
    # Reads ~/.claude/projects/*/*.jsonl (real transcripts are named <uuid>.jsonl;
    # the historical transcript-*.jsonl pattern is also matched). Returns an array
    # of PSCustomObject rows (Role / Timestamp / Model / token fields / PromptPrefix
    # / SessionId). Robust to malformed lines (skipped) and an absent projects dir.
    #
    # -IncludeRuleMetrics additionally emits one Role='meta' row per transcript row
    # for Get-RuleMetrics (ADR-0015 section E). It is opt-in rather than always on
    # because the 'assistant' and 'user' rows are a stable contract: callers that
    # count rows, and the existing cost / cache / stuck aggregation, must see the
    # exact same array as before. Role='meta' is a third value no existing filter
    # matches, so switching it on adds rows without altering any existing figure.
    param(
        [int]$WindowDays = 7,
        [string]$ProjectsRoot,
        [datetime]$Now,
        [switch]$IncludeRuleMetrics
    )

    if (-not $ProjectsRoot) {
        $ProjectsRoot = Join-Path (Join-Path $env:USERPROFILE ".claude") "projects"
    }
    if (-not $Now) { $Now = Get-Date }
    $cutoff = $Now.ToUniversalTime().AddDays(-$WindowDays)

    $rows = @()
    if (-not (Test-Path -LiteralPath $ProjectsRoot)) { return $rows }

    $files = Get-ChildItem -LiteralPath $ProjectsRoot -Recurse -Filter "*.jsonl" -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        # Cheap pre-filter: skip files untouched since the cutoff entirely.
        if ($file.LastWriteTimeUtc -lt $cutoff) { continue }

        # Read as UTF-8 explicitly. Get-Content without -Encoding decodes with the
        # host ANSI codepage on PS 5.1 (CP932 here), which corrupts every line that
        # carries Japanese text; ConvertFrom-Json then throws and the line is
        # silently dropped by the catch below. Measured on real transcripts: PS 5.1
        # saw 896 user rows and 14 real prompts where PS 7 saw 1,027 and 67, because
        # Japanese-heavy prompt rows were exactly the ones being discarded. ReadLines
        # is UTF-8 by default on both hosts and streams rather than buffering the
        # whole file. See ADR-0003 section C and the P6 encoding fix.
        $lines = @()
        try { $lines = [System.IO.File]::ReadLines($file.FullName) } catch { continue }
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -notmatch '"timestamp"') { continue }

            $obj = $null
            try { $obj = $line | ConvertFrom-Json } catch { continue }
            if ($null -eq $obj -or -not $obj.timestamp) { continue }

            $ts = $null
            try { $ts = ([datetime]$obj.timestamp).ToUniversalTime() } catch { continue }
            if ($ts -lt $cutoff) { continue }

            if ($obj.type -eq 'assistant' -and $obj.message -and $obj.message.usage) {
                $u = $obj.message.usage
                $c1h = 0; $c5m = 0
                if ($u.cache_creation) {
                    $c1h = [int64]($u.cache_creation.ephemeral_1h_input_tokens | ForEach-Object { $_ })
                    $c5m = [int64]($u.cache_creation.ephemeral_5m_input_tokens | ForEach-Object { $_ })
                }
                $rows += [PSCustomObject]@{
                    Role        = 'assistant'
                    Timestamp   = $ts
                    Model       = [string]$obj.message.model
                    Family      = (Get-ModelFamily ([string]$obj.message.model))
                    Input       = [int64]($u.input_tokens             | ForEach-Object { if ($_) { $_ } else { 0 } })
                    Output      = [int64]($u.output_tokens            | ForEach-Object { if ($_) { $_ } else { 0 } })
                    CacheCreate = [int64]($u.cache_creation_input_tokens | ForEach-Object { if ($_) { $_ } else { 0 } })
                    CacheRead   = [int64]($u.cache_read_input_tokens   | ForEach-Object { if ($_) { $_ } else { 0 } })
                    Cache1h     = $c1h
                    Cache5m     = $c5m
                    PromptPrefix = $null
                    SessionId   = [string]$obj.sessionId
                }
            } elseif ($obj.type -eq 'user') {
                # Capture a short prompt prefix for workflow-pattern detection.
                $text = $null
                $content = $obj.message.content
                if ($content -is [string]) {
                    $text = $content
                } elseif ($content) {
                    $first = $content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1
                    if ($first) { $text = [string]$first.text }
                }
                if ($text) {
                    $prefix = ($text -replace '\s+', ' ').Trim()
                    if ($prefix.Length -gt 48) { $prefix = $prefix.Substring(0, 48) }
                    $rows += [PSCustomObject]@{
                        Role         = 'user'
                        Timestamp    = $ts
                        Model        = $null
                        Family       = $null
                        Input        = 0; Output = 0; CacheCreate = 0; CacheRead = 0; Cache1h = 0; Cache5m = 0
                        PromptPrefix = $prefix
                        SessionId    = [string]$obj.sessionId
                    }
                }
            }

            if ($IncludeRuleMetrics) {
                $metaRow = New-RuleMetricsRow -Obj $obj -Timestamp $ts
                if ($metaRow) { $rows += $metaRow }
            }
        }
    }
    return $rows
}


function Get-UsageMetrics {
    # Aggregate normalized rows into an insights hashtable. Pricing is optional;
    # when $null, cost fields are reported as 0 and flagged unavailable.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()]$Entries,
        $Pricing
    )

    $assistant = @($Entries | Where-Object { $_.Role -eq 'assistant' })
    $userRows  = @($Entries | Where-Object { $_.Role -eq 'user' })

    $perModel = @{}
    $totalCost = 0.0
    foreach ($row in $assistant) {
        $fam = $row.Family
        $key = if ($fam) { $fam } else { 'Other' }
        if (-not $perModel.ContainsKey($key)) {
            $perModel[$key] = [ordered]@{
                Family = $key; Turns = 0; Input = 0; Output = 0
                CacheCreate = 0; CacheRead = 0; Cost = 0.0
            }
        }
        $b = $perModel[$key]
        $b.Turns       += 1
        $b.Input       += $row.Input
        $b.Output      += $row.Output
        $b.CacheCreate += $row.CacheCreate
        $b.CacheRead   += $row.CacheRead

        if ($Pricing -and $fam -and $Pricing.ContainsKey($fam)) {
            $p = $Pricing[$fam]
            # cache_creation_input_tokens does not split 1h/5m at the top level, so
            # bill the 1h/5m breakdown when present and fall back to 5m otherwise.
            $writeCost = ($row.Cache1h / 1e6) * $p.cache_write_1h + ($row.Cache5m / 1e6) * $p.cache_write_5m
            $writeRemainder = $row.CacheCreate - $row.Cache1h - $row.Cache5m
            if ($writeRemainder -gt 0) { $writeCost += ($writeRemainder / 1e6) * $p.cache_write_5m }
            $cost = ($row.Input / 1e6) * $p.input +
                    ($row.Output / 1e6) * $p.output +
                    ($row.CacheRead / 1e6) * $p.cache_read +
                    $writeCost
            $b.Cost   += $cost
            $totalCost += $cost
        }
    }

    # Cache efficiency: cold-read share. A cache read is "cold" when the gap from
    # the previous assistant turn in the same session exceeds 5 minutes (the 5m
    # ephemeral TTL), i.e. the cache likely expired and was re-paid.
    $totalRead = 0; $coldRead = 0
    $bySession = $assistant | Group-Object SessionId
    foreach ($grp in $bySession) {
        $sorted = $grp.Group | Sort-Object Timestamp
        $prevTs = $null
        foreach ($row in $sorted) {
            if ($row.CacheRead -gt 0) {
                $totalRead += $row.CacheRead
                if ($null -eq $prevTs -or ($row.Timestamp - $prevTs).TotalMinutes -gt 5) {
                    $coldRead += $row.CacheRead
                }
            }
            $prevTs = $row.Timestamp
        }
    }
    $coldReadPct = if ($totalRead -gt 0) { [math]::Round(100.0 * $coldRead / $totalRead, 1) } else { 0.0 }

    # Stuck candidates: inter-turn gaps within a session that exceed both 5 minutes
    # and (median + 3 sigma) of all gaps. Long pauses that dwarf the typical cadence.
    $gaps = @()
    foreach ($grp in $bySession) {
        $sorted = $grp.Group | Sort-Object Timestamp
        for ($i = 1; $i -lt $sorted.Count; $i++) {
            $gaps += [PSCustomObject]@{
                Minutes   = ($sorted[$i].Timestamp - $sorted[$i-1].Timestamp).TotalMinutes
                Timestamp = $sorted[$i-1].Timestamp
                SessionId = $grp.Name
            }
        }
    }
    $stuck = @()
    if ($gaps.Count -ge 2) {
        $vals = $gaps | ForEach-Object { $_.Minutes }
        $median = Get-Median $vals
        $mean = ($vals | Measure-Object -Average).Average
        $variance = ($vals | ForEach-Object { ($_ - $mean) * ($_ - $mean) } | Measure-Object -Average).Average
        $sigma = [math]::Sqrt($variance)
        $threshold = $median + 3 * $sigma
        $stuck = @($gaps | Where-Object { $_.Minutes -gt 5 -and $_.Minutes -gt $threshold } |
            Sort-Object Minutes -Descending | Select-Object -First 5)
    }

    # Haiku delegation rate.
    $totalTurns = $assistant.Count
    $haikuTurns = @($assistant | Where-Object { $_.Family -eq 'Haiku' }).Count
    $haikuRate = if ($totalTurns -gt 0) { [math]::Round(100.0 * $haikuTurns / $totalTurns, 1) } else { 0.0 }

    # Token-waste score (heuristic, 0-100): share of high-output turns (> 2000
    # output tokens). High output with little structural progress tends to signal
    # discussion-only turns. Documented as relative, not absolute.
    $heavy = @($assistant | Where-Object { $_.Output -gt 2000 }).Count
    $wasteScore = if ($totalTurns -gt 0) { [math]::Round(100.0 * $heavy / $totalTurns, 1) } else { 0.0 }

    # Workflow patterns: frequency of repeated user-prompt prefixes (simple hash).
    $patterns = @()
    if ($userRows.Count -gt 0) {
        $patterns = @($userRows | Where-Object { $_.PromptPrefix } |
            Group-Object PromptPrefix | Where-Object { $_.Count -ge 2 } |
            Sort-Object Count -Descending | Select-Object -First 5 |
            ForEach-Object { [PSCustomObject]@{ Prefix = $_.Name; Count = $_.Count } })
    }

    return [ordered]@{
        WindowTurns = $totalTurns
        UserPrompts = $userRows.Count
        PerModel    = $perModel
        TotalCost   = [math]::Round($totalCost, 4)
        CostAvailable = [bool]$Pricing
        ColdReadPct = $coldReadPct
        TotalReadTokens = $totalRead
        StuckCandidates = $stuck
        HaikuRatePct = $haikuRate
        HaikuTurns  = $haikuTurns
        WasteScore  = $wasteScore
        HeavyTurns  = $heavy
        Patterns    = $patterns
    }
}

function Get-Median {
    param([double[]]$Values)
    if (-not $Values -or $Values.Count -eq 0) { return 0.0 }
    $sorted = $Values | Sort-Object
    $n = $sorted.Count
    if ($n % 2 -eq 1) { return [double]$sorted[($n - 1) / 2] }
    return ([double]$sorted[$n/2 - 1] + [double]$sorted[$n/2]) / 2.0
}

function Get-CostTrend {
    # Compare this window's total cost against the previous same-kind run recorded
    # in <OutputDir>/.cost-history.json. Returns a delta string and updates history.
    param(
        [string]$OutputDir,
        [string]$Kind,
        [double]$TotalCost,
        [string]$DateStr,
        [switch]$NoPersist
    )
    $historyPath = Join-Path $OutputDir ".cost-history.json"
    $history = @()
    if (Test-Path -LiteralPath $historyPath) {
        try { $history = @((Read-Utf8NoBom -Path $historyPath) | ConvertFrom-Json) } catch { $history = @() }
    }
    $prev = @($history | Where-Object { $_.kind -eq $Kind }) | Select-Object -Last 1
    $trend = "n/a (no prior $Kind run)"
    if ($prev) {
        $delta = $TotalCost - [double]$prev.totalCost
        $sign = if ($delta -ge 0) { "+" } else { "-" }
        $trend = "$sign$([math]::Abs([math]::Round($delta, 4))) vs prev $Kind ($($prev.date))"
    }
    if (-not $NoPersist) {
        $history += [PSCustomObject]@{ date = $DateStr; kind = $Kind; totalCost = $TotalCost }
        # Keep history bounded.
        $history = @($history | Select-Object -Last 60)
        Write-Utf8NoBom -Path $historyPath -Content ($history | ConvertTo-Json -Depth 4)
    }
    return $trend
}


function Write-InsightsReport {
    # Write the report to <OutputDir>/<date>-<kind>.md and copy to latest.md.
    param(
        [Parameter(Mandatory)][string]$Report,
        [Parameter(Mandatory)][string]$Kind,
        [string]$OutputDir,
        [string]$DateStr
    )
    if (-not $OutputDir) {
        $OutputDir = Join-Path (Join-Path $env:USERPROFILE ".claude") "insights"
    }
    if (-not $DateStr) { $DateStr = (Get-Date).ToString('yyyy-MM-dd') }
    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    }
    $datedPath = Join-Path $OutputDir "$DateStr-$($Kind.ToLowerInvariant()).md"
    $latestPath = Join-Path $OutputDir "latest.md"
    Write-Utf8NoBom -Path $datedPath -Content $Report
    Write-Utf8NoBom -Path $latestPath -Content $Report
    return $datedPath
}

# --- main ---

function Invoke-UsageInsights {
    param(
        [string]$Window,
        [string]$OutputDir,
        [string]$PricingFile,
        [switch]$Quiet,
        [switch]$WriteBaseline
    )
    $kind = $Window.ToLowerInvariant()
    $windowDays = if ($Window -eq 'Daily') { 1 } else { 7 }
    if (-not $OutputDir) {
        $OutputDir = Join-Path (Join-Path $env:USERPROFILE ".claude") "insights"
    }
    $dateStr = (Get-Date).ToString('yyyy-MM-dd')

    if (-not $Quiet) {
        Write-Host "usage-insights.ps1 v$ScriptVersion ($Window, last $windowDays day(s))"
    }

    $pricing = Import-Pricing -Path $PricingFile
    $entries = Get-InsightsScope -WindowDays $windowDays -IncludeRuleMetrics
    $metrics = Get-UsageMetrics -Entries $entries -Pricing $pricing
    $ruleMetrics = Get-RuleMetrics -Entries $entries

    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    }
    $trend = Get-CostTrend -OutputDir $OutputDir -Kind $kind -TotalCost $metrics.TotalCost -DateStr $dateStr

    # Kit-behind detection (G6h): guarded so legacy installs / network failures omit the banner.
    $kitBehind = -1
    if (Get-Command -Name Test-KitBehind -ErrorAction SilentlyContinue) {
        try { $kitBehind = Test-KitBehind -KitRoot (Split-Path -Parent $PSScriptRoot) } catch { $kitBehind = -1 }
    }

    # Rule-firing baseline (ADR-0015 step 2). Read before writing so a -WriteBaseline
    # run still shows the delta against the baseline it is about to replace.
    $baselinePath = Join-Path $OutputDir "rule-metrics-baseline.json"
    $ruleBaseline = Read-RuleMetricsBaseline -Path $baselinePath

    $report = Format-InsightsReport -Metrics $metrics -Kind $kind -DateStr $dateStr `
        -WindowDays $windowDays -CostTrend $trend -KitBehind $kitBehind `
        -RuleMetrics $ruleMetrics -RuleBaseline $ruleBaseline
    $path = Write-InsightsReport -Report $report -Kind $kind -OutputDir $OutputDir -DateStr $dateStr

    if ($WriteBaseline) {
        $written = Write-RuleMetricsBaseline -Path $baselinePath -RuleMetrics $ruleMetrics `
            -DateStr $dateStr -WindowDays $windowDays
        if (-not $Quiet) { Write-Host "Rule-metrics baseline written: $written" }
    }

    if (-not $Quiet) {
        Write-Host "Report written: $path"
        Write-Host "  Assistant turns: $($metrics.WindowTurns), Haiku rate: $($metrics.HaikuRatePct)%, cold-read: $($metrics.ColdReadPct)%"
        Write-Host "  Rule adherence: plan-first $($ruleMetrics.PlanFirstRate)%, delegation $($ruleMetrics.DelegationRate)%, commit-convention $($ruleMetrics.CommitRate)%"
    }
    return $path
}

# Run main only on direct invocation; dot-sourcing (tests) just loads functions.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-UsageInsights -Window $Window -OutputDir $OutputDir -PricingFile $PricingFile `
        -Quiet:$Quiet -WriteBaseline:$WriteBaseline | Out-Null
}
