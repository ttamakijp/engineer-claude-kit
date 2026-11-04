# config-deploy.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Covers ADR-0017: the local-llm delegation config and the system prompts it
# names have to reach ~/.claude/, and 'system_prompt_ref' has to resolve against
# the DEPLOYED yaml rather than the kit checkout. Snapshot 4 measured 0 local
# calls while the repo itself was correct, because nothing deployed any of it.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$KitRoot = (Resolve-Path (Join-Path $here "..")).Path
$libDir = Join-Path (Join-Path $KitRoot "scripts") "lib"
. (Join-Path $libDir "encoding-helper.ps1")
. (Join-Path $libDir "link-safety.ps1")
. (Join-Path $libDir "config-deploy.ps1")

function New-HomeFixture {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("cfgdeploy-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

Describe "Install-KitLocalLlmConfig" {
    It "deploys the delegation config under the target config dir" {
        $target = New-HomeFixture
        $applied = @(Install-KitLocalLlmConfig -KitRoot $KitRoot -HomeClaude $target)
        $dest = Join-Path (Join-Path $target "config") "local-llm-delegation.yaml"

        Test-Path $dest | Should Be $true
        ($applied -contains $dest) | Should Be $true
        Remove-Item -Recurse -Force $target
    }

    It "deploys every system prompt the config names" {
        $target = New-HomeFixture
        $null = Install-KitLocalLlmConfig -KitRoot $KitRoot -HomeClaude $target
        $promptDir = Join-Path (Join-Path $target "config") "local-llm"

        foreach ($n in @('log-summary.md', 'commit-message.md', 'review-file.md')) {
            Test-Path (Join-Path $promptDir $n) | Should Be $true
        }
        Remove-Item -Recurse -Force $target
    }

    # The contract of ADR-0017 decision B, asserted where it matters: against the
    # deployed copy. A kit-relative ref ("templates/local-llm/x.md") would pass a
    # repo-side check and still be unresolvable from ~/.claude/config/.
    It "resolves every system_prompt_ref against the deployed yaml" {
        $target = New-HomeFixture
        $null = Install-KitLocalLlmConfig -KitRoot $KitRoot -HomeClaude $target
        $dest = Join-Path (Join-Path $target "config") "local-llm-delegation.yaml"
        $cfgDir = Split-Path -Parent $dest

        $refs = @()
        foreach ($line in ((Read-Utf8NoBom -Path $dest) -split "`r?`n")) {
            if ($line -match '^\s*system_prompt_ref\s*:\s*(\S+)\s*$') { $refs += $Matches[1] }
        }
        @($refs).Count | Should Be 3
        $missing = @()
        foreach ($r in $refs) {
            if (-not (Test-Path (Join-Path $cfgDir $r))) { $missing += $r }
        }
        ($missing -join ', ') | Should Be ''
        Remove-Item -Recurse -Force $target
    }

    It "writes nothing in dry-run mode" {
        $target = New-HomeFixture
        $null = Install-KitLocalLlmConfig -KitRoot $KitRoot -HomeClaude $target -IsDryRun
        Test-Path (Join-Path $target "config") | Should Be $false
        Remove-Item -Recurse -Force $target
    }

    # Generated kit content, so it is overwritten rather than preserved; a copy
    # the user had diverged from is backed up first.
    It "backs up a diverging deployed copy before overwriting it" {
        $target = New-HomeFixture
        $dest = Join-Path (Join-Path $target "config") "local-llm-delegation.yaml"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        Write-Utf8NoBom -Path $dest -Content "enabled: false  # hand edited"

        $null = Install-KitLocalLlmConfig -KitRoot $KitRoot -HomeClaude $target `
            -BackupRoot (Join-Path $target "backups") -BackupStamp "s1"

        $saved = @(Get-ChildItem -LiteralPath (Join-Path $target "backups") -Recurse `
            -Filter "local-llm-delegation.yaml" -File)
        @($saved).Count | Should BeGreaterThan 0
        (Read-Utf8NoBom -Path $saved[0].FullName) | Should Match 'hand edited'
        Remove-Item -Recurse -Force $target
    }

    It "takes no backup when the deployed copy already matches" {
        $target = New-HomeFixture
        $null = Install-KitLocalLlmConfig -KitRoot $KitRoot -HomeClaude $target `
            -BackupRoot (Join-Path $target "backups") -BackupStamp "s1"
        $null = Install-KitLocalLlmConfig -KitRoot $KitRoot -HomeClaude $target `
            -BackupRoot (Join-Path $target "backups") -BackupStamp "s2"

        Test-Path (Join-Path $target "backups") | Should Be $false
        Remove-Item -Recurse -Force $target
    }
}

Describe "Install-KitWorkSchedule" {
    # Regression for the extraction out of apply-claude-kit.ps1: the preserve
    # policy (ADR-0006) has to survive the move into this lib.
    It "deploys the schedule when the target has none" {
        $target = New-HomeFixture
        $applied = @(Install-KitWorkSchedule -KitRoot $KitRoot -HomeClaude $target)
        Test-Path (Join-Path $target "work-schedule.yaml") | Should Be $true
        @($applied).Count | Should Be 1
        Remove-Item -Recurse -Force $target
    }
    It "preserves a schedule the user already edited" {
        $target = New-HomeFixture
        $dest = Join-Path $target "work-schedule.yaml"
        Write-Utf8NoBom -Path $dest -Content "end_time: 18:30  # mine"

        $applied = @(Install-KitWorkSchedule -KitRoot $KitRoot -HomeClaude $target)

        (Read-Utf8NoBom -Path $dest) | Should Match 'mine'
        @($applied).Count | Should Be 0
        Remove-Item -Recurse -Force $target
    }
}

Describe "check-kit-deployment.ps1" {
    $CheckScript = Join-Path (Join-Path $KitRoot "scripts") "check-kit-deployment.ps1"
    $DistRules = Join-Path (Join-Path (Join-Path $KitRoot "dist") ".claude") "rules"

    It "exists" {
        Test-Path $CheckScript | Should Be $true
    }

    # The whole point of the script: it has to fail on the state the user
    # reported (config absent, firing rule absent) instead of reporting a
    # healthy kit.
    It "fails when nothing has been deployed" {
        $target = New-HomeFixture
        $claude = Join-Path $target ".claude"
        New-Item -ItemType Directory -Force -Path $claude | Out-Null

        $output = & powershell -NoProfile -File $CheckScript -TargetRoot $claude -KitRoot $KitRoot 2>&1
        $code = $LASTEXITCODE

        $code | Should Be 1
        ($output -join "`n") | Should Match 'local-llm-delegation'
        Remove-Item -Recurse -Force $target
    }

    It "passes once the config and the firing rule are deployed" {
        $target = New-HomeFixture
        $claude = Join-Path $target ".claude"
        $rules = Join-Path $claude "rules"
        New-Item -ItemType Directory -Force -Path $rules | Out-Null

        # Mirror what apply produces: every built rule, the config payload, and a
        # CLAUDE.md naming the deployed path.
        if (-not (Test-Path $DistRules)) {
            & powershell -NoProfile -File (Join-Path (Join-Path $KitRoot "scripts") "build-rules.ps1") `
                -SourceDir (Join-Path (Join-Path $KitRoot "source") "rules") -DistDir $DistRules 2>&1 | Out-Null
        }
        foreach ($r in (Get-ChildItem -LiteralPath $DistRules -Filter "*.md" -File)) {
            Write-Utf8NoBom -Path (Join-Path $rules $r.Name) -Content (Read-Utf8NoBom -Path $r.FullName)
        }
        $null = Install-KitLocalLlmConfig -KitRoot $KitRoot -HomeClaude $claude
        $md = '## 3.' + [Environment]::NewLine + '~/.claude/config/local-llm-delegation.yaml'
        Write-Utf8NoBom -Path (Join-Path $claude "CLAUDE.md") -Content $md

        $output = & powershell -NoProfile -File $CheckScript -TargetRoot $claude -KitRoot $KitRoot 2>&1
        $code = $LASTEXITCODE

        ($output -join "`n") | Should Match 'PASS'
        $code | Should Be 0
        Remove-Item -Recurse -Force $target
    }

    # The Haiku-agent contradiction is a pending decision (ADR-0017 phase 2), so
    # it has to report without failing the run -- otherwise the script could
    # never be used as a gate.
    It "reports a Haiku delegation agent as a warning, not a failure" {
        $target = New-HomeFixture
        $claude = Join-Path $target ".claude"
        $agents = Join-Path $claude "agents"
        New-Item -ItemType Directory -Force -Path (Join-Path $claude "rules") | Out-Null
        New-Item -ItemType Directory -Force -Path $agents | Out-Null
        Write-Utf8NoBom -Path (Join-Path $agents "commit-msg.md") -Content "# haiku"

        $output = (& powershell -NoProfile -File $CheckScript -TargetRoot $claude -KitRoot $KitRoot 2>&1) -join "`n"

        $output | Should Match 'warn'
        $output | Should Match 'commit-msg'
        Remove-Item -Recurse -Force $target
    }
}
