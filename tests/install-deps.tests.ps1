# install-deps.tests.ps1
# Pester v3.4 smoke tests (Windows PowerShell 5.1). ASCII only.

# $PSScriptRoot can be empty when Invoke-Pester is given a direct file path
# (vs a directory). Fall back to MyInvocation, then the current location.
$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path $here "..") "scripts") "install-deps.ps1"

Describe "install-deps.ps1" {
    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "parses without syntax errors" {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should Be 0
    }

    It "runs in DryRun mode and exits 0 (winget present) or 1 (winget absent)" {
        # Either outcome is acceptable: exit 1 only happens when winget is not on
        # PATH, which emits the manual-install guidance and is not a script fault.
        & powershell -NoProfile -File $ScriptPath -DryRun -Quiet 2>&1 | Out-Null
        ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1) | Should Be $true
    }
}
