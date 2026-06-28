<#
.SYNOPSIS
    Track active workflow state and update working-note metadata
.DESCRIPTION
    Monitors ~/.claude/workflows/ and ~/transcript directories for running/completed workflow runs.
    Updates working-note-YYYYMMDD.md with active workflow metadata for resume capability.
    Designed to be called periodically (cron job) and at session start/exit.
.EXAMPLE
    pwsh ~/.claude-kit/scripts/lib/track-workflow-state.ps1
#>

param(
    [switch] $DryRun = $false
)

# Resolve home directory
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$sessionNotesDir = Join-Path $homeDir ".claude" | Join-Path -ChildPath "session-notes"
$workflowsDir = Join-Path $homeDir ".claude" | Join-Path -ChildPath "workflows"
$transcriptDir = Join-Path $homeDir ".claude" | Join-Path -ChildPath "transcript"

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

$workingNoteFile = Join-Path $yearMonthDir "working-note-$year$month$day.md"
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
        Remove-Item $LockPath -Force -ErrorAction SilentlyContinue
    }
}

# Find active workflows by scanning transcripts
# Each transcript should have a corresponding workflow journal (agent-<id>.jsonl)
function Get-ActiveWorkflows {
    $activeWorkflows = @()

    if (-not (Test-Path $transcriptDir)) {
        return $activeWorkflows
    }

    # Look for agent-*.jsonl files (workflow state journals)
    Get-ChildItem -LiteralPath $transcriptDir -Filter "agent-*.jsonl" -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $journalPath = $_.FullName
            $lastLine = Get-Content $journalPath -Tail 1

            # Parse JSON to extract workflow metadata
            try {
                $entry = $lastLine | ConvertFrom-Json
                if ($entry.type -eq "workflow_executed") {
                    $activeWorkflows += @{
                        runId = $entry.runId
                        name = $entry.name
                        phase = $entry.current_phase
                        totalPhases = $entry.total_phases
                        lastUpdate = $entry.timestamp
                        scriptPath = $entry.scriptPath
                    }
                }
            } catch {
                # Skip unparseable entries
            }
        }

    return $activeWorkflows
}

# Format workflow entry for working-note
function Format-WorkflowEntry {
    param([hashtable] $Workflow)

    $phaseStr = if ($Workflow.phase -and $Workflow.totalPhases) {
        "$($Workflow.phase)/$($Workflow.totalPhases)"
    } else {
        "unknown"
    }

    $lastUpdateStr = if ($Workflow.lastUpdate) {
        $Workflow.lastUpdate
    } else {
        (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }

    return "  - $($Workflow.name): runId=$($Workflow.runId), phase=$phaseStr, last=$lastUpdateStr"
}

# Acquire lock
if (-not (Acquire-Lock $lockFile)) {
    exit 1
}

try {
    # Initialize or read existing file
    if (-not (Test-Path $workingNoteFile)) {
        $content = "# Working Note $year-$month-$day`n`n## Tasks`n- [ ] (Add tasks here)`n`n## Progress`n`n## Active Workflows`n"
        if (-not $DryRun) {
            Set-Content -Path $workingNoteFile -Value $content -Encoding UTF8
        }
    }

    # Get active workflows
    $workflows = Get-ActiveWorkflows

    if ($workflows.Count -gt 0) {
        # Build workflow section
        $timestamp = $now.ToString("HH:mm:ss")
        $workflowSection = "`n### Active Workflows (checkpoint at $timestamp)`n"
        foreach ($wf in $workflows) {
            $workflowSection += (Format-WorkflowEntry $wf) + "`n"
        }
        $workflowSection += "`nTo resume: Workflow({scriptPath: `"$($workflows[0].scriptPath)`", resumeFromRunId: `"$($workflows[0].runId)`"})`n"

        if ($DryRun) {
            Write-Host "DRY RUN: Would append to $workingNoteFile"
            Write-Host "Content:`n$workflowSection"
        } else {
            Add-Content -Path $workingNoteFile -Value $workflowSection -Encoding UTF8 -Force
            Write-Host "Workflow state appended: $workingNoteFile at $timestamp"
        }
    }
} finally {
    Release-Lock $lockFile
}
