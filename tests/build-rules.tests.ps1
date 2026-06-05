# build-rules.tests.ps1
# Pester v5 smoke tests for scripts/build-rules.ps1
# ASCII only.

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot ".." "scripts" "build-rules.ps1"
    $script:SourceDir = Join-Path $PSScriptRoot ".." "source" "rules"
    $script:TempDist = Join-Path $env:TEMP "engineer-claude-kit-test-dist"
    if (Test-Path $script:TempDist) {
        Remove-Item -Recurse -Force $script:TempDist
    }
}

Describe "build-rules.ps1" {
    It "exists and is executable" {
        Test-Path $script:ScriptPath | Should -BeTrue
    }

    It "runs in dry-run mode without writing files" {
        $output = & pwsh -NoProfile -File $script:ScriptPath `
            -SourceDir $script:SourceDir `
            -DistDir $script:TempDist `
            -DryRun 2>&1
        Test-Path $script:TempDist | Should -BeFalse
        ($output -join "`n") | Should -Match "dry-run"
    }

    It "builds at least one rule from source" {
        & pwsh -NoProfile -File $script:ScriptPath `
            -SourceDir $script:SourceDir `
            -DistDir $script:TempDist 2>&1 | Out-Null
        Test-Path $script:TempDist | Should -BeTrue
        $built = Get-ChildItem -Path $script:TempDist -Filter "*.md" -File
        $built.Count | Should -BeGreaterThan 0
    }

    It "writes commit-convention.md" {
        $out = Join-Path $script:TempDist "commit-convention.md"
        Test-Path $out | Should -BeTrue
    }
}

AfterAll {
    if (Test-Path $script:TempDist) {
        Remove-Item -Recurse -Force $script:TempDist
    }
}
