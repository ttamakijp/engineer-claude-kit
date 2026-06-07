# privilege-check.tests.ps1
# Pester v3.4 smoke tests (Windows PowerShell 5.1). ASCII only.
#
# Note: we deliberately do NOT call Assert-NonElevated without -AllowElevated
# here. CI runners run elevated, so the bare call would hit the fail-fast path
# and exit 2, killing the Pester run. The -AllowElevated path only warns and
# returns, so it is safe regardless of the runner's elevation state.

# $PSScriptRoot can be empty when Invoke-Pester is given a direct file path
# (vs a directory). Fall back to MyInvocation, then the current location.
$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path (Join-Path $here "..") "scripts") "lib") "privilege-check.ps1"

Describe "privilege-check.ps1" {
    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "parses without syntax errors" {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should Be 0
    }

    It "dot-sources successfully and defines Assert-NonElevated" {
        . $ScriptPath
        (Get-Command Assert-NonElevated -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }

    It "exposes an -AllowElevated switch parameter" {
        . $ScriptPath
        $cmd = Get-Command Assert-NonElevated
        $cmd.Parameters.ContainsKey('AllowElevated') | Should Be $true
        $cmd.Parameters['AllowElevated'].ParameterType | Should Be ([switch])
    }

    It "returns without exiting when -AllowElevated is passed" {
        # Safe on both elevated and non-elevated hosts:
        #   - elevated  -> warns and returns
        #   - normal    -> returns immediately
        # Neither path calls exit, so reaching the assertion proves no abort.
        . $ScriptPath
        Assert-NonElevated -AllowElevated -WarningAction SilentlyContinue
        $true | Should Be $true
    }
}
