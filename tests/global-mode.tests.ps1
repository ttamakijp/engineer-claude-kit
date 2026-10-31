# global-mode.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Covers the Global-mode deployment path of apply-claude-kit.ps1 (ADR-0015 step
# 3), which until now deployed no rules at all: the Global branch set the rules
# target to $null, so a Global-only install left every kit rule unreachable.
#
# $env:USERPROFILE is redirected to a temp directory for the duration of the
# apply run so the real ~/.claude is never written to. It is restored in a
# finally block, because leaking the override would corrupt later suites.
#
# -NoSettingsWizard / -NonInteractive keep the interactive wizard out (ADR-0010),
# -NoUpdateCheck keeps the run offline, and -AllowElevated is required because CI
# runners execute elevated and the ADR-0008 guard would otherwise exit early.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path $here "..") "scripts") "apply-claude-kit.ps1"
$KitRoot = (Resolve-Path (Join-Path $here "..")).Path
$DistRules = Join-Path (Join-Path (Join-Path $KitRoot "dist") ".claude") "rules"

# Write-Utf8NoBom (fixture authoring) and Get-LinkState (assertions) come from the
# same lib the script under test uses.
$libDir = Join-Path (Join-Path $KitRoot "scripts") "lib"
. (Join-Path $libDir "encoding-helper.ps1")
. (Join-Path $libDir "link-safety.ps1")

$MockHome = Join-Path $env:TEMP "eck-test-globalmode"
if (Test-Path $MockHome) { Remove-Item -Recurse -Force $MockHome }
New-Item -ItemType Directory -Force -Path $MockHome | Out-Null

$savedProfile = $env:USERPROFILE
try {
    $env:USERPROFILE = $MockHome
    & powershell -NoProfile -File $ScriptPath -Global -AllowElevated `
        -NoSettingsWizard -NonInteractive -NoUpdateCheck 2>&1 | Out-Null
} finally {
    $env:USERPROFILE = $savedProfile
}

$MockClaude = Join-Path $MockHome ".claude"
$MockRules = Join-Path $MockClaude "rules"

Describe "apply-claude-kit.ps1 Global-mode rule distribution" {
    It "creates ~/.claude/rules/" {
        Test-Path $MockRules | Should Be $true
    }
    It "deploys every built rule" {
        $expected = @(Get-ChildItem -LiteralPath $DistRules -Filter "*.md" -File).Count
        $actual = @(Get-ChildItem -LiteralPath $MockRules -Filter "*.md" -File -ErrorAction SilentlyContinue).Count
        $actual | Should Be $expected
    }
    It "copies a rule verbatim" {
        $src = Join-Path $DistRules "commit-convention.md"
        $dst = Join-Path $MockRules "commit-convention.md"
        Test-Path $dst | Should Be $true
        (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash |
            Should Be (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    }
    It "preserves the paths frontmatter that scopes a rule" {
        $dst = Join-Path $MockRules "security-mobile.md"
        $text = [System.IO.File]::ReadAllText($dst)
        $text | Should Match "(?m)^paths:"
    }
    It "deploys CLAUDE.md as a regular file, not a link" {
        $md = Join-Path $MockClaude "CLAUDE.md"
        Test-Path $md | Should Be $true
        $state = Get-LinkState -Path $md
        $state.IsLink | Should Be $false
    }
    It "leaves no backup directory when nothing was overwritten" {
        # A first-time Global apply overwrites nothing, so New-KitBackup must not
        # have created an empty timestamped folder.
        Test-Path (Join-Path $MockClaude "backups") | Should Be $false
    }
}

Describe "apply-claude-kit.ps1 Global-mode re-apply" {
    It "is idempotent for rules and takes no backup when content matches" {
        $savedProfile2 = $env:USERPROFILE
        try {
            $env:USERPROFILE = $MockHome
            & powershell -NoProfile -File $ScriptPath -Global -AllowElevated `
                -NoSettingsWizard -NonInteractive -NoUpdateCheck 2>&1 | Out-Null
        } finally {
            $env:USERPROFILE = $savedProfile2
        }
        $src = Join-Path $DistRules "commit-convention.md"
        $dst = Join-Path $MockRules "commit-convention.md"
        (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash |
            Should Be (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
        Test-Path (Join-Path $MockClaude "backups") | Should Be $false
    }
    It "backs up a hand-edited rule before overwriting it" {
        $dst = Join-Path $MockRules "commit-convention.md"
        Write-Utf8NoBom -Path $dst -Content "locally edited rule"
        $savedProfile3 = $env:USERPROFILE
        try {
            $env:USERPROFILE = $MockHome
            & powershell -NoProfile -File $ScriptPath -Global -AllowElevated `
                -NoSettingsWizard -NonInteractive -NoUpdateCheck 2>&1 | Out-Null
        } finally {
            $env:USERPROFILE = $savedProfile3
        }
        # Restored from the kit build...
        (Get-Content -LiteralPath $dst -Raw) | Should Not Match 'locally edited rule'
        # ...and the divergent copy was preserved.
        $backupRoot = Join-Path $MockClaude "backups"
        Test-Path $backupRoot | Should Be $true
        $found = @(Get-ChildItem -LiteralPath $backupRoot -Recurse -Filter "commit-convention.md" -File)
        $found.Count | Should BeGreaterThan 0
        (Get-Content -LiteralPath $found[0].FullName -Raw) | Should Match 'locally edited rule'
    }
}

if (Test-Path $MockHome) { Remove-Item -Recurse -Force $MockHome -ErrorAction SilentlyContinue }

Describe "Install-KitRules orphan removal" {
    # Deploy used to be additive only. ADR-0015 deleted
    # project-skill-recommend.md, but the already-deployed copy (3,554 B, no
    # paths, so loaded unconditionally) survived the apply and kept inflating the
    # context the reduction was meant to shrink. Observed on the real machine
    # after the 2026-10-17 apply: 6 rules / 16,961 B where 5 / 13,407 B was
    # expected.
    . (Join-Path $libDir "rules-deploy.ps1")

    function New-RulesFixture {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("orphan-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        return $dir
    }

    It "removes a rule the kit shipped before but no longer builds" {
        $dir = New-RulesFixture
        $rules = Join-Path $dir "rules"
        New-Item -ItemType Directory -Force -Path $rules | Out-Null
        $orphan = Join-Path $rules "gone.md"
        Write-Utf8NoBom -Path $orphan -Content "# stale"
        $kept = Join-Path $rules "kept.md"
        Write-Utf8NoBom -Path $kept -Content "# current"

        Remove-OrphanedKitRules -TargetRulesDir $rules -CurrentApplied @($kept) `
            -PreviousAppliedFiles @("C:\somewhere\.claude\rules\gone.md", "C:\somewhere\.claude\rules\kept.md") `
            -BackupRoot (Join-Path $dir "backups") -BackupStamp "s1"

        Test-Path $orphan | Should Be $false
        Test-Path $kept | Should Be $true
        Remove-Item -Recurse -Force $dir
    }
    It "backs the removed rule up before deleting it" {
        $dir = New-RulesFixture
        $rules = Join-Path $dir "rules"
        New-Item -ItemType Directory -Force -Path $rules | Out-Null
        Write-Utf8NoBom -Path (Join-Path $rules "gone.md") -Content "# stale content"

        Remove-OrphanedKitRules -TargetRulesDir $rules -CurrentApplied @() `
            -PreviousAppliedFiles @("C:\x\.claude\rules\gone.md") `
            -BackupRoot (Join-Path $dir "backups") -BackupStamp "s1"

        $saved = @(Get-ChildItem -LiteralPath (Join-Path $dir "backups") -Recurse -Filter "gone.md" -File)
        $saved.Count | Should BeGreaterThan 0
        (Get-Content -LiteralPath $saved[0].FullName -Raw) | Should Match 'stale content'
        Remove-Item -Recurse -Force $dir
    }
    # A hand-written rule was never in applied_files, so it must survive.
    It "never deletes a rule the kit did not deploy" {
        $dir = New-RulesFixture
        $rules = Join-Path $dir "rules"
        New-Item -ItemType Directory -Force -Path $rules | Out-Null
        $mine = Join-Path $rules "my-own-rule.md"
        Write-Utf8NoBom -Path $mine -Content "# user authored"

        Remove-OrphanedKitRules -TargetRulesDir $rules -CurrentApplied @() `
            -PreviousAppliedFiles @() -BackupRoot (Join-Path $dir "backups") -BackupStamp "s1"

        Test-Path $mine | Should Be $true
        Remove-Item -Recurse -Force $dir
    }
    It "matches on leaf name so a marker from another path still attributes" {
        $dir = New-RulesFixture
        $rules = Join-Path $dir "rules"
        New-Item -ItemType Directory -Force -Path $rules | Out-Null
        $orphan = Join-Path $rules "gone.md"
        Write-Utf8NoBom -Path $orphan -Content "# stale"

        Remove-OrphanedKitRules -TargetRulesDir $rules -CurrentApplied @() `
            -PreviousAppliedFiles @("D:\OTHER\.CLAUDE\RULES\GONE.MD") `
            -BackupRoot (Join-Path $dir "backups") -BackupStamp "s1"

        Test-Path $orphan | Should Be $false
        Remove-Item -Recurse -Force $dir
    }
    It "removes nothing in dry-run mode" {
        $dir = New-RulesFixture
        $rules = Join-Path $dir "rules"
        New-Item -ItemType Directory -Force -Path $rules | Out-Null
        $orphan = Join-Path $rules "gone.md"
        Write-Utf8NoBom -Path $orphan -Content "# stale"

        Remove-OrphanedKitRules -TargetRulesDir $rules -CurrentApplied @() `
            -PreviousAppliedFiles @("C:\x\.claude\rules\gone.md") `
            -BackupRoot (Join-Path $dir "backups") -BackupStamp "s1" -IsDryRun

        Test-Path $orphan | Should Be $true
        Remove-Item -Recurse -Force $dir
    }
    It "tolerates a missing rules directory" {
        $dir = New-RulesFixture
        Remove-OrphanedKitRules -TargetRulesDir (Join-Path $dir "absent") -CurrentApplied @() `
            -PreviousAppliedFiles @("C:\x\.claude\rules\gone.md")
        $true | Should Be $true
        Remove-Item -Recurse -Force $dir
    }
}

Describe "Update-KitRulesBuild" {
    # The build used to run only when a source file was newer than the newest
    # dist file. That heuristic is blind to a rule that STOPPED being built: no
    # surviving source file is touched when one is deleted, or when 'claude' is
    # dropped from its audience in a commit older than the dist copy. dist
    # therefore looked fresh, the build was skipped, and the orphan it still
    # held was deployed again. Observed 2026-10-31: local-llm-fallback.md
    # reached ~/.claude/rules/ despite 'audience: [kit]' (always-loaded surface
    # 9,505 -> 11,073 B). The build is cheap; the heuristic was not sound.
    . (Join-Path $libDir "rules-deploy.ps1")

    function New-KitBuildFixture {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("kitbuild-" + [System.Guid]::NewGuid().ToString("N"))
        $scripts = Join-Path $root "scripts"
        New-Item -ItemType Directory -Force -Path $scripts | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path (Join-Path $root "source") "rules") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path (Join-Path (Join-Path $root "dist") ".claude") "rules") | Out-Null

        # Stand-in for build-rules.ps1: records that it ran and emits one line of
        # each kind the caller filters on.
        $stub = @'
Set-Content -LiteralPath (Join-Path $PSScriptRoot "..\build-ran.txt") -Value "ran" -Encoding ASCII
Write-Host "[build] source/rules/a.md -> dist/.claude/rules/a.md"
Write-Host "[clean] removed stale dist/.claude/rules/gone.md"
'@
        Set-Content -LiteralPath (Join-Path $scripts "build-rules.ps1") -Value $stub -Encoding ASCII
        Write-Utf8NoBom -Path (Join-Path (Join-Path (Join-Path $root "source") "rules") "a.md") -Content "# src"
        return $root
    }

    It "builds even when every dist file is newer than every source file" {
        $root = New-KitBuildFixture
        $orphan = Join-Path (Join-Path (Join-Path (Join-Path $root "dist") ".claude") "rules") "gone.md"
        Write-Utf8NoBom -Path $orphan -Content "# orphan"
        (Get-Item -LiteralPath $orphan).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddDays(1)

        Update-KitRulesBuild -KitRoot $root

        Test-Path (Join-Path $root "build-ran.txt") | Should Be $true
        Remove-Item -Recurse -Force $root
    }

    It "reports the build's stale removal and hides its per-rule build lines" {
        $root = New-KitBuildFixture
        $out = (Update-KitRulesBuild -KitRoot $root 6>&1) -join "`n"

        $out | Should Match "\[clean\] removed stale"
        ($out -match "\[build\]") | Should Be $false
        Remove-Item -Recurse -Force $root
    }

    It "skips the build in dry-run mode" {
        $root = New-KitBuildFixture
        Update-KitRulesBuild -KitRoot $root -IsDryRun
        Test-Path (Join-Path $root "build-ran.txt") | Should Be $false
        Remove-Item -Recurse -Force $root
    }
}
