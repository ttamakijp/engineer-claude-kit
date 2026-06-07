#requires -Version 5.1
# install-deps.ps1
# Installs the tools engineer-claude-kit relies on (gitleaks / gh / pwsh / node)
# via winget in one shot. Already-installed tools are skipped (idempotent).
# ASCII only (no Japanese in code, comments, or strings).
# See ADR-0001.
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$msg)
    if (-not $Quiet) { Write-Host $msg }
}

function Install-PSScriptAnalyzerNonInteractive {
    # Install PSScriptAnalyzer so it succeeds in a non-interactive shell.
    # PSScriptAnalyzer is a PowerShell module, not a winget package, so it
    # cannot be installed through the winget loop above. Three things break the
    # default Install-Module flow when unattended:
    #   1. PSGallery is untrusted -> Install-Module prompts for confirmation.
    #   2. TLS 1.2 not enabled -> NuGet API connection fails on older defaults.
    #   3. NuGet provider missing -> Install-Module prompts to install it.
    [CmdletBinding()]
    param()

    # Force TLS 1.2 for the NuGet / PSGallery endpoints.
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Warning "Failed to set TLS 1.2 (continuing): $_"
    }

    # Ensure the NuGet package provider is present (else Install-Module prompts).
    $nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
        Where-Object { $_.Version -ge [version]'2.8.5.201' }
    if (-not $nuget) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 `
            -Scope CurrentUser -Force -Confirm:$false | Out-Null
    }

    # Temporarily mark PSGallery as Trusted to avoid the confirmation prompt.
    $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    $originalPolicy = $null
    if ($gallery -and $gallery.InstallationPolicy -ne 'Trusted') {
        $originalPolicy = $gallery.InstallationPolicy
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    try {
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser `
            -Force -SkipPublisherCheck -Confirm:$false -ErrorAction Stop
    } finally {
        # Restore the original PSGallery installation policy.
        if ($originalPolicy) {
            Set-PSRepository -Name PSGallery -InstallationPolicy $originalPolicy
        }
    }
}

function Test-WingetAvailable {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

if (-not (Test-WingetAvailable)) {
    Write-Warning "winget not found. Please install App Installer from Microsoft Store."
    Write-Warning "Or install required tools manually:"
    Write-Warning "  gitleaks: https://github.com/gitleaks/gitleaks/releases"
    Write-Warning "  gh:       https://cli.github.com/"
    Write-Warning "  pwsh:     https://github.com/PowerShell/PowerShell/releases"
    Write-Warning "  node:     https://nodejs.org/"
    exit 1
}

$tools = @(
    @{ name = 'gitleaks'; wingetId = 'gitleaks.gitleaks';    required = $true;  hint = 'Required for leak detection hooks (Group C)' },
    @{ name = 'gh';       wingetId = 'GitHub.cli';           required = $true;  hint = 'Required for PR operations from CLI' },
    @{ name = 'pwsh';     wingetId = 'Microsoft.PowerShell'; required = $false; hint = 'Recommended for stable script execution (PS 7+)' },
    @{ name = 'node';     wingetId = 'OpenJS.NodeJS';        required = $false; hint = 'Required for Claude Code CLI (install separately via npm)' }
)

$installed = 0
$skipped = 0
$failed = 0

foreach ($t in $tools) {
    $cmd = Get-Command $t.name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Info "[skip] $($t.name) already installed: $($cmd.Source)"
        $skipped++
        continue
    }

    Write-Info ""
    Write-Info "[$($t.name)] $($t.hint)"

    if ($DryRun) {
        Write-Info "[dry-run] would install: winget install --id $($t.wingetId)"
        continue
    }

    Write-Info "Installing $($t.name) via winget (id: $($t.wingetId)) ..."
    winget install --id $t.wingetId --silent --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-Info "  [ok] $($t.name) installed"
        $installed++
    } else {
        if ($t.required) {
            Write-Warning "  [fail] required tool $($t.name) failed to install (exit code: $LASTEXITCODE)"
            $failed++
        } else {
            Write-Info "  [skip] optional tool $($t.name) failed to install (continuing)"
        }
    }
}

# PSScriptAnalyzer (separate path: PowerShell module via Install-Module, not winget)
$psa = Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -First 1
if ($psa) {
    Write-Info "[skip] PSScriptAnalyzer already installed: v$($psa.Version)"
    $skipped++
} else {
    Write-Info ""
    Write-Info "[PSScriptAnalyzer] Required for lint (scripts/lint.ps1)"
    if ($DryRun) {
        Write-Info "[dry-run] would install: Install-Module PSScriptAnalyzer -Scope CurrentUser"
    } else {
        Write-Info "Installing PSScriptAnalyzer via Install-Module (non-interactive) ..."
        try {
            Install-PSScriptAnalyzerNonInteractive
            Write-Info "  [ok] PSScriptAnalyzer installed"
            $installed++
        } catch {
            Write-Warning "  [fail] PSScriptAnalyzer failed to install: $_"
            $failed++
        }
    }
}

Write-Info ""
Write-Info "Summary: installed=$installed skipped=$skipped failed=$failed"

# Claude Code CLI (separate path: npm, not winget)
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Info ""
    Write-Info "[hint] Claude Code CLI not found. Install via:"
    Write-Info "       npm install -g @anthropic-ai/claude-code"
}

if ($failed -gt 0) {
    exit 1
}
exit 0
