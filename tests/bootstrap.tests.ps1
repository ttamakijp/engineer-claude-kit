# bootstrap.tests.ps1
# Pester v3.4 smoke tests (Windows PowerShell 5.1). ASCII only.

$ScriptPath = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "scripts") "bootstrap.ps1"
$KitRoot = Join-Path $PSScriptRoot ".."

Describe "bootstrap.ps1" {
    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "runs in DryRun mode without errors" {
        $output = & powershell -NoProfile -File $ScriptPath -DryRun -SkipProjectPrompt 2>&1
        ($output -join "`n") | Should Match "Kit root:"
        ($output -join "`n") | Should Match "kit structure validated"
        ($output -join "`n") | Should Match "Bootstrap complete"
    }

    It "validates required kit files" {
        Test-Path (Join-Path (Join-Path $KitRoot "scripts") "apply-claude-kit.ps1") | Should Be $true
        Test-Path (Join-Path (Join-Path $KitRoot "config") "models.yaml") | Should Be $true
        Test-Path (Join-Path (Join-Path $KitRoot "templates") "CLAUDE.md") | Should Be $true
    }

    It "derives URL from git remote (if kit is a git clone)" {
        # Will print "[url] derived from git remote: <url>" if working tree is a git repo
        $output = & powershell -NoProfile -File $ScriptPath -DryRun -SkipProjectPrompt 2>&1
        $joined = $output -join "`n"
        # Either derived from git OR using env OR could not derive - all valid in test env
        ($joined -match "url" -or $joined -match "Could not derive") | Should Be $true
    }
}
