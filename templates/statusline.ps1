#requires -Version 5.1
# statusline.ps1 - Claude Code status line (ADR-0012 color-coded context usage,
#                  ADR-0015 end-of-day indicator)
#
# Renders: [<model>] <pct>% context  <dir> git:<branch>  EOD <HH:MM>
# The percentage is color-coded: green < 75%, yellow 75-90%, red >= 90%.
# The EOD segment appears only inside the warning window before the configured
# work end time (yellow), or after it has passed (red). Otherwise it is absent.
#
# Why a -File script instead of an inline -Command (the original ship form):
# On Windows, Claude Code runs the statusLine command through Git Bash whenever
# Git Bash is installed. An inline 'powershell -Command "...$_..."' has its $
# tokens ($input, $_, $p, ...) expanded by bash BEFORE PowerShell sees them,
# corrupting the command so it prints nothing (silent blank statusline). A -File
# path carries no $ tokens for bash to touch, so the logic stays intact under
# Git Bash, cmd, or PowerShell alike. See ADR-0012 (2026-06-09 amendment).
#
# Why the EOD logic lives here rather than in a rule:
# work-end-reminder.md used to ask Claude to read a marker file, compare dates
# and branch three ways on every single turn. Nothing verified that it happened,
# and a miss was indistinguishable from "not yet time" -- a silent fallback with
# no way to detect it. The comparison is deterministic, so a script owns it and
# the rule is reduced to "if you see EOD, ask before starting something big".
# See ADR-0015 section C.
#
# ASCII only (ADR-0003 section C). An hourglass or alarm-clock emoji would need
# a non-ASCII source byte, and its terminal cell width is inconsistent enough to
# misalign the rest of the line, so the indicator is the literal text "EOD".
# PS 5.1 compatible (no `e, no PS 6+ syntax).

$ErrorActionPreference = 'SilentlyContinue'

function Get-WorkEndStatus {
    # Decide whether to show the EOD indicator, and in which color.
    #
    # Precedence (same as the rule it replaces):
    #   1. ~/.claude/.work-end-today, when its date is today
    #        "HH:MM" -> that time    "off" / "skip" -> show nothing
    #        "yaml"  -> fall through to the schedule below
    #   2. schedule.<weekday> in ~/.claude/work-schedule.yaml ("null" -> nothing)
    #   3. neither -> show nothing (never guess an end time)
    #
    # Returns a hashtable: Show (bool), Time (HH:MM), Color (ANSI code).
    # Parameters are injectable so the drift tests can drive every branch.
    param(
        [datetime]$Now = (Get-Date),
        [string]$SchedulePath,
        [string]$MarkerPath
    )

    $none = @{ Show = $false; Time = ''; Color = '' }

    # $home would shadow the well-known automatic variable, so name it explicitly.
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
    if (-not $SchedulePath) { $SchedulePath = Join-Path (Join-Path $userHome ".claude") "work-schedule.yaml" }
    if (-not $MarkerPath)   { $MarkerPath   = Join-Path (Join-Path $userHome ".claude") ".work-end-today" }

    $endText = $null
    $useSchedule = $true

    # --- 1. today's marker ---
    if (Test-Path -LiteralPath $MarkerPath) {
        # ReadAllText, not ReadLines: ReadLines returns a lazy enumerable, and
        # breaking out of it after the first line leaves the StreamReader open, so
        # the marker stays locked for the rest of the process and anything that
        # tries to rewrite it fails. The marker is a single short line.
        $first = ''
        try {
            foreach ($line in ([System.IO.File]::ReadAllText($MarkerPath) -split "`r?`n")) {
                if ($line.Trim()) { $first = $line.Trim(); break }
            }
        } catch { $first = '' }
        if ($first -match '^(\d{4}-\d{2}-\d{2})\s+(\S+)$') {
            $markerDate = $Matches[1]
            $markerValue = $Matches[2]
            if ($markerDate -eq $Now.ToString('yyyy-MM-dd')) {
                if ($markerValue -eq 'off' -or $markerValue -eq 'skip') { return $none }
                if ($markerValue -match '^\d{1,2}:\d{2}$') {
                    $endText = $markerValue
                    $useSchedule = $false
                }
                # "yaml" (or anything unrecognized) leaves $useSchedule true.
            }
        }
    }

    # --- 2. weekday schedule ---
    $windowMinutes = 30
    if (Test-Path -LiteralPath $SchedulePath) {
        $yaml = ''
        try { $yaml = [System.IO.File]::ReadAllText($SchedulePath) } catch { $yaml = '' }
        if ($yaml -match '(?m)^\s*warning_window_minutes\s*:\s*(\d+)') {
            $windowMinutes = [int]$Matches[1]
        }
        if ($useSchedule) {
            $day = $Now.ToString('ddd', [System.Globalization.CultureInfo]::InvariantCulture).ToLowerInvariant()
            if ($yaml -match ('(?m)^\s+' + $day + '\s*:\s*(.+)$')) {
                $raw = $Matches[1].Trim().Trim('"').Trim("'")
                if ($raw -match '^\d{1,2}:\d{2}$') { $endText = $raw }
            }
        }
    }

    if (-not $endText) { return $none }

    # --- 3. compare ---
    $parts = $endText.Split(':')
    $endToday = $Now.Date.AddHours([int]$parts[0]).AddMinutes([int]$parts[1])
    $minutesLeft = ($endToday - $Now).TotalMinutes

    if ($minutesLeft -lt 0) { return @{ Show = $true; Time = $endText; Color = '31' } }
    if ($minutesLeft -le $windowMinutes) { return @{ Show = $true; Time = $endText; Color = '33' } }
    return $none
}

$raw = $input | Out-String
if ([string]::IsNullOrWhiteSpace($raw)) { return }
$data = $raw | ConvertFrom-Json
if ($null -eq $data) { return }

# context_window.used_percentage can be null right after session start / compact.
$pct = $data.context_window.used_percentage
if ($null -eq $pct) { $pct = 0 }
$p = [Math]::Floor([double]$pct)

# Color thresholds (ADR-0012). Kept as a single returnable if-expression so the
# drift test can extract and evaluate it directly.
$color = if ($p -ge 90) { '31' } elseif ($p -ge 75) { '33' } else { '32' }

$dir = $data.workspace.current_dir
$leaf = if ($dir) { Split-Path -Leaf $dir } else { '' }

$branch = ''
if ($dir -and (Test-Path $dir)) {
    Push-Location $dir
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    Pop-Location
}
$git = if ($branch) { ' git:' + $branch } else { '' }

$model = $data.model.display_name
$esc = [char]27

# End-of-day indicator (ADR-0015). Absent outside the warning window, so the
# normal line is unchanged for most of the day.
$eod = ''
$eodStatus = Get-WorkEndStatus
if ($eodStatus.Show) {
    $eod = '  ' + $esc + '[' + $eodStatus.Color + 'm' + 'EOD ' + $eodStatus.Time + $esc + '[0m'
}

Write-Host ($esc + '[' + $color + 'm[' + $model + '] ' + $p + '% context' + $esc + '[0m ' + $leaf + $git + $eod)
