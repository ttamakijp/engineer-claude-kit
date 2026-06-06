#!/usr/bin/env pwsh
# cost-observe-bedrock.ps1
# Generates a weekly cost report for AWS Bedrock usage via AWS Cost Explorer API.
# ASCII only (no Japanese in code, comments, or strings).
# See ADR-0001 section I, ADR-0003 section B, ADR-0002 (0017 cost-observation portage).

[CmdletBinding()]
param(
    [string]$BudgetConfig,
    [string]$OutputDir,
    [int]$DaysBack = 7,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = "0.1.0"

# --- helpers ---

function Get-KitRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

function Read-MinimalYaml {
    param([string]$Path)

    # Very minimal: handles flat key: value pairs and ignores comments.
    # Used only for cost-budget.yaml schema (flat top-level keys).
    $values = @{}
    if (-not (Test-Path $Path)) { return $values }

    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*$') { continue }
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^#]+?)\s*(#.*)?$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()
            $values[$key] = $val
        }
    }
    return $values
}

function Test-AwsCli {
    $cmd = Get-Command aws -ErrorAction SilentlyContinue
    return ($null -ne $cmd)
}

# --- main ---

$kitRoot = Get-KitRoot
if (-not $BudgetConfig) {
    $BudgetConfig = Join-Path (Join-Path $kitRoot "config") "cost-budget.yaml"
}
if (-not $OutputDir) {
    $OutputDir = Join-Path $kitRoot "reports"
}

Write-Host "engineer-claude-kit cost-observe-bedrock.ps1 (version $ScriptVersion)"
Write-Host "  Kit root: $kitRoot"
Write-Host "  Budget config: $BudgetConfig"
Write-Host "  Output dir: $OutputDir"
Write-Host "  Days back: $DaysBack"
if ($DryRun) { Write-Host "  Mode: dry-run" }

# Check AWS CLI
if (-not (Test-AwsCli)) {
    Write-Warning "AWS CLI not found in PATH."
    Write-Warning "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    if (-not $DryRun) {
        exit 1
    }
}

# Time period
$endDate = Get-Date
$startDate = $endDate.AddDays(-$DaysBack)
$startStr = $startDate.ToString("yyyy-MM-dd")
$endStr = $endDate.ToString("yyyy-MM-dd")

Write-Host ""
Write-Host "Period: $startStr to $endStr"

# Build AWS CLI command
$filter = '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Bedrock"]}}'
$awsArgs = @(
    "ce", "get-cost-and-usage",
    "--time-period", "Start=$startStr,End=$endStr",
    "--granularity", "DAILY",
    "--metrics", "UnblendedCost",
    "--filter", $filter,
    "--output", "json"
)

if ($DryRun) {
    Write-Host ""
    Write-Host "[dry-run] Would invoke:"
    Write-Host "  aws $($awsArgs -join ' ')"
    Write-Host ""
    Write-Host "[dry-run] No actual query performed. Skipping report generation."
    return
}

# Execute Cost Explorer query
Write-Host ""
Write-Host "Querying AWS Cost Explorer..."
try {
    $rawJson = & aws @awsArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI exited with code $LASTEXITCODE. Output: $rawJson"
    }
    $costData = $rawJson | ConvertFrom-Json
} catch {
    Write-Error "Cost Explorer query failed: $_"
    exit 1
}

# Parse daily costs
$dailyCosts = @()
foreach ($period in $costData.ResultsByTime) {
    $entry = [PSCustomObject]@{
        Date = $period.TimePeriod.Start
        Amount = [decimal]$period.Total.UnblendedCost.Amount
        Unit = $period.Total.UnblendedCost.Unit
    }
    $dailyCosts += $entry
}

$totalCost = ($dailyCosts | Measure-Object -Property Amount -Sum).Sum
$avgDailyCost = if ($dailyCosts.Count -gt 0) { $totalCost / $dailyCosts.Count } else { [decimal]0 }

# Read budget config
$budget = Read-MinimalYaml -Path $BudgetConfig
$dailyBudget = $null
$warnPct = 80
$alertPct = 100
if ($budget.ContainsKey('bedrock_daily_budget_usd')) {
    $dailyBudget = [decimal]$budget['bedrock_daily_budget_usd']
}
if ($budget.ContainsKey('warn_threshold_pct')) {
    $warnPct = [int]$budget['warn_threshold_pct']
}
if ($budget.ContainsKey('alert_threshold_pct')) {
    $alertPct = [int]$budget['alert_threshold_pct']
}

# Determine alert level
$alertLevel = "ok"
if ($dailyBudget) {
    $pct = ($avgDailyCost / $dailyBudget) * 100
    if ($pct -ge $alertPct) {
        $alertLevel = "alert"
    } elseif ($pct -ge $warnPct) {
        $alertLevel = "warn"
    }
}

# Generate markdown report
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

$reportDate = $endDate.ToString("yyyy-MM-dd")
$reportPath = Join-Path $OutputDir "bedrock-cost-$reportDate.md"

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Bedrock Cost Report ($reportDate)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Summary")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- Period: $startStr to $endStr ($DaysBack days)")
[void]$sb.AppendLine("- Total cost: USD $($totalCost.ToString('F2'))")
[void]$sb.AppendLine("- Average daily cost: USD $($avgDailyCost.ToString('F2'))")
[void]$sb.AppendLine("- Alert level: $alertLevel")
if ($dailyBudget) {
    [void]$sb.AppendLine("- Daily budget: USD $($dailyBudget.ToString('F2'))")
    [void]$sb.AppendLine("- Warn threshold: $warnPct percent of budget")
    [void]$sb.AppendLine("- Alert threshold: $alertPct percent of budget")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Daily Breakdown")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Date | Cost (USD) |")
[void]$sb.AppendLine("|---|---|")
foreach ($entry in $dailyCosts) {
    [void]$sb.AppendLine("| $($entry.Date) | $($entry.Amount.ToString('F4')) |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Notes")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- Source: AWS Cost Explorer (UnblendedCost metric)")
[void]$sb.AppendLine("- Filter: SERVICE = Amazon Bedrock")
[void]$sb.AppendLine("- Granularity: DAILY")
[void]$sb.AppendLine("- Generated by cost-observe-bedrock.ps1 v$ScriptVersion")

Set-Content -LiteralPath $reportPath -Value $sb.ToString() -Encoding UTF8 -NoNewline
Write-Host ""
Write-Host "Report written: $reportPath"

# Final summary
Write-Host ""
Write-Host "Total cost: USD $($totalCost.ToString('F2'))"
Write-Host "Average daily cost: USD $($avgDailyCost.ToString('F2'))"
Write-Host "Alert level: $alertLevel"

if ($alertLevel -eq "alert") {
    Write-Warning "Budget alert: avg daily cost ($avgDailyCost) exceeds daily budget ($dailyBudget)"
    exit 2
} elseif ($alertLevel -eq "warn") {
    Write-Warning "Budget warning: avg daily cost ($avgDailyCost) is at $warnPct percent or more of daily budget ($dailyBudget)"
    exit 0
}
