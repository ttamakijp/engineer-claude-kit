# encoding-helper.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# These tests must stay ASCII-only (ADR-0003 section C), so the multibyte
# sample text is built from Unicode code points at runtime rather than written
# as literal Japanese characters in the source.

# $PSScriptRoot can be empty when Invoke-Pester is given a direct file path
# (vs a directory). Fall back to MyInvocation, then the current location.
$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path (Join-Path $here "..") "scripts") "lib") "encoding-helper.ps1"

# Sample multibyte text: U+65E5 U+672C U+8A9E ("Nihongo") + ASCII, built from
# code points to keep this source file ASCII-only.
$Sample = ([char]0x65E5).ToString() + ([char]0x672C) + ([char]0x8A9E) + " test 123"

function New-TempPath {
    Join-Path $env:TEMP ("eck-enc-" + [System.IO.Path]::GetRandomFileName())
}

Describe "encoding-helper.ps1" {

    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "parses without syntax errors" {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should Be 0
    }

    It "dot-sources successfully and defines both functions" {
        . $ScriptPath
        (Get-Command Write-Utf8NoBom -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Read-Utf8NoBom  -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }

    It "writes UTF-8 WITHOUT a BOM (first 3 bytes are not EF BB BF)" {
        . $ScriptPath
        $p = New-TempPath
        try {
            Write-Utf8NoBom -Path $p -Content $Sample
            $bytes = [System.IO.File]::ReadAllBytes($p)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $hasBom | Should Be $false
        } finally {
            if (Test-Path $p) { Remove-Item -LiteralPath $p -Force }
        }
    }

    It "writes bytes that decode back as the original UTF-8 text" {
        . $ScriptPath
        $p = New-TempPath
        try {
            Write-Utf8NoBom -Path $p -Content $Sample
            $bytes = [System.IO.File]::ReadAllBytes($p)
            $decoded = (New-Object System.Text.UTF8Encoding($false)).GetString($bytes)
            $decoded | Should Be $Sample
        } finally {
            if (Test-Path $p) { Remove-Item -LiteralPath $p -Force }
        }
    }

    It "round-trips multibyte text through Write then Read" {
        . $ScriptPath
        $p = New-TempPath
        try {
            Write-Utf8NoBom -Path $p -Content $Sample
            $read = Read-Utf8NoBom -Path $p
            $read | Should Be $Sample
        } finally {
            if (Test-Path $p) { Remove-Item -LiteralPath $p -Force }
        }
    }

    It "strips a leading BOM when reading a BOM-prefixed UTF-8 file" {
        . $ScriptPath
        $p = New-TempPath
        try {
            # Build a file that starts with a UTF-8 BOM (EF BB BF) followed by
            # the UTF-8 encoding of the sample text.
            $enc = New-Object System.Text.UTF8Encoding($false)
            $bom = [byte[]](0xEF, 0xBB, 0xBF)
            $body = $enc.GetBytes($Sample)
            $all = New-Object byte[] ($bom.Length + $body.Length)
            [System.Array]::Copy($bom, 0, $all, 0, $bom.Length)
            [System.Array]::Copy($body, 0, $all, $bom.Length, $body.Length)
            [System.IO.File]::WriteAllBytes($p, $all)

            $read = Read-Utf8NoBom -Path $p
            # No leading U+FEFF, and content matches the original.
            ($read[0] -eq [char]0xFEFF) | Should Be $false
            $read | Should Be $Sample
        } finally {
            if (Test-Path $p) { Remove-Item -LiteralPath $p -Force }
        }
    }
}
