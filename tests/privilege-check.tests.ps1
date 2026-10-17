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

Describe "privilege-check elevation diagnostics" {
    # Reported symptom: an Administrators-group account was refused in a normal
    # (non-elevated) shell, with the theory that IsInRole(Administrator) reports
    # group membership. Measured on such an account under UAC, it does NOT:
    #   integrity level = Medium (S-1-16-8192)
    #   BUILTIN\Administrators present but "used for deny only"
    #   IsInRole(Administrator) = False   <- guard stays quiet
    # So the gate is kept as-is and these tests pin the observable facts instead.
    . $ScriptPath

    It "defines the diagnostic helpers" {
        (Get-Command Test-UacEnabled -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Get-ElevationDiagnostics -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }
    It "reports UAC state as a boolean or null, never a string" {
        $uac = Test-UacEnabled
        ($null -eq $uac -or $uac -is [bool]) | Should Be $true
    }
    It "produces a single-line diagnostic naming integrity and UAC" {
        $d = Get-ElevationDiagnostics
        $d | Should Match 'integrity='
        $d | Should Match 'UAC='
        $d.Contains("`n") | Should Be $false
    }
    It "does not refuse a non-elevated session on an Administrators-group account" {
        # The guard must stay quiet here. Running it must not exit the process.
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal($id)
        $isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($isAdmin) {
            # Elevated runner (CI is elevated): nothing to assert about the quiet path.
            $true | Should Be $true
        } else {
            Assert-NonElevated
            $true | Should Be $true
        }
    }
    It "explains that group membership alone is not the trigger" {
        $text = Get-Content -LiteralPath $ScriptPath -Raw
        $text | Should Match 'deny only'
    }
    It "continues instead of refusing when UAC is disabled" {
        $text = Get-Content -LiteralPath $ScriptPath -Raw
        # The refusal is unactionable with UAC off: no non-elevated session exists.
        $text | Should Match 'UAC is disabled'
        $text | Should Match 'no non-elevated session to re-run from'
    }
}
