<#
.SYNOPSIS
    Session exit hook: force-checkpoint working-note on Claude session exit
.DESCRIPTION
    This hook is triggered when Claude Code session ends (on atexit).
    It immediately forces a checkpoint to capture the final state before exit.
.NOTES
    This is a hook template. It is invoked via settings.json hook configuration.
#>

param(
    [string] $SessionId = $env:CLAUDE_SESSION_ID,
    [string] $ExitReason = "normal"
)

# Resolve home directory
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$sessionNotesDir = Join-Path $homeDir ".claude" "session-notes"

# Get current date components
$now = Get-Date
$year = $now.Year
$month = $now.Month.ToString("D2")
$day = $now.Day.ToString("D2")

# Create YYYY/MM directory if not exists
$yearMonthDir = Join-Path $sessionNotesDir $year $month
if (-not (Test-Path $yearMonthDir)) {
    New-Item -ItemType Directory -Path $yearMonthDir -Force | Out-Null
}

# Construct working-note file path
$workingNoteFile = Join-Path $yearMonthDir "working-note-$year$month$day.md"

# Lock file for concurrent safety
$lockFile = "$workingNoteFile.lock"

# Helper: acquire lock with timeout
function Acquire-Lock {
    param([string] $LockPath, [int] $TimeoutSeconds = 5)
    $elapsed = 0
    while ((Test-Path $LockPath) -and $elapsed -lt $TimeoutSeconds) {
        Start-Sleep -Milliseconds 100
        $elapsed += 0.1
    }
    if (Test-Path $LockPath) {
        # Timeout: force remove stale lock
        Remove-Item $LockPath -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType File -Path $lockFile -Force | Out-Null
    return $true
}

# Helper: release lock
function Release-Lock {
    param([string] $LockPath)
    if (Test-Path $LockPath) {
        Remove-Item $LockPath -Force
    }
}

# Acquire lock (short timeout since this is final checkpoint)
Acquire-Lock $lockFile | Out-Null

try {
    # Initialize or read existing file
    if (-not (Test-Path $workingNoteFile)) {
        $content = "# Working Note $year-$month-$day`n`n## Tasks`n`n## Progress`n"
        Set-Content -Path $workingNoteFile -Value $content -Encoding UTF8
    }

    # Append exit checkpoint
    $timestamp = $now.ToString("yyyy-MM-dd HH:mm:ss")
    $exitMarker = "`n**Session exit at $timestamp ($ExitReason)**`n"

    Add-Content -Path $workingNoteFile -Value $exitMarker -Encoding UTF8 -Force
} finally {
    Release-Lock $lockFile
}
