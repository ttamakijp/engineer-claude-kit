#requires -Version 5.1
# lint.ps1
# PSScriptAnalyzer runner for engineer-claude-kit (local + CI shared).
# Target: Windows PowerShell 5.1 compatibility (ADR-0001).
# ASCII only (no Japanese in code, comments, or strings).
[CmdletBinding()]
param(
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'

function Install-PSScriptAnalyzerNonInteractive {
    # Install PSScriptAnalyzer in a way that succeeds in a non-interactive shell.
    # Three things break the default Install-Module flow when unattended:
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
        Write-Host "[lint] Installing NuGet package provider..."
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

Write-Host "[lint] Engineer Claude Kit - PSScriptAnalyzer lint"
Write-Host "[lint] Target: PowerShell 5.1 compatibility"

# Ensure PSScriptAnalyzer
$psa = Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -First 1
if (-not $psa) {
    Write-Warning "PSScriptAnalyzer not installed. Installing..."
    try {
        Install-PSScriptAnalyzerNonInteractive
    } catch {
        Write-Error "Failed to install PSScriptAnalyzer: $_"
        exit 1
    }
}

Import-Module PSScriptAnalyzer

$kitRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $kitRoot "PSScriptAnalyzerSettings.psd1"

if (-not (Test-Path $settingsPath)) {
    Write-Error "Settings not found: $settingsPath"
    exit 1
}

$paths = @(
    Join-Path $kitRoot "scripts"
    Join-Path $kitRoot "tests"
)

$allResults = @()
foreach ($p in $paths) {
    if (Test-Path $p) {
        Write-Host "[lint] Scanning: $p"
        $results = Invoke-ScriptAnalyzer -Path $p -Recurse -Settings $settingsPath
        if ($results) {
            $allResults += $results
        }
    }
}

if ($allResults.Count -gt 0) {
    Write-Host ""
    Write-Host "[lint] Found $($allResults.Count) issue(s):"
    $allResults | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize -Wrap

    if ($Strict) {
        Write-Error "[lint] FAILED (Strict mode enabled)"
        exit 1
    } else {
        Write-Warning "[lint] Issues found but not in Strict mode (exit 0)"
        exit 0
    }
}

Write-Host "[lint] PASS - no issues found"
exit 0
