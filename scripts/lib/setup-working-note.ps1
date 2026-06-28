<#
.SYNOPSIS
    Auto-configure settings.json on-exit hook and Windows Task Scheduler cron job
.DESCRIPTION
    Called by apply-claude-kit.ps1 after deploying working-note-checkpoint spec.
    - Merges on-exit hook into ~/.claude/settings.json (preserves existing settings)
    - Registers working-note-checkpoint cron job to Windows Task Scheduler
    - Idempotent: safe to run multiple times
.EXAMPLE
    pwsh ~/.claude-kit/scripts/lib/setup-working-note.ps1
#>

param(
    [switch] $DryRun = $false
)

$ErrorActionPreference = 'Continue'

# Resolve home directory
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$claudeDir = Join-Path -Path $homeDir -ChildPath ".claude"
$settingsJsonPath = Join-Path -Path $claudeDir -ChildPath "settings.json"

Write-Host "[working-note] Auto-setup starting..."

# Stage 1: Configure on-exit hook in settings.json
Write-Host "[1/2] Configuring on-exit hook in settings.json..."

$hookCommand = "powershell -NoProfile -Command '. \`"$homeDir\.claude\hooks\on-session-exit-checkpoint.ps1\`"'"

if (Test-Path -LiteralPath $settingsJsonPath) {
    # Read existing settings
    $settingsContent = Get-Content -LiteralPath $settingsJsonPath -Raw
    $settings = $settingsContent | ConvertFrom-Json

    # Check if on-exit hook already exists
    if ($null -ne $settings.hooks -and $null -ne $settings.hooks.'on-exit') {
        Write-Host "[skip] on-exit hook already configured"
    } else {
        # Add hooks object if missing
        if ($null -eq $settings.hooks) {
            $settings | Add-Member -MemberType NoteProperty -Name "hooks" -Value @{}
        }

        # Add on-exit hook
        $exitHook = @{
            shell = "powershell"
            command = $hookCommand
        }
        $settings.hooks | Add-Member -MemberType NoteProperty -Name "on-exit" -Value $exitHook -Force

        # Write back to file
        if ($DryRun) {
            Write-Host "[dry-run] Would update settings.json with on-exit hook"
        } else {
            $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settingsJsonPath -Encoding UTF8
            Write-Host "[apply] on-exit hook added to settings.json"
        }
    }
} else {
    Write-Host "[info] settings.json does not exist yet (Claude Code creates it on first run)"
    Write-Host "[note] Once Claude Code creates settings.json, run this script again"
}

# Stage 2: Register Windows Task Scheduler cron job
Write-Host "[2/2] Registering Windows Task Scheduler cron job..."

$taskName = "engineer-claude-kit-working-note-checkpoint"
$taskPath = "\engineer-claude-kit\"

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue

if ($null -ne $existingTask) {
    Write-Host "[skip] Task $taskName already registered"
} else {
    try {
        # Build action: run both scripts
        $claudeKitDir = Join-Path -Path $homeDir -ChildPath ".claude-kit"
        $checkpointScript = Join-Path -Path $claudeKitDir -ChildPath "scripts\lib\auto-checkpoint.ps1"
        $trackScript = Join-Path -Path $claudeKitDir -ChildPath "scripts\lib\track-workflow-state.ps1"

        $actionCommand = "powershell.exe"
        $actionArgs = "-NoProfile -Command `". \`"$checkpointScript\`"`"; . \`"$trackScript\`"`""

        $action = New-ScheduledTaskAction -Execute $actionCommand -Argument $actionArgs

        # Trigger: repeat every 10 minutes, indefinitely
        # Note: RepetitionDuration must be >= RepetitionInterval, use large value to approximate infinite
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)

        # Settings: allow task to run, stop after 5 minutes
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

        if ($DryRun) {
            Write-Host "[dry-run] Would register task $taskName"
        } else {
            Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath `
                -Action $action -Trigger $trigger -Settings $settings `
                -Description "Auto-checkpoint working-note every 10 minutes (engineer-claude-kit Phase B+)" `
                -Force | Out-Null
            Write-Host "[apply] Task $taskName registered to Windows Task Scheduler"
        }
    } catch {
        Write-Host "[error] Failed to register scheduled task: $_"
        Write-Host "[hint] You can register manually using Task Scheduler GUI:"
        Write-Host "       Task Name: $taskName"
        Write-Host "       Recurrence: Every 10 minutes"
        Write-Host "       Action: $actionCommand $actionArgs"
    }
}

Write-Host ""
Write-Host "[working-note] Auto-setup complete."
