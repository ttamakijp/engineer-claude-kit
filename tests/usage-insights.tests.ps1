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
    # Derived from the data file rather than hard-coded: a hard-coded list is how
    # this test broke when HaikuZero was removed, and it would not have caught a
    # newly added category with no text at all.
    $hintsPath = Join-Path (Join-Path (Join-Path (Join-Path $here "..") "scripts") "lib") "plain-language-hints.json"
    $categories = @((Read-Utf8NoBom -Path $hintsPath | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { $_.Name } | Where-Object { $_ -ne 'KitBehind' })

    It "covers more than one category" {
        # Guards against the list silently collapsing to empty, which would make
        # the next assertion pass without testing anything.
        $categories.Count | Should BeGreaterThan 1
    }
    # HaikuZero told the user to delegate commit messages to Haiku, which
    # CLAUDE.md section 3 now forbids as more expensive than writing them
    # directly. It must not come back (ADR-0016).
    It "no longer ships a hint that contradicts the delegation guidance" {
        $categories -contains 'HaikuZero' | Should Be $false
        (Get-PlainLanguageHint -Category 'HaikuZero') | Should Be ''
    }
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

# Kit-behind banner (G6h). Format-InsightsReport is kept pure: it renders the banner
# only from the -KitBehind int passed in (Test-KitBehind runs in Invoke-UsageInsights,
# not here), so these assertions are deterministic and never touch the network.
# A healthy metrics set is used so the ONLY possible blockquote is the kit banner.
Describe "Format-InsightsReport kit-behind banner" {
    $healthy = [ordered]@{
        WindowTurns = 5; UserPrompts = 2
        PerModel = @{ Haiku = [ordered]@{ Family='Haiku'; Turns=5; Input=10; Output=50; CacheCreate=0; CacheRead=0; Cost=0.5 } }
        TotalCost = 0.5; CostAvailable = $true
        ColdReadPct = 0.0; TotalReadTokens = 0
        StuckCandidates = @()
        HaikuRatePct = 60.0; HaikuTurns = 3
        WasteScore = 0.0; HeavyTurns = 0
        Patterns = @()
    }

    It "prepends the banner with a blockquote when behind by 5 commits" {
        $report = Format-InsightsReport -Metrics $healthy -Kind 'weekly' -DateStr '2026-06-11' -WindowDays 7 -CostTrend 'n/a' -KitBehind 5
        $report | Should Match "Kit update available \(5 commits behind\)"
        $report | Should Match "(?m)^>"
        # The banner sits before Key findings (report opening).
        $report.IndexOf("Kit update available") | Should BeLessThan ($report.IndexOf("Key findings"))
    }
    It "omits the banner when up to date (behind=0)" {
        $report = Format-InsightsReport -Metrics $healthy -Kind 'weekly' -DateStr '2026-06-11' -WindowDays 7 -CostTrend 'n/a' -KitBehind 0
        $report | Should Not Match "Kit update available"
        ([regex]::Matches($report, "(?m)^>")).Count | Should Be 0
    }
    It "omits the banner when detection failed (behind=-1)" {
        $report = Format-InsightsReport -Metrics $healthy -Kind 'weekly' -DateStr '2026-06-11' -WindowDays 7 -CostTrend 'n/a' -KitBehind -1
        $report | Should Not Match "Kit update available"
    }
    It "omits the banner by default (silent skip when -KitBehind not supplied)" {
        # Models the legacy-install / Test-KitBehind-absent path: Invoke-UsageInsights
        # leaves $kitBehind at its -1 default, which Format-InsightsReport renders as no banner.
        $report = Format-InsightsReport -Metrics $healthy -Kind 'weekly' -DateStr '2026-06-11' -WindowDays 7 -CostTrend 'n/a'
        $report | Should Not Match "Kit update available"
    }
}

Describe "Format-KitBehindBanner" {
    It "returns empty for non-positive counts" {
        (Format-KitBehindBanner -KitBehind 0)  | Should Be ''
        (Format-KitBehindBanner -KitBehind -1) | Should Be ''
    }
    It "uses the singular 'commit' for a behind count of 1" {
        $b = Format-KitBehindBanner -KitBehind 1
        $b | Should Match "Kit update available \(1 commit behind\)"
        $b | Should Not Match "1 commits behind"
    }
    It "uses the plural 'commits' for counts above 1" {
        (Format-KitBehindBanner -KitBehind 3) | Should Match "3 commits behind"
    }
}

Describe "Get-PlainLanguageHint metrics placeholder" {
    It "substitutes {Behind} from the -Metrics hashtable" {
        $hint = Get-PlainLanguageHint -Category 'KitBehind' -Metrics @{ Behind = 7 }
        $hint | Should Not BeNullOrEmpty
        $hint | Should Not Match "\{Behind\}"
        $hint | Should Match "7"
    }
    It "leaves the placeholder intact when no metrics are supplied" {
        (Get-PlainLanguageHint -Category 'KitBehind') | Should Match "\{Behind\}"
    }
}

Describe "Get-CostTrend history parsing" {
    # Regression: the history file was read with
    #   @((Read-Utf8NoBom $p) | ConvertFrom-Json)
    # and PS 5.1 emits a JSON ARRAY as ONE object instead of enumerating it, so
    # that expression produced a 1-element array holding the whole list. With 0
    # entries there is no previous run and with exactly 1 entry ConvertFrom-Json
    # returns a single object, so the defect only surfaced from the THIRD run on:
    # $prev became the whole Object[], $prev.totalCost an Object[], and [double]
    # on it threw "Cannot convert System.Object[] to System.Double", aborting the
    # whole report over a cosmetic trend line. These cases pin each entry count.

    function New-HistoryDir {
        param([int]$Entries)
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("ct-test-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        if ($Entries -gt 0) {
            $rows = @()
            for ($i = 1; $i -le $Entries; $i++) {
                $rows += [PSCustomObject]@{ date = ("2026-10-{0:d2}" -f $i); kind = 'weekly'; totalCost = (100.0 * $i) }
            }
            Write-Utf8NoBom -Path (Join-Path $dir ".cost-history.json") -Content ($rows | ConvertTo-Json -Depth 4)
        }
        return $dir
    }

    It "reports n/a when no history exists" {
        $dir = New-HistoryDir -Entries 0
        $t = Get-CostTrend -OutputDir $dir -Kind 'weekly' -TotalCost 50 -DateStr '2026-10-15' -NoPersist
        $t | Should Match 'no prior weekly run'
        Remove-Item -Recurse -Force $dir
    }
    It "computes the delta against a single prior entry" {
        $dir = New-HistoryDir -Entries 1
        $t = Get-CostTrend -OutputDir $dir -Kind 'weekly' -TotalCost 150 -DateStr '2026-10-15' -NoPersist
        $t | Should Match '^\+50'
        Remove-Item -Recurse -Force $dir
    }
    It "computes the delta against the LAST of two prior entries (array regression)" {
        $dir = New-HistoryDir -Entries 2
        $t = Get-CostTrend -OutputDir $dir -Kind 'weekly' -TotalCost 250 -DateStr '2026-10-15' -NoPersist
        # Last entry is 200.0, so the delta must be +50 -- not a cast failure and
        # not a comparison against the first entry.
        $t | Should Match '^\+50'
        $t | Should Match '2026-10-02'
        Remove-Item -Recurse -Force $dir
    }
    It "computes the delta against the last of many prior entries" {
        $dir = New-HistoryDir -Entries 5
        $t = Get-CostTrend -OutputDir $dir -Kind 'weekly' -TotalCost 400 -DateStr '2026-10-15' -NoPersist
        $t | Should Match '^-100'
        $t | Should Match '2026-10-05'
        Remove-Item -Recurse -Force $dir
    }
    It "ignores entries of a different kind" {
        $dir = New-HistoryDir -Entries 2
        $t = Get-CostTrend -OutputDir $dir -Kind 'daily' -TotalCost 10 -DateStr '2026-10-15' -NoPersist
        $t | Should Match 'no prior daily run'
        Remove-Item -Recurse -Force $dir
    }
    It "degrades to n/a instead of throwing on a malformed entry" {
        $dir = New-HistoryDir -Entries 0
        Write-Utf8NoBom -Path (Join-Path $dir ".cost-history.json") `
            -Content '[{"date":"2026-10-01","kind":"weekly","totalCost":"not-a-number"}]'
        $t = Get-CostTrend -OutputDir $dir -Kind 'weekly' -TotalCost 10 -DateStr '2026-10-15' -NoPersist
        $t | Should Match 'n/a'
        Remove-Item -Recurse -Force $dir
    }
    It "appends to history and keeps all prior entries readable" {
        $dir = New-HistoryDir -Entries 2
        $null = Get-CostTrend -OutputDir $dir -Kind 'weekly' -TotalCost 300 -DateStr '2026-10-15'
        $written = @()
        ((Read-Utf8NoBom -Path (Join-Path $dir ".cost-history.json")) | ConvertFrom-Json) | ForEach-Object { $written += $_ }
        $written.Count | Should Be 3
        # The next run must see the appended entry, not choke on the longer array.
        $t = Get-CostTrend -OutputDir $dir -Kind 'weekly' -TotalCost 350 -DateStr '2026-10-16' -NoPersist
        $t | Should Match '^\+50'
        Remove-Item -Recurse -Force $dir
    }
}

Describe "Format-InsightsReport cost caveat" {
    # Key findings is what the session-start hint surfaces (CLAUDE.md section 9),
    # so the "concept pricing" caveat has to ride on the cost line itself. With it
    # only in the Notes section, a reader who never scrolled saw a four-figure
    # estimate presented as fact (observed: "Est. cost: USD 5401.6135 (+3462.1007)").
    $metrics = [ordered]@{
        WindowTurns = 10; UserPrompts = 5
        PerModel = @{ Opus = [ordered]@{ Family = 'Opus'; Turns = 10; Input = 1; Output = 1; CacheCreate = 0; CacheRead = 0; Cost = 12.5 } }
        TotalCost = 12.5; CostAvailable = $true
        ColdReadPct = 1.0; TotalReadTokens = 10
        StuckCandidates = @(); HaikuRatePct = 0.0; HaikuTurns = 0
        WasteScore = 0.0; HeavyTurns = 0; Patterns = @()
    }

    It "marks the estimate as concept pricing on the cost line" {
        $report = Format-InsightsReport -Metrics $metrics -Kind 'weekly' -DateStr '2026-10-17' -CostTrend '+1 vs prev weekly (2026-10-10)'
        $costLine = @($report -split "`r?`n" | Where-Object { $_ -match '^- Est\. cost:' })[0]
        $costLine | Should Not BeNullOrEmpty
        $costLine | Should Match 'concept pricing'
        $costLine | Should Match 'relative comparison only'
    }
    It "still reports the amount and the trend" {
        $report = Format-InsightsReport -Metrics $metrics -Kind 'weekly' -DateStr '2026-10-17' -CostTrend '+1 vs prev weekly (2026-10-10)'
        $report | Should Match 'USD 12\.5'
        $report | Should Match 'vs prev weekly'
    }
    It "says pricing is unavailable rather than claiming a caveat-free zero" {
        $noCost = [ordered]@{}
        foreach ($k in $metrics.Keys) { $noCost[$k] = $metrics[$k] }
        $noCost['CostAvailable'] = $false
        $report = Format-InsightsReport -Metrics $noCost -Kind 'weekly' -DateStr '2026-10-17'
        $report | Should Match 'Est\. cost: unavailable'
    }
}

Describe "README cost headline" {
    # The headline used to read "-80%" with an unmeasured "+ alpha" row, which
    # presented a pricing projection as a measured result.
    $readme = [System.IO.File]::ReadAllText((Join-Path (Split-Path -Parent $here) "README.md"))

    It "does not advertise a bare reduction percentage as the headline" {
        $readme | Should Not Match '\*\*-80%\*\*'
        $readme | Should Not Match '80% \+ '
    }
    It "carries no unmeasured '+ alpha' figure in a cost table" {
        $readme | Should Not Match '\$60 \+ '
    }
    # Assertions stay ASCII (ADR-0003 section C): PS 5.1 parses a BOM-less script
    # with the host ANSI codepage, so a Japanese literal here breaks the file.
    It "points at the concept pricing source next to the figures" {
        $readme | Should Match 'pricing\.psd1'
        $readme | Should Match 'billing'
    }
    It "names the measured quantity (workload) rather than the money" {
        $readme | Should Match 'workload'
    }
    It "keeps the orchestration-pace caveat next to the table" {
        $readme | Should Match 'orchestration'
        $readme | Should Match '7%'
    }
}
