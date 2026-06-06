# build-rules.tests.ps1
# Pester v3.4 smoke tests for scripts/build-rules.ps1 (Windows PowerShell 5.1).
# ASCII only.

$ScriptPath = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "scripts") "build-rules.ps1"
$SourceDir = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "source") "rules"
$TempDist = Join-Path $env:TEMP "engineer-claude-kit-test-dist"
if (Test-Path $TempDist) {
    Remove-Item -Recurse -Force $TempDist
}

Describe "build-rules.ps1" {
    It "exists and is executable" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "runs in dry-run mode without writing files" {
        $output = & powershell -NoProfile -File $ScriptPath `
            -SourceDir $SourceDir `
            -DistDir $TempDist `
            -DryRun 2>&1
        Test-Path $TempDist | Should Be $false
        ($output -join "`n") | Should Match "dry-run"
    }

    It "builds at least one rule from source" {
        & powershell -NoProfile -File $ScriptPath `
            -SourceDir $SourceDir `
            -DistDir $TempDist 2>&1 | Out-Null
        Test-Path $TempDist | Should Be $true
        $built = Get-ChildItem -Path $TempDist -Filter "*.md" -File
        $built.Count | Should BeGreaterThan 0
    }

    It "writes commit-convention.md" {
        $out = Join-Path $TempDist "commit-convention.md"
        Test-Path $out | Should Be $true
    }
}

if (Test-Path $TempDist) {
    Remove-Item -Recurse -Force $TempDist
}
