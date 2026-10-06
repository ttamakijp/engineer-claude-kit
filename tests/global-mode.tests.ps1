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
