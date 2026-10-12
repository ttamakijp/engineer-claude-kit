# statusline-eod.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Covers the end-of-day indicator in templates/statusline.ps1 (ADR-0015 section
# C), which took over the marker-file / date-compare / three-way branch that
# work-end-reminder.md used to ask Claude to perform every turn.
#
# statusline.ps1 is dot-sourced: its body reads $input, which is empty here, so
# it returns before rendering anything and only the functions land in scope.
# Get-WorkEndStatus takes -Now / -SchedulePath / -MarkerPath so every branch is
# driven from fixtures rather than from the clock or the real ~/.claude.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$repoRoot = Split-Path -Parent $here
. (Join-Path (Join-Path $repoRoot "templates") "statusline.ps1")

$script:Fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("eod-test-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $script:Fixture | Out-Null
$script:Schedule = Join-Path $script:Fixture "work-schedule.yaml"
$script:Marker = Join-Path $script:Fixture ".work-end-today"
@(
    'schedule:',
    '  mon: "17:30"',
    '  tue: "17:30"',
    '  wed: "17:30"',
    '  thu: "17:30"',
    '  fri: "17:00"',
    '  sat: null',
    '  sun: null',
    'warning_window_minutes: 30'
) | Set-Content -LiteralPath $script:Schedule

# 2026-10-07 is a Wednesday (schedule 17:30); 2026-10-10 is a Saturday (null).
function Get-Eod {
    param([string]$When, [string]$MarkerLine)
    if ($null -ne $MarkerLine) {
        if ($MarkerLine -eq '') {
            if (Test-Path -LiteralPath $script:Marker) { Remove-Item -Force $script:Marker }
        } else {
            $MarkerLine | Set-Content -LiteralPath $script:Marker
        }
    }
    $now = [datetime]::ParseExact($When, 'yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    return Get-WorkEndStatus -Now $now -SchedulePath $script:Schedule -MarkerPath $script:Marker
}

Describe "statusline EOD indicator (weekday schedule)" {
    It "stays hidden well before the end time" {
        $r = Get-Eod -When '2026-10-07 16:00' -MarkerLine ''
        $r.Show | Should Be $false
    }
    It "turns yellow inside the warning window" {
        $r = Get-Eod -When '2026-10-07 17:05' -MarkerLine ''
        $r.Show | Should Be $true
        $r.Time | Should Be '17:30'
        $r.Color | Should Be '33'
    }
    It "turns yellow exactly at the window boundary" {
        $r = Get-Eod -When '2026-10-07 17:00' -MarkerLine ''
        $r.Show | Should Be $true
        $r.Color | Should Be '33'
    }
    It "stays hidden one minute before the window opens" {
        $r = Get-Eod -When '2026-10-07 16:59' -MarkerLine ''
        $r.Show | Should Be $false
    }
    It "turns red once the end time has passed" {
        $r = Get-Eod -When '2026-10-07 17:35' -MarkerLine ''
        $r.Show | Should Be $true
        $r.Color | Should Be '31'
    }
    It "stays hidden on a day whose schedule is null" {
        $r = Get-Eod -When '2026-10-10 17:35' -MarkerLine ''
        $r.Show | Should Be $false
    }
}

Describe "statusline EOD indicator (today's marker)" {
    It "prefers the marker time over the weekday schedule" {
        $r = Get-Eod -When '2026-10-07 14:40' -MarkerLine '2026-10-07 15:00'
        $r.Show | Should Be $true
        $r.Time | Should Be '15:00'
        $r.Color | Should Be '33'
    }
    It "shows nothing when the marker says off" {
        $r = Get-Eod -When '2026-10-07 17:35' -MarkerLine '2026-10-07 off'
        $r.Show | Should Be $false
    }
    It "shows nothing when the marker says skip" {
        $r = Get-Eod -When '2026-10-07 17:35' -MarkerLine '2026-10-07 skip'
        $r.Show | Should Be $false
    }
    It "falls back to the schedule when the marker says yaml" {
        $r = Get-Eod -When '2026-10-07 17:05' -MarkerLine '2026-10-07 yaml'
        $r.Show | Should Be $true
        $r.Time | Should Be '17:30'
    }
    It "ignores a marker from an earlier day" {
        $r = Get-Eod -When '2026-10-07 17:05' -MarkerLine '2026-10-01 09:00'
        $r.Show | Should Be $true
        $r.Time | Should Be '17:30'
    }
    It "ignores a malformed marker line" {
        $r = Get-Eod -When '2026-10-07 17:05' -MarkerLine 'not a marker at all'
        $r.Show | Should Be $true
        $r.Time | Should Be '17:30'
    }
    # Regression: the first implementation read the marker with the lazy
    # [System.IO.File]::ReadLines and broke out after the first line, leaving the
    # StreamReader open. The marker stayed locked for the rest of the process, so
    # anything that rewrote it afterwards failed silently.
    It "does not keep the marker file open" {
        $null = Get-Eod -When '2026-10-07 17:05' -MarkerLine '2026-10-07 17:30'
        # A lingering handle makes this throw.
        '2026-10-07 off' | Set-Content -LiteralPath $script:Marker
        (Get-Content -LiteralPath $script:Marker -Raw) | Should Match 'off'
    }
}

Describe "statusline EOD indicator (no configuration)" {
    It "shows nothing when neither marker nor schedule exists" {
        $empty = Join-Path $script:Fixture "absent"
        $r = Get-WorkEndStatus -Now ([datetime]'2026-10-07 17:05') `
            -SchedulePath (Join-Path $empty "work-schedule.yaml") `
            -MarkerPath (Join-Path $empty ".work-end-today")
        $r.Show | Should Be $false
    }
    It "honors a custom warning window" {
        $wide = Join-Path $script:Fixture "wide.yaml"
        @('schedule:', '  wed: "17:30"', 'warning_window_minutes: 120') | Set-Content -LiteralPath $wide
        $r = Get-WorkEndStatus -Now ([datetime]'2026-10-07 16:00') `
            -SchedulePath $wide -MarkerPath (Join-Path $script:Fixture "absent-marker")
        $r.Show | Should Be $true
        $r.Color | Should Be '33'
    }
}

if (Test-Path $script:Fixture) { Remove-Item -Recurse -Force $script:Fixture -ErrorAction SilentlyContinue }
