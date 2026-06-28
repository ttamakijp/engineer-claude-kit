<#
.SYNOPSIS
    Auto-checkpoint working-note-YYYYMMDD.md with current session state
.DESCRIPTION
    Generate / append working-note-YYYY/MM/working-note-YYYYMMDD.md with current state.
    Safe for concurrent append via sequential lock.
.EXAMPLE
    pwsh ~/.claude-kit/scripts/lib/auto-checkpoint.ps1
#>

param(
    [switch] $DryRun = $false
)

# Resolve home directory (works on Windows + POSIX)
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$sessionNotesDir = Join-Path $homeDir ".claude" | Join-Path -ChildPath "session-notes"

# Get current date components
$now = Get-Date
$year = $now.Year
$month = $now.Month.ToString("D2")
$day = $now.Day.ToString("D2")

# Create YYYY/MM directory if not exists
$yearMonthDir = Join-Path $sessionNotesDir $year | Join-Path -ChildPath $month
if (-not (Test-Path $yearMonthDir)) {
    New-Item -ItemType Directory -Path $yearMonthDir -Force | Out-Null
}

# Construct working-note file path
$workingNoteFile = Join-Path $yearMonthDir "working-note-$year$month$day.md"

# Lock file for concurrent safety
$lockFile = "$workingNoteFile.lock"

# Helper: acquire lock with timeout
function Acquire-Lock {
    param([string] $LockPath, [int] $TimeoutSeconds = 30)
    $elapsed = 0
    while ((Test-Path $LockPath) -and $elapsed -lt $TimeoutSeconds) {
        Start-Sleep -Milliseconds 100
        $elapsed += 0.1
    }
    if (Test-Path $LockPath) {
        Write-Error "Lock timeout on $LockPath after ${TimeoutSeconds}s"
        return $false
    }
    New-Item -ItemType File -Path $LockPath -Force | Out-Null
    return $true
}

# Helper: release lock
function Release-Lock {
    param([string] $LockPath)
    if (Test-Path $LockPath) {
        Remove-Item $LockPath -Force
    }
}

# Acquire lock
if (-not (Acquire-Lock $lockFile)) {
    exit 1
}

try {
    # Initialize or read existing file
    $content = @()
    if (Test-Path $workingNoteFile) {
        $content = @(Get-Content $workingNoteFile -Raw)
    } else {
        # Create header for new file
        $content += "# Working Note $year-$month-$day`n"
        $content += "## Tasks`n"
        $content += "- [ ] (Add tasks here)`n`n"
        $content += "## Progress`n"
    }

    # Append timestamp checkpoint
    $timestamp = $now.ToString("HH:mm:ss")
    $checkpoint = "`n[Auto-checkpoint at $timestamp]`n"

    if ($DryRun) {
        Write-Host "DRY RUN: Would append to $workingNoteFile"
        Write-Host "Content:`n$checkpoint"
    } else {
        Add-Content -Path $workingNoteFile -Value $checkpoint -Encoding UTF8 -Force
        Write-Host "Auto-checkpoint appended: $workingNoteFile at $timestamp"
    }
} finally {
    Release-Lock $lockFile
}
