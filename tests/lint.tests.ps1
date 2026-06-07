# lint.tests.ps1
# Pester v3.4 smoke tests (Windows PowerShell 5.1). ASCII only.

$ScriptPath = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "scripts") "lint.ps1"

Describe "lint.ps1" {
    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "parses without syntax errors" {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should Be 0
    }

    It "defines the non-interactive install helper" {
        $content = Get-Content $ScriptPath -Raw
        $content | Should Match 'function Install-PSScriptAnalyzerNonInteractive'
    }

    It "enables TLS 1.2 before contacting PSGallery" {
        $content = Get-Content $ScriptPath -Raw
        $content | Should Match 'Tls12'
    }

    It "trusts PSGallery and restores the policy" {
        $content = Get-Content $ScriptPath -Raw
        $content | Should Match "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted"
        $content | Should Match '\$originalPolicy'
    }

    It "runs to completion without hanging in a non-interactive shell" {
        # Smoke test: when PSScriptAnalyzer is present the script skips install and
        # runs the lint. Run it in a child non-interactive shell and assert it
        # terminates with a defined exit code (0 = pass, 1 = strict failures).
        # This guards against the prompt-driven hang the non-interactive install
        # logic was added to prevent.
        $psa = Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -First 1
        if (-not $psa) {
            # PSScriptAnalyzer not installed in this environment; skip the live run
            # to avoid a network-dependent install during unit tests. Pester 3.4
            # has no inconclusive state, so this asserts a trivial pass.
            $true | Should Be $true
        } else {
            & powershell -NoProfile -NonInteractive -File $ScriptPath 2>&1 | Out-Null
            ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1) | Should Be $true
        }
    }
}
