# compare-snapshots.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Covers scripts/compare-snapshots.ps1 (ADR-0015 / ADR-0016). The script exists
# to make the confounds visible: every large swing in the snapshot series so far
# turned out to be a workload shift rather than a change in behaviour, so a
# comparison that hands back a confident number without flagging that is worse
# than no comparison.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$repoRoot = Split-Path -Parent $here
$ScriptPath = Join-Path (Join-Path $repoRoot "scripts") "compare-snapshots.ps1"
. (Join-Path (Join-Path (Join-Path $repoRoot "scripts") "lib") "encoding-helper.ps1")

function New-SnapshotFixture {
    # Build an insights dir holding two baselines and their weekly reports.
    param(
        [double]$FromRate, [int]$FromElig, [double]$FromCost, [int]$FromTurns,
        [double]$ToRate,   [int]$ToElig,   [double]$ToCost,   [int]$ToTurns
    )
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("cs-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $mk = {
        param($date, $rate, $elig, $cost, $turns)
        $b = [ordered]@{
            RecordedOn = $date; WindowDays = 7
            PlanFirstRate = $rate; PlanFirstStrictRate = $rate; PlanFirstEligible = $elig
            DelegationRate = 0; DelegationEligible = $elig
            CommitRate = 100; CommitExtracted = $elig
        }
        Write-Utf8NoBom -Path (Join-Path $dir "rule-metrics-baseline-$date.json") -Content ($b | ConvertTo-Json -Depth 3)
        $report = "# Usage Insights ($date, weekly)`n`nWindow: last 7 day(s). Assistant turns: $turns. User prompts: 1.`n`n- Est. cost: USD $cost (n/a)`n"
        Write-Utf8NoBom -Path (Join-Path $dir "$date-weekly.md") -Content $report
    }
    & $mk '2026-01-01' $FromRate $FromElig $FromCost $FromTurns
    & $mk '2026-01-08' $ToRate   $ToElig   $ToCost   $ToTurns
    return $dir
}

function Invoke-Compare {
    param([string]$Dir, [string[]]$ExtraArgs = @())
    $args = @('-NoProfile', '-File', $ScriptPath, '-InsightsDir', $Dir) + $ExtraArgs
    $out = & powershell @args 2>&1
    return (@($out) -join "`n")
}

Describe "compare-snapshots.ps1" {
    It "exists and parses" {
        Test-Path $ScriptPath | Should Be $true
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$errors)
        @($errors).Count | Should Be 0
    }
    It "reports both snapshot dates" {
        $dir = New-SnapshotFixture -FromRate 50 -FromElig 100 -FromCost 100 -FromTurns 1000 `
            -ToRate 50 -ToElig 100 -ToCost 100 -ToTurns 1000
        $out = Invoke-Compare -Dir $dir
        $out | Should Match '2026-01-01'
        $out | Should Match '2026-01-08'
        Remove-Item -Recurse -Force $dir
    }
    # The noise floor measured in ADR-0015: a window sliding one day moved
    # plan-first 2.2 pt on its own, so a smaller delta is not a finding.
    It "marks a sub-noise delta as within noise" {
        $dir = New-SnapshotFixture -FromRate 50 -FromElig 100 -FromCost 100 -FromTurns 1000 `
            -ToRate 51 -ToElig 100 -ToCost 100 -ToTurns 1000
        $out = Invoke-Compare -Dir $dir
        $out | Should Match 'within noise'
        Remove-Item -Recurse -Force $dir
    }
    It "does not mark a delta above the noise floor" {
        $dir = New-SnapshotFixture -FromRate 50 -FromElig 100 -FromCost 100 -FromTurns 1000 `
            -ToRate 70 -ToElig 100 -ToCost 100 -ToTurns 1000
        $out = Invoke-Compare -Dir $dir
        # Scope the check to the plan-first row. The fixture holds delegation at
        # 0 -> 0, which is legitimately within noise and would match otherwise.
        $planLine = @($out -split "`r?`n" | Where-Object { $_ -match '^\s+plan-first\s' })[0]
        $planLine | Should Not BeNullOrEmpty
        $planLine | Should Match '\+20 pt'
        $planLine | Should Not Match 'within noise'
        Remove-Item -Recurse -Force $dir
    }
    # Every large swing in the real series was a workload shift. The denominator
    # warning is the whole point of the script.
    It "warns when the eligible count moved by more than half" {
        $dir = New-SnapshotFixture -FromRate 50 -FromElig 100 -FromCost 100 -FromTurns 1000 `
            -ToRate 20 -ToElig 20 -ToCost 100 -ToTurns 1000
        $out = Invoke-Compare -Dir $dir
        $out | Should Match 'compares different workloads'
        Remove-Item -Recurse -Force $dir
    }
    It "reports per-turn cost alongside the total" {
        $dir = New-SnapshotFixture -FromRate 50 -FromElig 100 -FromCost 1000 -FromTurns 1000 `
            -ToRate 50 -ToElig 100 -ToCost 500 -ToTurns 1000
        $out = Invoke-Compare -Dir $dir
        $out | Should Match 'per turn'
        $out | Should Match 'total'
        Remove-Item -Recurse -Force $dir
    }
    It "passes the verdict when the saving clears the threshold on comparable windows" {
        $dir = New-SnapshotFixture -FromRate 50 -FromElig 100 -FromCost 1000 -FromTurns 1000 `
            -ToRate 50 -ToElig 100 -ToCost 500 -ToTurns 1000
        $out = Invoke-Compare -Dir $dir -ExtraArgs @('-SuccessUsdPerMonth', '20')
        $out | Should Match 'PASS'
        Remove-Item -Recurse -Force $dir
    }
    It "says NOT YET when the saving is below the threshold" {
        $dir = New-SnapshotFixture -FromRate 50 -FromElig 100 -FromCost 1000 -FromTurns 1000 `
            -ToRate 50 -ToElig 100 -ToCost 999 -ToTurns 1000
        $out = Invoke-Compare -Dir $dir -ExtraArgs @('-SuccessUsdPerMonth', '20')
        $out | Should Match 'NOT YET'
        Remove-Item -Recurse -Force $dir
    }
    # Without this the 10-16 -> 10-27 pair projects USD 1,736/month purely from a
    # workload shift, and the script would call that a PASS.
    It "refuses a verdict when the turn count moved by more than 2x" {
        $dir = New-SnapshotFixture -FromRate 50 -FromElig 100 -FromCost 5000 -FromTurns 4000 `
            -ToRate 50 -ToElig 100 -ToCost 800 -ToTurns 900
        $out = Invoke-Compare -Dir $dir -ExtraArgs @('-SuccessUsdPerMonth', '20')
        $out | Should Match 'UNRELIABLE'
        $out | Should Not Match '=> PASS'
        Remove-Item -Recurse -Force $dir
    }
    It "exits with guidance when there are fewer than two archives" {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("cs-empty-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $out = Invoke-Compare -Dir $dir
        $out | Should Match 'Need at least two baseline archives'
        Remove-Item -Recurse -Force $dir
    }
    It "reminds the reader to check the project mix" {
        $dir = New-SnapshotFixture -FromRate 50 -FromElig 100 -FromCost 100 -FromTurns 1000 `
            -ToRate 50 -ToElig 100 -ToCost 100 -ToTurns 1000
        $out = Invoke-Compare -Dir $dir
        $out | Should Match 'Activity by project'
        Remove-Item -Recurse -Force $dir
    }
}
