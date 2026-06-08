# statusline-color.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Verifies the color-coded statusline (ADR-0012): context % maps to ANSI
# color codes (green < 75%, yellow 75-90%, red >= 90%). Both shipped artifacts
# - docs/setup/statusline-powershell.example.json and the wizard template in
# scripts/setup-wizard.ps1 - are checked so they cannot drift apart.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$repoRoot = Split-Path -Parent $here
$exampleJsonPath = Join-Path (Join-Path (Join-Path $repoRoot "docs") "setup") "statusline-powershell.example.json"
$wizardPath = Join-Path (Join-Path $repoRoot "scripts") "setup-wizard.ps1"

# Extract the "if($p -ge 90){'31'}elseif($p -ge 75){'33'}else{'32'}" color
# expression from arbitrary text. Doubled single quotes (PS string-literal form,
# as used inside setup-wizard.ps1) are normalized to single quotes first, so the
# same matcher works against the JSON example and the wizard literal alike.
function Get-ColorExpr {
    param([string]$Text)
    $norm = $Text -replace "''", "'"
    $m = [regex]::Match($norm, "if\(\`$p -ge 90\)\{'31'\}elseif\(\`$p -ge 75\)\{'33'\}else\{'32'\}")
    return $m.Value
}

Describe "statusline color example JSON" {

    It "exists" {
        Test-Path $exampleJsonPath | Should Be $true
    }

    It "is valid JSON with a command statusLine" {
        $json = Get-Content -LiteralPath $exampleJsonPath -Raw | ConvertFrom-Json
        $json.statusLine.type | Should Be 'command'
        $json.statusLine.command | Should Not BeNullOrEmpty
    }

    It "uses [char]27 for the ANSI escape and a [0m reset" {
        $cmd = (Get-Content -LiteralPath $exampleJsonPath -Raw | ConvertFrom-Json).statusLine.command
        $cmd.Contains('[char]27') | Should Be $true
        $cmd.Contains('[0m') | Should Be $true
    }

    It "contains the three threshold color codes" {
        $cmd = (Get-Content -LiteralPath $exampleJsonPath -Raw | ConvertFrom-Json).statusLine.command
        $expr = Get-ColorExpr $cmd
        $expr | Should Not BeNullOrEmpty
    }
}

Describe "statusline color thresholds (shipped example JSON expression)" {

    $cmd = (Get-Content -LiteralPath $exampleJsonPath -Raw | ConvertFrom-Json).statusLine.command
    $expr = Get-ColorExpr $cmd
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

Describe "statusline color thresholds (shipped wizard template)" {

    $raw = Get-Content -LiteralPath $wizardPath -Raw
    $expr = Get-ColorExpr $raw
    $sb = [scriptblock]::Create('param($p) ' + $expr)

    It "wizard ships the same color expression" {
        $expr | Should Not BeNullOrEmpty
    }
    It "wizard 74% -> green (32)" {
        (& $sb 74) | Should Be '32'
    }
    It "wizard 75% -> yellow (33)" {
        (& $sb 75) | Should Be '33'
    }
    It "wizard 90% -> red (31)" {
        (& $sb 90) | Should Be '31'
    }
    It "wizard uses [char]27 for the ANSI escape" {
        $raw.Contains('[char]27') | Should Be $true
    }
}
