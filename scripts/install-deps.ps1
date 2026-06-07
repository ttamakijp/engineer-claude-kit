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
