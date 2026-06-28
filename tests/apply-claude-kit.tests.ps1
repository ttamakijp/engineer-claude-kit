# apply-claude-kit.tests.ps1
# Pester v3.4 smoke tests (Windows PowerShell 5.1). ASCII only.
# Script invocations pass -AllowElevated because CI runners (e.g. GitHub
# windows-latest) run elevated and the ADR-0008 fail-fast guard would otherwise
# exit 2 before the script body runs.

# $PSScriptRoot can be empty when Invoke-Pester is given a direct file path
# (vs a directory). Fall back to MyInvocation, then the current location.
$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path $here "..") "scripts") "apply-claude-kit.ps1"
$KitRoot = Join-Path $here ".."
$MockGlobal = Join-Path $env:TEMP "eck-test-global"
$MockProject = Join-Path $env:TEMP "eck-test-project"

if (Test-Path $MockGlobal) { Remove-Item -Recurse -Force $MockGlobal }
if (Test-Path $MockProject) { Remove-Item -Recurse -Force $MockProject }
New-Item -ItemType Directory -Force -Path $MockGlobal | Out-Null
New-Item -ItemType Directory -Force -Path $MockProject | Out-Null
# Group C leak-protection hooks distribute into <project>/.git/hooks, so the
# mock project must be a real git repo for those tests to exercise the path.
& git init -q $MockProject 2>&1 | Out-Null

Describe "apply-claude-kit.ps1" {
    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "runs in DryRun mode (Global)" {
        $output = & powershell -NoProfile -File $ScriptPath -AllowElevated -Global -DryRun 2>&1
        ($output -join "`n") | Should Match "DryRun: yes"
        ($output -join "`n") | Should Match "dry-run"
    }

    It "applies CLAUDE.md and at least one agent in Project mode" {
        & powershell -NoProfile -File $ScriptPath -AllowElevated -Project $MockProject 2>&1 | Out-Null

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

    It "applies checkpoint command in Project mode" {
        Test-Path (Join-Path (Join-Path (Join-Path $MockProject ".claude") "commands") "checkpoint.md") | Should Be $true
    }

    It "applies resume command in Project mode" {
        Test-Path (Join-Path (Join-Path (Join-Path $MockProject ".claude") "commands") "resume.md") | Should Be $true
    }
    It "applies project rules in Project mode" {
        $rulesDir = Join-Path (Join-Path $MockProject ".claude") "rules"
        Test-Path $rulesDir | Should Be $true
        (Get-ChildItem $rulesDir -Filter "*.md").Count | Should BeGreaterThan 0
    }

    It "applies work-end-reminder rule in Project mode" {
        $ruleFile = Join-Path (Join-Path (Join-Path $MockProject ".claude") "rules") "work-end-reminder.md"
        Test-Path $ruleFile | Should Be $true
    }

    It "does NOT apply project rules in Global (DryRun) mode" {
        $output = & powershell -NoProfile -File $ScriptPath -AllowElevated -Global -DryRun 2>&1
        ($output -join "`n") | Should Not Match 'rules'
    }

    It "writes applied marker" {
        $marker = Join-Path $MockProject ".engineer-claude-kit-applied"
        Test-Path $marker | Should Be $true
    }

    It "applies pre-commit hook in Project mode" {
        Test-Path (Join-Path (Join-Path (Join-Path $MockProject ".git") "hooks") "pre-commit") | Should Be $true
    }

    It "applies pre-push hook in Project mode" {
        Test-Path (Join-Path (Join-Path (Join-Path $MockProject ".git") "hooks") "pre-push") | Should Be $true
    }

    It "applies .gitleaks.toml when missing" {
        Test-Path (Join-Path $MockProject ".gitleaks.toml") | Should Be $true
    }

    It "applies .mailmap when missing" {
        Test-Path (Join-Path $MockProject ".mailmap") | Should Be $true
    }

    It "applies .gitignore when missing" {
        Test-Path (Join-Path $MockProject ".gitignore") | Should Be $true
    }

    It "applies work-schedule.yaml in Global (DryRun) mode" {
        # Global mode writes into the real ~/.claude, so we verify via DryRun
        # output instead of touching the user's home directory. The line is
        # present whether the destination is new ([dry-run] ...) or already
        # exists ([skip] ...), so this holds on any machine.
        $output = & powershell -NoProfile -File $ScriptPath -AllowElevated -Global -DryRun 2>&1
        ($output -join "`n") | Should Match 'work-schedule.yaml'
    }

    It "does NOT apply work-schedule.yaml in Project mode" {
        # Project mode is unchanged: the schedule is a single global file.
        Test-Path (Join-Path $MockProject "work-schedule.yaml") | Should Be $false
    }

    It "applies android-build skill in Global (DryRun) mode" {
        $output = & powershell -NoProfile -File $ScriptPath -AllowElevated -Global -DryRun 2>&1 | Out-String
        $output | Should Match 'android-build'
    }

    It "applies install-skill command in Project mode" {
        Test-Path (Join-Path (Join-Path (Join-Path $MockProject ".claude") "commands") "install-skill.md") | Should Be $true
    }

    It "applies skill-installer skill in Project mode" {
        Test-Path (Join-Path (Join-Path (Join-Path $MockProject ".claude") "skills") "skill-installer") | Should Be $true
    }

    It "applies cleanup-processes command in Project mode" {
        Test-Path (Join-Path (Join-Path (Join-Path $MockProject ".claude") "commands") "cleanup-processes.md") | Should Be $true
    }

    It "applies cleanup-orphan-processes skill in Project mode" {
        Test-Path (Join-Path (Join-Path (Join-Path $MockProject ".claude") "skills") "cleanup-orphan-processes") | Should Be $true
    }

    It "does NOT deploy the cleanup scheduled-task without -EnableCleanupSchedule (Global DryRun)" {
        $output = & powershell -NoProfile -File $ScriptPath -AllowElevated -Global -DryRun 2>&1 | Out-String
        $output | Should Match 'scheduled-task not deployed'
    }

    It "deploys the cleanup scheduled-task with -EnableCleanupSchedule (Global DryRun)" {
        $output = & powershell -NoProfile -File $ScriptPath -AllowElevated -Global -DryRun -EnableCleanupSchedule 2>&1 | Out-String
        $output | Should Match 'cleanup-orphan-processes'
    }
}

if (Test-Path $MockGlobal) { Remove-Item -Recurse -Force $MockGlobal }
if (Test-Path $MockProject) { Remove-Item -Recurse -Force $MockProject }
