#!/usr/bin/env pwsh
# bootstrap.ps1
# Entry point for engineer-claude-kit setup.
# Auto-derives the distribution URL from git remote and invokes apply-claude-kit.ps1.
# ASCII only (no Japanese in code, comments, or strings).
# See ADR-0001 section I, ADR-0003 section A/D, ADR-0004 section D.

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$GitUrl,
    [switch]$SkipProjectPrompt,
    [switch]$NoEnvPersist,
    [switch]$AllowElevated,
    [switch]$NonInteractive,
    [switch]$NoSettingsWizard
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = "0.1.0"

# Fail-fast if running as Administrator (see ADR-0008). Escape hatch: -AllowElevated.
. (Join-Path (Join-Path $PSScriptRoot "lib") "privilege-check.ps1")
Assert-NonElevated -AllowElevated:$AllowElevated

# --- helpers ---

function Get-KitRoot {
    # bootstrap.ps1 is at <KitRoot>/scripts/bootstrap.ps1
    $resolved = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
    return $resolved
}

function Get-RemoteUrl {
    param([string]$RepoPath)

    # Try git remote get-url origin
    try {
        Push-Location $RepoPath
        $url = git remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $url) {
            return $null
        }
        return $url.Trim()
    } catch {
        return $null
    } finally {
        Pop-Location
    }
}

function Set-UserEnv {
    param(
        [string]$Name,
        [string]$Value,
        [switch]$IsDryRun
    )

    if ($IsDryRun) {
        Write-Host "[dry-run] would set user env $Name = $Value"
        return
    }

    # Persist to user environment (Windows registry HKCU\Environment)
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")

    # Also set in current session
    Set-Item -Path "Env:$Name" -Value $Value
    Write-Host "[env] set $Name = $Value (user-level, persisted)"
}

function Test-IsGitRepo {
    param([string]$Path)

    try {
        Push-Location $Path
        git rev-parse --is-inside-work-tree 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    } finally {
        Pop-Location
    }
}

# --- main ---

Write-Host "engineer-claude-kit bootstrap.ps1 (version $ScriptVersion)"
Write-Host ""

# Step 1: resolve kit root and validate structure
$kitRoot = Get-KitRoot
Write-Host "Kit root: $kitRoot"

$requiredPaths = @(
    (Join-Path (Join-Path $kitRoot "scripts") "apply-claude-kit.ps1"),
    (Join-Path (Join-Path $kitRoot "config") "models.yaml"),
    (Join-Path (Join-Path $kitRoot "templates") "CLAUDE.md")
)
foreach ($p in $requiredPaths) {
    if (-not (Test-Path $p)) {
        throw "Kit structure invalid: missing $p"
    }
}
Write-Host "[ok] kit structure validated"

# Step 2: resolve distribution URL
$resolvedUrl = $null
if ($GitUrl) {
    $resolvedUrl = $GitUrl
    Write-Host "[url] using -GitUrl parameter: $resolvedUrl"
} else {
    $remoteUrl = Get-RemoteUrl -RepoPath $kitRoot
    if ($remoteUrl) {
        $resolvedUrl = $remoteUrl
        Write-Host "[url] derived from git remote: $resolvedUrl"
    } else {
        # Fallback: existing env var
        if ($env:ENGINEER_CLAUDE_KIT_GIT_URL) {
            $resolvedUrl = $env:ENGINEER_CLAUDE_KIT_GIT_URL
            Write-Host "[url] using pre-set env ENGINEER_CLAUDE_KIT_GIT_URL: $resolvedUrl"
        } else {
            Write-Warning "Could not derive distribution URL. Kit may not be in a git repo."
            Write-Warning "Set -GitUrl <url> or `$env:ENGINEER_CLAUDE_KIT_GIT_URL manually if upgrade is needed later."
        }
    }
}

# Step 3: persist URL to user env (if available)
if ($resolvedUrl -and -not $NoEnvPersist) {
    Set-UserEnv -Name "ENGINEER_CLAUDE_KIT_GIT_URL" -Value $resolvedUrl -IsDryRun:$DryRun
}

# Step 4: invoke apply-claude-kit.ps1 -Global
$applyScript = Join-Path (Join-Path $kitRoot "scripts") "apply-claude-kit.ps1"
Write-Host ""
Write-Host "[invoke] apply-claude-kit.ps1 -Global"

$applyArgs = @("-NoProfile", "-File", $applyScript, "-Global")
if ($DryRun) { $applyArgs += "-DryRun" }
if ($AllowElevated) { $applyArgs += "-AllowElevated" }
# Bootstrap owns the settings wizard and runs it once at the very end (after the
# optional project prompt), so suppress it inside the apply -Global subprocess to
# avoid prompting twice. Direct `apply-claude-kit.ps1 -Global` still runs it.
$applyArgs += "-NoSettingsWizard"
if ($NonInteractive) { $applyArgs += "-NonInteractive" }

& powershell @applyArgs
if ($LASTEXITCODE -ne 0) {
    throw "apply-claude-kit.ps1 -Global failed with exit code $LASTEXITCODE"
}

# Step 5: optional project-level apply prompt
$cwd = (Get-Location).Path
$shouldPromptProject = (-not $SkipProjectPrompt) `
    -and ($cwd -ne $kitRoot) `
    -and (-not $cwd.StartsWith($kitRoot, [System.StringComparison]::OrdinalIgnoreCase)) `
    -and (Test-IsGitRepo -Path $cwd)

if ($shouldPromptProject) {
    Write-Host ""
    Write-Host "Current directory is a git repository: $cwd"
    Write-Host "Apply engineer-claude-kit to this project? (y/N): " -NoNewline

    $answer = $null
    if ($DryRun) {
        Write-Host "n (dry-run auto-decline)"
        $answer = "n"
    } else {
        $answer = Read-Host
    }

    if ($answer -match '^[yY]') {
        Write-Host "[invoke] apply-claude-kit.ps1 -Project `"$cwd`""
        $projectArgs = @("-NoProfile", "-File", $applyScript, "-Project", $cwd)
        if ($AllowElevated) { $projectArgs += "-AllowElevated" }
        & powershell @projectArgs
        if ($LASTEXITCODE -ne 0) {
            throw "apply-claude-kit.ps1 -Project failed with exit code $LASTEXITCODE"
        }
    } else {
        Write-Host "[skip] project-level apply declined"
    }
} elseif ($SkipProjectPrompt) {
    Write-Host "[skip] -SkipProjectPrompt was specified"
} else {
    Write-Host "[skip] cwd is not a separate git repository, skipping project-level prompt"
}

Write-Host ""
Write-Host "Bootstrap complete."
if ($DryRun) { Write-Host "Note: -DryRun was specified, no files were modified and no env was persisted." }

# Step 6: post-bootstrap hint for optional tool installation
Write-Host ""
Write-Host "[hint] To install required tools (gitleaks, gh, node, etc.) via winget, run:"
Write-Host "       powershell -NoProfile -File `"$kitRoot\scripts\install-deps.ps1`""
Write-Host "       (or use ``pwsh`` instead of ``powershell`` if you prefer PowerShell 7+)"
Write-Host "       (add -DryRun to preview without installing anything)"

# Step 7: optional interactive settings wizard (ADR-0010).
# Opt-in deep merge of missing settings.json keys (statusLine /
# ANTHROPIC_SMALL_FAST_MODEL). Skipped on -DryRun (no modifications) and on
# -NoSettingsWizard. The wizard itself skips in non-interactive contexts
# (-NonInteractive / $env:CI / no UserInteractive console), so the default
# non-interactive behavior is unchanged.
if (-not $DryRun -and -not $NoSettingsWizard) {
    . (Join-Path $PSScriptRoot "setup-wizard.ps1")
    Invoke-SettingsSetupWizard -NonInteractive:$NonInteractive
}
