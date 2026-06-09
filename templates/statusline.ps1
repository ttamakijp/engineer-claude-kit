#requires -Version 5.1
# statusline.ps1 - Claude Code status line (ADR-0012 color-coded context usage)
#
# Renders: [<model>] <pct>% context  <dir> git:<branch>
# The percentage is color-coded: green < 75%, yellow 75-90%, red >= 90%.
#
# Why a -File script instead of an inline -Command (the original ship form):
# On Windows, Claude Code runs the statusLine command through Git Bash whenever
# Git Bash is installed. An inline 'powershell -Command "...$_..."' has its $
# tokens ($input, $_, $p, ...) expanded by bash BEFORE PowerShell sees them,
# corrupting the command so it prints nothing (silent blank statusline). A -File
# path carries no $ tokens for bash to touch, so the logic stays intact under
# Git Bash, cmd, or PowerShell alike. See ADR-0012 (2026-06-09 amendment).
#
# ASCII only (ADR-0003 section C). PS 5.1 compatible (no `e, no PS 6+ syntax).

$ErrorActionPreference = 'SilentlyContinue'

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
Write-Host ($esc + '[' + $color + 'm[' + $model + '] ' + $p + '% context' + $esc + '[0m ' + $leaf + $git)
