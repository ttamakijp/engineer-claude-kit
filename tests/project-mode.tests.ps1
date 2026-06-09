# project-mode.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1). ASCII only.
#
# Hardens the Project-mode distribution path of apply-claude-kit.ps1. The
# existing apply-claude-kit.tests.ps1 verifies only existence (Test-Path) of the
# leak-protection artifacts; this suite additionally asserts that the bytes
# actually written match the template source (Get-FileHash equality) for the
# files copied verbatim: git hooks (pre-commit / pre-push), .gitleaks.toml and
# .mailmap. That catches silent corruption (encoding, truncation, wrong source)
# that a Test-Path-only check would miss.
#
# This file is independent of apply-claude-kit.tests.ps1: it uses its own temp
# project directory so the two suites never collide.
#
# Script invocations pass -AllowElevated because CI runners (e.g. GitHub
# windows-latest) run elevated and the ADR-0008 fail-fast guard would otherwise
# exit 2 before the script body runs.

# $PSScriptRoot can be empty when Invoke-Pester is given a direct file path
# (vs a directory). Fall back to MyInvocation, then the current location.
$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path $here "..") "scripts") "apply-claude-kit.ps1"
$KitRoot = (Resolve-Path (Join-Path $here "..")).Path
$TemplatesRoot = Join-Path $KitRoot "templates"
$MockProject = Join-Path $env:TEMP "eck-test-projmode"

if (Test-Path $MockProject) { Remove-Item -Recurse -Force $MockProject }
New-Item -ItemType Directory -Force -Path $MockProject | Out-Null
# Hooks distribute into <project>/.git/hooks, so the mock project must be a real
# git repo for the hook-distribution path to run.
& git init -q $MockProject 2>&1 | Out-Null

# Apply once; every assertion below inspects the result of this single run.
& powershell -NoProfile -File $ScriptPath -AllowElevated -Project $MockProject 2>&1 | Out-Null

# Compare the SHA-256 of two files. Returns $true only when both exist and their
# hashes are identical. Used for the verbatim-copy assertions.
function Test-FileHashMatch {
    param([string]$Expected, [string]$Actual)
    if (-not (Test-Path $Expected)) { return $false }
    if (-not (Test-Path $Actual)) { return $false }
    $e = (Get-FileHash -LiteralPath $Expected -Algorithm SHA256).Hash
    $a = (Get-FileHash -LiteralPath $Actual -Algorithm SHA256).Hash
    return ($e -eq $a)
}

Describe "apply-claude-kit.ps1 Project-mode distribution" {

    It "creates the project as a real git repo (hook path precondition)" {
        Test-Path (Join-Path $MockProject ".git") | Should Be $true
    }

    Context "git hooks" {
        $hooksDest = Join-Path (Join-Path $MockProject ".git") "hooks"
        $hooksSrc = Join-Path $TemplatesRoot "git-hooks"

        It "deploys pre-commit hook" {
            Test-Path (Join-Path $hooksDest "pre-commit") | Should Be $true
        }

        It "pre-commit content matches the template byte-for-byte" {
            $src = Join-Path $hooksSrc "pre-commit"
            $dest = Join-Path $hooksDest "pre-commit"
            Test-FileHashMatch -Expected $src -Actual $dest | Should Be $true
        }

        It "deploys pre-push hook" {
            Test-Path (Join-Path $hooksDest "pre-push") | Should Be $true
        }

        It "pre-push content matches the template byte-for-byte" {
            $src = Join-Path $hooksSrc "pre-push"
            $dest = Join-Path $hooksDest "pre-push"
            Test-FileHashMatch -Expected $src -Actual $dest | Should Be $true
        }
    }

    Context "root leak-protection config" {
        It "deploys .gitleaks.toml" {
            Test-Path (Join-Path $MockProject ".gitleaks.toml") | Should Be $true
        }

        It ".gitleaks.toml content matches the template byte-for-byte" {
            $src = Join-Path $TemplatesRoot ".gitleaks.toml"
            $dest = Join-Path $MockProject ".gitleaks.toml"
            Test-FileHashMatch -Expected $src -Actual $dest | Should Be $true
        }

        It "deploys .mailmap" {
            Test-Path (Join-Path $MockProject ".mailmap") | Should Be $true
        }

        It ".mailmap content matches the template byte-for-byte" {
            $src = Join-Path $TemplatesRoot ".mailmap"
            $dest = Join-Path $MockProject ".mailmap"
            Test-FileHashMatch -Expected $src -Actual $dest | Should Be $true
        }
    }

    Context "project CLAUDE.md" {
        # CLAUDE.md is rendered through Copy-Template (placeholder substitution),
        # so its bytes intentionally differ from the template. Assert presence
        # and that no unresolved {{role:...}} placeholder leaked through.
        It "deploys CLAUDE.md to the project root" {
            Test-Path (Join-Path $MockProject "CLAUDE.md") | Should Be $true
        }

        It "leaves no unresolved role placeholder" {
            $content = Get-Content -LiteralPath (Join-Path $MockProject "CLAUDE.md") -Raw
            $content | Should Not Match '\{\{role:'
        }
    }

    It "records the deployed leak-protection files in the applied marker" {
        $marker = Join-Path $MockProject ".engineer-claude-kit-applied"
        Test-Path $marker | Should Be $true
        $content = Get-Content -LiteralPath $marker -Raw
        $content | Should Match 'pre-commit'
        $content | Should Match 'gitleaks'
        $content | Should Match 'mailmap'
    }
}

if (Test-Path $MockProject) { Remove-Item -Recurse -Force $MockProject }
