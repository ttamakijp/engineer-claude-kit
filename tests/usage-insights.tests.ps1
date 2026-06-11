# usage-insights.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# The script is dot-sourced ONCE at file scope. usage-insights.ps1 guards its
# main body with `$MyInvocation.InvocationName -ne '.'`, so dot-sourcing loads the
# functions WITHOUT running the analysis. Tests build mock transcript JSONL in a
# temp projects dir and drive Get-InsightsScope / Get-UsageMetrics directly. The
# real ~/.claude/projects/ tree is never touched. See ADR-0014.

# $PSScriptRoot can be empty when Invoke-Pester is given a direct file path.
$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path $here "..") "scripts") "usage-insights.ps1"
$PricingPath = Join-Path (Join-Path (Join-Path $here "..") "scripts") "pricing.psd1"

. $ScriptPath

# UTC reference shared across the mock builders. Entries are placed relative to
# this so the per-entry cutoff (Now - WindowDays) admits them while files stay
# fresh enough to pass the LastWriteTime pre-filter.
$script:NowUtc = (Get-Date).ToUniversalTime()

function New-AssistantLine {
    param([string]$Ts, [string]$Sid, [string]$Model, [int]$In, [int]$Out, [int]$Cc, [int]$Cr, [int]$C1h, [int]$C5m)
    $obj = @{
        type = 'assistant'; timestamp = $Ts; sessionId = $Sid
        message = @{
            model = $Model
            usage = @{
                input_tokens = $In; output_tokens = $Out
                cache_creation_input_tokens = $Cc; cache_read_input_tokens = $Cr
                cache_creation = @{ ephemeral_1h_input_tokens = $C1h; ephemeral_5m_input_tokens = $C5m }
            }
        }
    }
    return ($obj | ConvertTo-Json -Compress -Depth 6)
}

function New-UserLine {
    param([string]$Ts, [string]$Sid, [string]$Text)
    $obj = @{ type = 'user'; timestamp = $Ts; sessionId = $Sid; message = @{ content = $Text } }
    return ($obj | ConvertTo-Json -Compress -Depth 6)
}

function New-MockProjects {
    # Write the given JSONL lines into a fresh temp projects/<proj>/<uuid>.jsonl.
    param([string[]]$Lines)
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("ui-test-" + [System.Guid]::NewGuid().ToString("N"))
    $projDir = Join-Path $root "C--mock-project"
    New-Item -ItemType Directory -Force -Path $projDir | Out-Null
    $file = Join-Path $projDir "00000000-0000-0000-0000-000000000000.jsonl"
    [System.IO.File]::WriteAllLines($file, $Lines)
    return $root
}

function Format-Utc {
    param([datetime]$Dt)
    return $Dt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
}

Describe "usage-insights.ps1 loads" {
    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }
    It "parses without syntax errors" {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should Be 0
    }
    It "defines the public functions (dot-sourcing runs no analysis)" {
        (Get-Command Get-InsightsScope -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Get-UsageMetrics -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Format-InsightsReport -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Write-InsightsReport -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }
}

Describe "Get-ModelFamily" {
    It "maps opus / sonnet / haiku ids" {
        (Get-ModelFamily "claude-opus-4-7") | Should Be "Opus"
        (Get-ModelFamily "claude-sonnet-4-6") | Should Be "Sonnet"
        (Get-ModelFamily "claude-haiku-4-5-20251001") | Should Be "Haiku"
    }
    It "returns null for unknown or empty" {
        (Get-ModelFamily "gpt-4") | Should BeNullOrEmpty
        (Get-ModelFamily "") | Should BeNullOrEmpty
    }
}

Describe "Import-Pricing" {
    It "loads pricing.psd1 with the three families and a Note" {
        $p = Import-Pricing -Path $PricingPath
        $p | Should Not BeNullOrEmpty
        $p.ContainsKey("Sonnet") | Should Be $true
        $p.ContainsKey("Haiku") | Should Be $true
        $p.ContainsKey("Opus") | Should Be $true
        $p.Opus.output | Should Be 75.0
        $p.Note | Should Match "relative"
    }
    It "returns null when the file is absent" {
        (Import-Pricing -Path (Join-Path $env:TEMP "no-such-pricing.psd1")) | Should BeNullOrEmpty
    }
}

Describe "Get-InsightsScope" {
    It "returns empty for a missing projects dir" {
        $rows = Get-InsightsScope -WindowDays 7 -ProjectsRoot (Join-Path $env:TEMP "no-such-projects-xyz") -Now $script:NowUtc
        @($rows).Count | Should Be 0
    }
    It "collects assistant and user entries within the window" {
        $lines = @(
            (New-UserLine (Format-Utc $script:NowUtc.AddMinutes(-30)) "s1" "hello there"),
            (New-AssistantLine (Format-Utc $script:NowUtc.AddMinutes(-29)) "s1" "claude-opus-4-7" 10 300 5000 0 5000 0)
        )
        $root = New-MockProjects -Lines $lines
        try {
            $rows = @(Get-InsightsScope -WindowDays 7 -ProjectsRoot $root -Now $script:NowUtc)
            $rows.Count | Should Be 2
            (@($rows | Where-Object { $_.Role -eq 'assistant' })).Count | Should Be 1
            (@($rows | Where-Object { $_.Role -eq 'user' })).Count | Should Be 1
        } finally { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
    }
    It "excludes entries older than the window" {
        $lines = @(
            (New-AssistantLine (Format-Utc $script:NowUtc.AddDays(-3)) "s1" "claude-haiku-4-5" 1 10 0 0 0 0),
            (New-AssistantLine (Format-Utc $script:NowUtc.AddMinutes(-90)) "s1" "claude-haiku-4-5" 1 10 0 0 0 0)
        )
        $root = New-MockProjects -Lines $lines
        try {
            $rows = @(Get-InsightsScope -WindowDays 1 -ProjectsRoot $root -Now $script:NowUtc)
            (@($rows | Where-Object { $_.Role -eq 'assistant' })).Count | Should Be 1
        } finally { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
    }
    It "skips malformed lines without throwing" {
        $lines = @(
            "{ not valid json",
            (New-AssistantLine (Format-Utc $script:NowUtc.AddMinutes(-5)) "s1" "claude-opus-4-7" 1 10 0 0 0 0)
        )
        $root = New-MockProjects -Lines $lines
        try {
            $rows = @(Get-InsightsScope -WindowDays 7 -ProjectsRoot $root -Now $script:NowUtc)
            $rows.Count | Should Be 1
        } finally { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
    }
}

Describe "Get-UsageMetrics aggregation" {
    # Shared dataset: one session mixing opus / haiku / sonnet plus a repeated prompt.
    $lines = @(
        (New-UserLine (Format-Utc $script:NowUtc.AddMinutes(-31)) "s1" "commit the changes please"),
        (New-AssistantLine (Format-Utc $script:NowUtc.AddMinutes(-29)) "s1" "claude-opus-4-7"   10 3000 5000 0 5000 0),
        (New-AssistantLine (Format-Utc $script:NowUtc.AddMinutes(-28)) "s1" "claude-haiku-4-5"   5  100 0 2000 0 0),
        (New-AssistantLine (Format-Utc $script:NowUtc.AddMinutes(-10)) "s1" "claude-sonnet-4-6"  8  500 0 4000 0 0),
        (New-UserLine (Format-Utc $script:NowUtc.AddMinutes(-9)) "s1" "commit the changes please"),
        (New-AssistantLine (Format-Utc $script:NowUtc.AddMinutes(-8)) "s1" "claude-haiku-4-5"     3   50 0 0 0 0)
    )
    $root = New-MockProjects -Lines $lines
    $entries = @(Get-InsightsScope -WindowDays 7 -ProjectsRoot $root -Now $script:NowUtc)
    $pricing = Import-Pricing -Path $PricingPath
    $m = Get-UsageMetrics -Entries $entries -Pricing $pricing
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue

    It "counts assistant turns" {
        $m.WindowTurns | Should Be 4
    }
    It "aggregates per-model output tokens" {
        $m.PerModel["Opus"].Output | Should Be 3000
        $m.PerModel["Haiku"].Output | Should Be 150
        $m.PerModel["Sonnet"].Output | Should Be 500
    }
    It "computes the Haiku delegation rate" {
        $m.HaikuTurns | Should Be 2
        $m.HaikuRatePct | Should Be 50
    }
    It "computes the token-waste score from heavy-output turns" {
        $m.HeavyTurns | Should Be 1
        $m.WasteScore | Should Be 25
    }
    It "computes the cold-read share" {
        $m.TotalReadTokens | Should Be 6000
        $m.ColdReadPct | Should Be 66.7
    }
    It "detects repeated workflow prompt prefixes" {
        @($m.Patterns).Count | Should BeGreaterThan 0
        $m.Patterns[0].Count | Should Be 2
    }
    It "reports cost when pricing is present" {
        $m.CostAvailable | Should Be $true
        $m.TotalCost | Should BeGreaterThan 0
    }
}

Describe "Get-UsageMetrics without pricing" {
    It "flags cost unavailable and reports zero" {
        $lines = @(
            (New-AssistantLine (Format-Utc $script:NowUtc.AddMinutes(-5)) "s1" "claude-opus-4-7" 10 300 0 0 0 0)
        )
        $root = New-MockProjects -Lines $lines
        try {
            $entries = @(Get-InsightsScope -WindowDays 7 -ProjectsRoot $root -Now $script:NowUtc)
            $m = Get-UsageMetrics -Entries $entries -Pricing $null
            $m.CostAvailable | Should Be $false
            $m.TotalCost | Should Be 0
        } finally { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
    }
}

Describe "Get-UsageMetrics stuck detection" {
    It "flags an inter-turn gap that dwarfs the median + 3 sigma" {
        # 12 turns one minute apart, then a 90-minute jump (13th turn): 12 gaps,
        # eleven of 1 min and one of 90 min. With n=12 the lone outlier clears
        # median + 3 sigma.
        $base = $script:NowUtc.AddMinutes(-200)
        $lines = @()
        for ($i = 0; $i -lt 12; $i++) {
            $lines += (New-AssistantLine (Format-Utc $base.AddMinutes($i)) "s1" "claude-haiku-4-5" 1 10 0 0 0 0)
        }
        $lines += (New-AssistantLine (Format-Utc $base.AddMinutes(11 + 90)) "s1" "claude-haiku-4-5" 1 10 0 0 0 0)
        $root = New-MockProjects -Lines $lines
        try {
            $entries = @(Get-InsightsScope -WindowDays 7 -ProjectsRoot $root -Now $script:NowUtc)
            $m = Get-UsageMetrics -Entries $entries -Pricing $null
            @($m.StuckCandidates).Count | Should BeGreaterThan 0
        } finally { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
    }
}

Describe "Format-InsightsReport" {
    It "renders Key findings and a model table" {
        $lines = @(
            (New-AssistantLine (Format-Utc $script:NowUtc.AddMinutes(-5)) "s1" "claude-opus-4-7" 10 300 0 0 0 0)
        )
        $root = New-MockProjects -Lines $lines
        try {
            $entries = @(Get-InsightsScope -WindowDays 7 -ProjectsRoot $root -Now $script:NowUtc)
            $m = Get-UsageMetrics -Entries $entries -Pricing (Import-Pricing -Path $PricingPath)
            $report = Format-InsightsReport -Metrics $m -Kind 'weekly' -DateStr '2026-06-11' -WindowDays 7 -CostTrend 'n/a'
            $report | Should Match "Key findings"
            $report | Should Match "Model usage"
            $report | Should Match "Haiku delegation"
        } finally { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
    }
}

# Plain-language hints (G6g). The Japanese hint text lives in
# scripts/lib/plain-language-hints.json and is rendered as a Markdown blockquote.
# Assertions stay ASCII: they check the blockquote marker (^>) and gating, never
# the translated copy itself.
Describe "Get-PlainLanguageHint" {
    $categories = @('OpusHeavy','HaikuZero','ColdHeavy','WasteHigh','StuckSession','RepeatedPattern','CostRising')

    It "returns a non-empty blockquote for every known category" {
        foreach ($c in $categories) {
            $hint = Get-PlainLanguageHint -Category $c
            $hint | Should Not BeNullOrEmpty
            $hint | Should Match "(?m)^>"
        }
    }
    It "returns empty string for an unknown category" {
        (Get-PlainLanguageHint -Category 'NoSuchCategory') | Should Be ''
    }
    It "returns empty string when the hints file is absent" {
        $missing = Join-Path $env:TEMP "no-such-hints-xyz.json"
        (Get-PlainLanguageHint -Category 'OpusHeavy' -HintsFile $missing) | Should Be ''
    }
    It "begins with a blank line so the blockquote separates from the metric" {
        (Get-PlainLanguageHint -Category 'OpusHeavy').StartsWith("`n") | Should Be $true
    }
}

Describe "Format-InsightsReport plain-language hints" {
    function New-Metrics {
        param($PerModel, $HaikuTurns, $HaikuRate, $Cold, $Waste, $Heavy, $Stuck, $Patterns, $CostAvailable)
        return [ordered]@{
            WindowTurns = 10; UserPrompts = 4
            PerModel = $PerModel
            TotalCost = 9.0; CostAvailable = $CostAvailable
            ColdReadPct = $Cold; TotalReadTokens = 8000
            StuckCandidates = $Stuck
            HaikuRatePct = $HaikuRate; HaikuTurns = $HaikuTurns
            WasteScore = $Waste; HeavyTurns = $Heavy
            Patterns = $Patterns
        }
    }
    $opusHeavyModel = @{
        Opus  = [ordered]@{ Family='Opus';  Turns=9; Input=100; Output=5000; CacheCreate=0; CacheRead=0; Cost=9.0 }
        Haiku = [ordered]@{ Family='Haiku'; Turns=1; Input=10;  Output=50;   CacheCreate=0; CacheRead=0; Cost=0.01 }
    }
    $healthyModel = @{
        Haiku = [ordered]@{ Family='Haiku'; Turns=5; Input=10; Output=50; CacheCreate=0; CacheRead=0; Cost=0.5 }
    }

    It "appends a blockquote when Haiku delegation is zero" {
        $m = New-Metrics $opusHeavyModel 0 0.0 70.0 40.0 4 @([PSCustomObject]@{Minutes=95.0;Timestamp=$script:NowUtc}) @([PSCustomObject]@{Prefix='x';Count=3}) $true
        $report = Format-InsightsReport -Metrics $m -Kind 'weekly' -DateStr '2026-06-11' -WindowDays 7 -CostTrend '+1.5 vs prev weekly (2026-06-04)'
        $report | Should Match "(?m)^>"
        $report | Should Match "Haiku delegation: 0%"
    }
    It "emits an Opus cost share line and OpusHeavy hint when Opus dominates" {
        $m = New-Metrics $opusHeavyModel 0 0.0 70.0 40.0 4 @() @() $true
        $report = Format-InsightsReport -Metrics $m -Kind 'weekly' -DateStr '2026-06-11' -WindowDays 7 -CostTrend 'n/a'
        $report | Should Match "Opus cost share:"
        ([regex]::Matches($report, "(?m)^>")).Count | Should BeGreaterThan 0
    }
    It "omits all hints when every metric is healthy" {
        $m = New-Metrics $healthyModel 3 60.0 0.0 0.0 0 @() @() $true
        $report = Format-InsightsReport -Metrics $m -Kind 'weekly' -DateStr '2026-06-11' -WindowDays 7 -CostTrend '+0 vs prev weekly (2026-06-04)'
        ([regex]::Matches($report, "(?m)^>")).Count | Should Be 0
    }
    It "preserves the technical metric lines alongside the hints" {
        $m = New-Metrics $opusHeavyModel 0 0.0 70.0 40.0 4 @() @() $true
        $report = Format-InsightsReport -Metrics $m -Kind 'weekly' -DateStr '2026-06-11' -WindowDays 7 -CostTrend 'n/a'
        $report | Should Match "Cache cold-read share: 70%"
        $report | Should Match "Token-waste score: 40"
    }
}
