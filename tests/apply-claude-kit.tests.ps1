# apply-claude-kit.tests.ps1
# Pester v3.4 smoke tests (Windows PowerShell 5.1). ASCII only.

$ScriptPath = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "scripts") "apply-claude-kit.ps1"
$KitRoot = Join-Path $PSScriptRoot ".."
$MockGlobal = Join-Path $env:TEMP "eck-test-global"
$MockProject = Join-Path $env:TEMP "eck-test-project"

if (Test-Path $MockGlobal) { Remove-Item -Recurse -Force $MockGlobal }
if (Test-Path $MockProject) { Remove-Item -Recurse -Force $MockProject }
New-Item -ItemType Directory -Force -Path $MockGlobal | Out-Null
New-Item -ItemType Directory -Force -Path $MockProject | Out-Null

Describe "apply-claude-kit.ps1" {
    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "runs in DryRun mode (Global)" {
        $output = & powershell -NoProfile -File $ScriptPath -Global -DryRun 2>&1
        ($output -join "`n") | Should Match "DryRun: yes"
        ($output -join "`n") | Should Match "dry-run"
    }

    It "applies CLAUDE.md and at least one agent in Project mode" {
        & powershell -NoProfile -File $ScriptPath -Project $MockProject 2>&1 | Out-Null

        $claudeMd = Join-Path $MockProject "CLAUDE.md"
        Test-Path $claudeMd | Should Be $true

        $agentDir = Join-Path (Join-Path $MockProject ".claude") "agents"
        Test-Path $agentDir | Should Be $true
        (Get-ChildItem $agentDir -Filter "*.md").Count | Should BeGreaterThan 0
    }

    It "substitutes placeholders" {
        $commitMsgAgent = Join-Path (Join-Path (Join-Path $MockProject ".claude") "agents") "commit-msg.md"
        Test-Path $commitMsgAgent | Should Be $true
        $content = Get-Content -LiteralPath $commitMsgAgent -Raw
        $content | Should Not Match '\{\{role:'
        $content | Should Match 'claude-haiku-4-5'
    }

    It "applies skills in Project mode" {
        $skillDir = Join-Path (Join-Path $MockProject ".claude") "skills"
        Test-Path $skillDir | Should Be $true
        (Get-ChildItem $skillDir -Recurse -Filter "SKILL.md").Count | Should BeGreaterThan 0
    }

    It "places commit-helper skill" {
        $commitHelperSkill = Join-Path (Join-Path (Join-Path (Join-Path $MockProject ".claude") "skills") "commit-helper") "SKILL.md"
        Test-Path $commitHelperSkill | Should Be $true
    }

    It "applies commands in Project mode" {
        $commandsDir = Join-Path (Join-Path $MockProject ".claude") "commands"
        Test-Path $commandsDir | Should Be $true
        (Get-ChildItem $commandsDir -Filter "*.md").Count | Should BeGreaterThan 0
    }

    It "places apply command" {
        $applyCommand = Join-Path (Join-Path (Join-Path $MockProject ".claude") "commands") "apply.md"
        Test-Path $applyCommand | Should Be $true
    }

    It "writes applied marker" {
        $marker = Join-Path $MockProject ".engineer-claude-kit-applied"
        Test-Path $marker | Should Be $true
    }
}

if (Test-Path $MockGlobal) { Remove-Item -Recurse -Force $MockGlobal }
if (Test-Path $MockProject) { Remove-Item -Recurse -Force $MockProject }
