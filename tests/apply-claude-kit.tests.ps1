# apply-claude-kit.tests.ps1
# Pester v5 smoke tests. ASCII only.

BeforeAll {
    $script:ScriptPath = Join-Path (Join-Path $PSScriptRoot "..") "scripts" | Join-Path -ChildPath "apply-claude-kit.ps1"
    $script:KitRoot = Join-Path $PSScriptRoot ".."
    $script:MockGlobal = Join-Path $env:TEMP "eck-test-global"
    $script:MockProject = Join-Path $env:TEMP "eck-test-project"

    if (Test-Path $script:MockGlobal) { Remove-Item -Recurse -Force $script:MockGlobal }
    if (Test-Path $script:MockProject) { Remove-Item -Recurse -Force $script:MockProject }
    New-Item -ItemType Directory -Force -Path $script:MockGlobal | Out-Null
    New-Item -ItemType Directory -Force -Path $script:MockProject | Out-Null
}

Describe "apply-claude-kit.ps1" {
    It "exists" {
        Test-Path $script:ScriptPath | Should -BeTrue
    }

    It "runs in DryRun mode (Global)" {
        $output = & pwsh -NoProfile -File $script:ScriptPath -Global -DryRun 2>&1
        ($output -join "`n") | Should -Match "DryRun: yes"
        ($output -join "`n") | Should -Match "dry-run"
    }

    It "applies CLAUDE.md and at least one agent in Project mode" {
        & pwsh -NoProfile -File $script:ScriptPath -Project $script:MockProject 2>&1 | Out-Null

        $claudeMd = Join-Path $script:MockProject "CLAUDE.md"
        Test-Path $claudeMd | Should -BeTrue

        $agentDir = Join-Path (Join-Path $script:MockProject ".claude") "agents"
        Test-Path $agentDir | Should -BeTrue
        (Get-ChildItem $agentDir -Filter "*.md").Count | Should -BeGreaterThan 0
    }

    It "substitutes placeholders" {
        $commitMsgAgent = Join-Path (Join-Path (Join-Path $script:MockProject ".claude") "agents") "commit-msg.md"
        Test-Path $commitMsgAgent | Should -BeTrue
        $content = Get-Content -LiteralPath $commitMsgAgent -Raw
        $content | Should -Not -Match '\{\{role:'
        $content | Should -Match 'claude-haiku-4-5'
    }

    It "applies skills in Project mode" {
        $skillDir = Join-Path (Join-Path $script:MockProject ".claude") "skills"
        Test-Path $skillDir | Should -BeTrue
        (Get-ChildItem $skillDir -Recurse -Filter "SKILL.md").Count | Should -BeGreaterThan 0
    }

    It "places commit-helper skill" {
        $commitHelperSkill = Join-Path (Join-Path (Join-Path (Join-Path $script:MockProject ".claude") "skills") "commit-helper") "SKILL.md"
        Test-Path $commitHelperSkill | Should -BeTrue
    }

    It "writes applied marker" {
        $marker = Join-Path $script:MockProject ".engineer-claude-kit-applied"
        Test-Path $marker | Should -BeTrue
    }
}

AfterAll {
    if (Test-Path $script:MockGlobal) { Remove-Item -Recurse -Force $script:MockGlobal }
    if (Test-Path $script:MockProject) { Remove-Item -Recurse -Force $script:MockProject }
}
