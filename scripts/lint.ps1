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

Write-Host "[lint] Engineer Claude Kit - PSScriptAnalyzer lint"
Write-Host "[lint] Target: PowerShell 5.1 compatibility"

# Ensure PSScriptAnalyzer
$psa = Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -First 1
if (-not $psa) {
    Write-Warning "PSScriptAnalyzer not installed. Installing..."
    try {
        Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
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
