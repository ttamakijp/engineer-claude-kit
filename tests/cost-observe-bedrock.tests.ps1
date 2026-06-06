# cost-observe-bedrock.tests.ps1
# Pester v5 smoke tests. ASCII only.

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot ".." "scripts" "cost-observe-bedrock.ps1"
    $script:KitRoot = Join-Path $PSScriptRoot ".."
    $script:BudgetConfig = Join-Path $script:KitRoot "config" "cost-budget.yaml"
}

Describe "cost-observe-bedrock.ps1" {
    It "exists" {
        Test-Path $script:ScriptPath | Should -BeTrue
    }

    It "budget config exists" {
        Test-Path $script:BudgetConfig | Should -BeTrue
    }

    It "runs in DryRun mode and prints AWS CLI command preview" {
        $output = & pwsh -NoProfile -File $script:ScriptPath -DryRun 2>&1
        $joined = $output -join "`n"
        $joined | Should -Match "Mode: dry-run"
        $joined | Should -Match "(aws ce get-cost-and-usage|AWS CLI not found)"
    }

    It "does not generate a report file in DryRun mode" {
        $tempReportDir = Join-Path $env:TEMP "eck-cost-dryrun-test"
        if (Test-Path $tempReportDir) { Remove-Item -Recurse -Force $tempReportDir }

        & pwsh -NoProfile -File $script:ScriptPath -DryRun -OutputDir $tempReportDir 2>&1 | Out-Null
        Test-Path $tempReportDir | Should -BeFalse
    }
}
