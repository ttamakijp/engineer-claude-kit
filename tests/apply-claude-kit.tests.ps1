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

    # Was asserted on commit-msg.md until ADR-0016 decision B withdrew the three
    # Haiku delegation agents. architect.md resolves {{role:heavy}} instead, and
    # 'claude-sonnet' is the part both the Bedrock and the Anthropic-direct id
    # share, so the assertion survives a models.yaml adapted to either.
    It "substitutes placeholders" {
        $architectAgent = Join-Path (Join-Path (Join-Path $MockProject ".claude") "agents") "architect.md"
        Test-Path $architectAgent | Should Be $true
        $content = Get-Content -LiteralPath $architectAgent -Raw
        $content | Should Not Match '\{\{role:'
        $content | Should Match 'claude-sonnet'
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

    # Reversed by ADR-0015 step 3. This previously asserted that Global mode
    # mentions no rules at all, encoding the behaviour that left a Global-only
    # install with its rules deployed nowhere: Claude Code reads
    # ~/.claude/rules/*.md for every project, so Global is where user-level rules
    # belong. DryRun keeps the real ~/.claude untouched.
    It "applies user-level rules in Global (DryRun) mode" {
        $output = & powershell -NoProfile -File $ScriptPath -AllowElevated -Global -DryRun 2>&1
        $joined = ($output -join "`n")
        $joined | Should Match 'commit-convention\.md'
        $joined | Should Match ([regex]::Escape((Join-Path (Join-Path $env:USERPROFILE ".claude") "rules")))
    }

    It "writes applied marker" {
        $marker = Join-Path $MockProject ".engineer-claude-kit-applied"
        Test-Path $marker | Should Be $true
    }

    # ADR-0016 decision B withdrew three agents. Deploy only writes what the kit
    # ships now, so without orphan removal the already-deployed copies would stay
    # in <target>/agents/ and keep appearing in every session's agent roster.
    # Driven with a name the kit never shipped, so the test does not break the
    # next time the shipped set changes.
    It "removes an agent it deployed before but no longer ships" {
        $agentsDir = Join-Path (Join-Path $MockProject ".claude") "agents"
        $withdrawn = Join-Path $agentsDir "zz-withdrawn.md"
        Set-Content -LiteralPath $withdrawn -Value "# withdrawn agent" -Encoding ASCII

        # Attribution: only files the previous run's marker lists are removed, so
        # the fixture has to appear in applied_files the way apply would have left
        # it. A hand-written agent is never listed, and the test below covers it.
        $marker = Join-Path $MockProject ".engineer-claude-kit-applied"
        $json = (Get-Content -LiteralPath $marker -Raw) | ConvertFrom-Json
        $files = @()
        $json.applied_files | ForEach-Object { $files += [string]$_ }
        $files += $withdrawn
        $json.applied_files = $files
        [System.IO.File]::WriteAllText($marker, ($json | ConvertTo-Json -Depth 5),
            (New-Object System.Text.UTF8Encoding $false))

        $mine = Join-Path $agentsDir "zz-my-own.md"
        Set-Content -LiteralPath $mine -Value "# hand written" -Encoding ASCII

        & powershell -NoProfile -File $ScriptPath -AllowElevated -Project $MockProject 2>&1 | Out-Null

        Test-Path $withdrawn | Should Be $false
        Test-Path $mine | Should Be $true
        Test-Path (Join-Path $agentsDir "architect.md") | Should Be $true
        Remove-Item -LiteralPath $mine -Force
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

    It "gates the settings wizard behind Test-IsInteractive with a skip hint (G6k)" {
        # The wizard block must call Test-IsInteractive and, on the non-interactive
        # branch, emit the auto-skip hint instead of invoking the wizard (which
        # would Read-Host and hang under a redirected stdin / slash command).
        $scriptText = Get-Content -LiteralPath $ScriptPath -Raw
        $scriptText | Should Match 'Test-IsInteractive'
        $scriptText | Should Match 'non-interactive context'
        $scriptText | Should Match '-NoSettingsWizard to silence'
    }

    It "auto-creates the scheduled-task parent dir when absent (G6i regression)" {
        # Copy-ScheduledTaskDir now lives in lib/scheduled-tasks-deploy.ps1, so it
        # can be dot-sourced directly. It previously had to be regex-extracted
        # from apply-claude-kit.ps1 and Invoke-Expression'd, because that script
        # has no dot-source guard and running it would perform a real apply.
        # The function depends on Read/Write-Utf8NoBom from the encoding helper.
        $libDir = Join-Path (Join-Path $KitRoot "scripts") "lib"
        . (Join-Path $libDir "encoding-helper.ps1")
        . (Join-Path $libDir "scheduled-tasks-deploy.ps1")
        (Get-Command Copy-ScheduledTaskDir -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty

        # Source: a task subdir with one spec. Target: a brand-new root whose
        # scheduled-tasks/<name>/ subtree does NOT exist yet (the bug repro).
        $srcRoot = Join-Path $env:TEMP "eck-g6i-src"
        $tgtRoot = Join-Path $env:TEMP "eck-g6i-tgt"
        foreach ($d in @($srcRoot, $tgtRoot)) { if (Test-Path $d) { Remove-Item -Recurse -Force $d } }
        $srcTask = Join-Path $srcRoot "daily-usage-insights"
        New-Item -ItemType Directory -Force -Path $srcTask | Out-Null
        Set-Content -LiteralPath (Join-Path $srcTask "daily-usage-insights.md") -Value "# spec" -Encoding ASCII

        $schedTasksDir = Join-Path $tgtRoot "scheduled-tasks"
        $deployed = Copy-ScheduledTaskDir -SourceTaskDir $srcTask -TargetSchedTasksDir $schedTasksDir

        $expected = Join-Path (Join-Path $schedTasksDir "daily-usage-insights") "daily-usage-insights.md"
        Test-Path $expected | Should Be $true
        ($deployed -contains $expected) | Should Be $true

        foreach ($d in @($srcRoot, $tgtRoot)) { if (Test-Path $d) { Remove-Item -Recurse -Force $d } }
    }
}

if (Test-Path $MockGlobal) { Remove-Item -Recurse -Force $MockGlobal }
if (Test-Path $MockProject) { Remove-Item -Recurse -Force $MockProject }
