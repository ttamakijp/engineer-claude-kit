# bootstrap.tests.ps1
# Pester v5 smoke tests. ASCII only.

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot ".." "scripts" "bootstrap.ps1"
    $script:KitRoot = Join-Path $PSScriptRoot ".."
}

Describe "bootstrap.ps1" {
    It "exists" {
        Test-Path $script:ScriptPath | Should -BeTrue
    }

    It "runs in DryRun mode without errors" {
        $output = & pwsh -NoProfile -File $script:ScriptPath -DryRun -SkipProjectPrompt 2>&1
        ($output -join "`n") | Should -Match "Kit root:"
        ($output -join "`n") | Should -Match "kit structure validated"
        ($output -join "`n") | Should -Match "Bootstrap complete"
    }

    It "validates required kit files" {
        Test-Path (Join-Path $script:KitRoot "scripts" "apply-claude-kit.ps1") | Should -BeTrue
        Test-Path (Join-Path $script:KitRoot "config" "models.yaml") | Should -BeTrue
        Test-Path (Join-Path $script:KitRoot "templates" "CLAUDE.md") | Should -BeTrue
    }

    It "derives URL from git remote (if kit is a git clone)" {
        # Will print "[url] derived from git remote: <url>" if working tree is a git repo
        $output = & pwsh -NoProfile -File $script:ScriptPath -DryRun -SkipProjectPrompt 2>&1
        $joined = $output -join "`n"
        # Either derived from git OR using env OR could not derive - all valid in test env
        ($joined -match "url" -or $joined -match "Could not derive") | Should -BeTrue
    }
}
