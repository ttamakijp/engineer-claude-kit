# models-config.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
# Covers the config loader + model-role resolution extracted from
# apply-claude-kit.ps1 into scripts/lib/models-config.ps1 (G1 refactor).

# $PSScriptRoot can be empty when Invoke-Pester is given a direct file path
# (vs a directory). Fall back to MyInvocation, then the current location.
$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$LibDir = Join-Path (Join-Path (Join-Path $here "..") "scripts") "lib"
$ScriptPath = Join-Path $LibDir "models-config.ps1"
$EncodingHelper = Join-Path $LibDir "encoding-helper.ps1"

function New-TempPath {
    Join-Path $env:TEMP ("eck-models-" + [System.IO.Path]::GetRandomFileName())
}

Describe "models-config.ps1" {

    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "parses without syntax errors" {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should Be 0
    }

    It "dot-sources successfully and defines all three functions" {
        . $EncodingHelper
        . $ScriptPath
        (Get-Command Read-ConfigYaml            -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Resolve-ModelId            -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Invoke-TemplateSubstitution -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }

    It "parses a nested map and an inline list" {
        . $EncodingHelper
        . $ScriptPath
        $p = New-TempPath
        try {
            $yaml = "models:`n  main:`n    id: claude-test-main`ntags: [a, b, c]"
            Write-Utf8NoBom -Path $p -Content $yaml
            $cfg = Read-ConfigYaml -Path $p
            $cfg['models']['main']['id'] | Should Be 'claude-test-main'
            ($cfg['tags'] -join ',') | Should Be 'a,b,c'
        } finally {
            if (Test-Path $p) { Remove-Item -LiteralPath $p -Force }
        }
    }

    It "resolves a direct model id" {
        . $EncodingHelper
        . $ScriptPath
        $cfg = @{ models = @{ main = @{ id = 'claude-direct' } } }
        Resolve-ModelId -ModelsConfig $cfg -Role 'main' | Should Be 'claude-direct'
    }

    It "resolves a role alias via role-of" {
        . $EncodingHelper
        . $ScriptPath
        $cfg = @{
            models = @{ main = @{ id = 'claude-target' } }
            roles  = @{ 'small-fast' = @{ 'role-of' = 'main' } }
        }
        Resolve-ModelId -ModelsConfig $cfg -Role 'small-fast' | Should Be 'claude-target'
    }

    It "throws when a role cannot be resolved" {
        # Manual try/catch instead of `Should Throw`: the CI runner ships Pester 5
        # preinstalled, which can shadow the pinned v3 such that the legacy
        # `Should Throw` no longer catches. A boolean flag is version-agnostic.
        . $EncodingHelper
        . $ScriptPath
        $cfg = @{ models = @{ main = @{ id = 'x' } } }
        $threw = $false
        try { Resolve-ModelId -ModelsConfig $cfg -Role 'nope' } catch { $threw = $true }
        $threw | Should Be $true
    }

    It "substitutes {{role:<name>}} placeholders and leaves others untouched" {
        . $EncodingHelper
        . $ScriptPath
        $cfg = @{ models = @{ main = @{ id = 'claude-sub' } } }
        $text = "model is {{role:main}} but {{user.name}} stays"
        $out = Invoke-TemplateSubstitution -TemplateContent $text -ModelsConfig $cfg
        $out | Should Match 'claude-sub'
        $out | Should Not Match '\{\{role:'
        $out | Should Match '\{\{user.name\}\}'
    }
}
