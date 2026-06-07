# cost-observe-bedrock.tests.ps1
# Pester v3.4 smoke tests (Windows PowerShell 5.1). ASCII only.

# $PSScriptRoot can be empty when Invoke-Pester is given a direct file path
# (vs a directory). Fall back to MyInvocation, then the current location.
$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path $here "..") "scripts") "cost-observe-bedrock.ps1"
$KitRoot = Join-Path $here ".."
$BudgetConfig = Join-Path (Join-Path $KitRoot "config") "cost-budget.yaml"

Describe "cost-observe-bedrock.ps1" {
    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "budget config exists" {
        Test-Path $BudgetConfig | Should Be $true
    }

    It "runs in DryRun mode and prints AWS CLI command preview" {
        $output = & powershell -NoProfile -File $ScriptPath -DryRun 2>&1
        $joined = $output -join "`n"
        $joined | Should Match "Mode: dry-run"
        $joined | Should Match "(aws ce get-cost-and-usage|AWS CLI not found)"
    }

    It "does not generate a report file in DryRun mode" {
        $tempReportDir = Join-Path $env:TEMP "eck-cost-dryrun-test"
        if (Test-Path $tempReportDir) { Remove-Item -Recurse -Force $tempReportDir }

        & powershell -NoProfile -File $ScriptPath -DryRun -OutputDir $tempReportDir 2>&1 | Out-Null
        Test-Path $tempReportDir | Should Be $false
    }
}
