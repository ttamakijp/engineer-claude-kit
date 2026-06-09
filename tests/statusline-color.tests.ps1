# statusline-color.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Verifies the color-coded statusline (ADR-0012): context % maps to ANSI color
# codes (green < 75%, yellow 75-90%, red >= 90%).
#
# As of the 2026-06-09 amendment the color logic lives in the shipped script
# templates/statusline.ps1 (deployed via -File), not in an inline -Command. The
# wizard and the example JSON now only reference that script by path; these tests
# check all three artifacts so they cannot drift apart.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$repoRoot = Split-Path -Parent $here
$exampleJsonPath = Join-Path (Join-Path (Join-Path $repoRoot "docs") "setup") "statusline-powershell.example.json"
$wizardPath = Join-Path (Join-Path $repoRoot "scripts") "setup-wizard.ps1"
$scriptPath = Join-Path (Join-Path $repoRoot "templates") "statusline.ps1"

# Extract the "if ($p -ge 90) { '31' } elseif ($p -ge 75) { '33' } else { '32' }"
# color expression from the script. Whitespace runs are normalized to single
# spaces first so the matcher is tolerant of formatting.
function Get-ColorExpr {
    param([string]$Text)
    $norm = ($Text -replace "\s+", " ")
    $m = [regex]::Match($norm, "if \(\`$p -ge 90\) \{ '31' \} elseif \(\`$p -ge 75\) \{ '33' \} else \{ '32' \}")
    return $m.Value
}

Describe "statusline.ps1 shipped script" {

    It "exists" {
        Test-Path $scriptPath | Should Be $true
    }

    It "parses without syntax errors" {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should Be 0
    }

    It "uses [char]27 for the ANSI escape and a [0m reset" {
        $raw = Get-Content -LiteralPath $scriptPath -Raw
        $raw.Contains('[char]27') | Should Be $true
        $raw.Contains('[0m') | Should Be $true
    }

    It "is ASCII only" {
        $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
        ($bytes | Where-Object { $_ -gt 127 }).Count | Should Be 0
    }

    It "contains the three threshold color codes" {
        $raw = Get-Content -LiteralPath $scriptPath -Raw
        (Get-ColorExpr $raw) | Should Not BeNullOrEmpty
    }
}

Describe "statusline color thresholds (shipped statusline.ps1 expression)" {

    $raw = Get-Content -LiteralPath $scriptPath -Raw
    $expr = Get-ColorExpr $raw
    $sb = [scriptblock]::Create('param($p) ' + $expr)

    It "74% -> green (32)" {
        (& $sb 74) | Should Be '32'
    }
    It "75% -> yellow (33)" {
        (& $sb 75) | Should Be '33'
    }
    It "89% -> yellow (33)" {
        (& $sb 89) | Should Be '33'
    }
    It "90% -> red (31)" {
        (& $sb 90) | Should Be '31'
    }
    It "0% -> green (32)" {
        (& $sb 0) | Should Be '32'
    }
    It "100% -> red (31)" {
        (& $sb 100) | Should Be '31'
    }
}

Describe "statusline command artifacts use -File (not inline -Command)" {

    It "example JSON is valid with a command statusLine" {
        $json = Get-Content -LiteralPath $exampleJsonPath -Raw | ConvertFrom-Json
        $json.statusLine.type | Should Be 'command'
        $json.statusLine.command | Should Not BeNullOrEmpty
    }

    It "example JSON references statusline.ps1 via -File" {
        $cmd = (Get-Content -LiteralPath $exampleJsonPath -Raw | ConvertFrom-Json).statusLine.command
        $cmd.Contains('-File') | Should Be $true
        $cmd.Contains('statusline.ps1') | Should Be $true
    }

    It "wizard ships a -File command referencing statusline.ps1" {
        $raw = Get-Content -LiteralPath $wizardPath -Raw
        $raw.Contains('-NoProfile -File') | Should Be $true
        $raw.Contains('statusline.ps1') | Should Be $true
    }

    It "wizard no longer embeds the inline color -Command" {
        $raw = Get-Content -LiteralPath $wizardPath -Raw
        # The fragile inline form carried the used_percentage parse inside -Command.
        $raw.Contains('ConvertFrom-Json | ForEach-Object') | Should Be $false
    }
}
