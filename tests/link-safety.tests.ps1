# link-safety.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Covers lib/link-safety.ps1 (ADR-0015 step 3). Creating a real symbolic link
# needs either Developer Mode or elevation, neither of which a test run can
# assume, so Get-LinkState takes an -ItemInfo injection point: the reparse-point
# branch is driven with a stub exposing the same .Attributes / .Target / .LinkType
# surface Get-Item returns. The backup and unlink paths work on ordinary files
# and are exercised for real.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$libDir = Join-Path (Join-Path (Join-Path $here "..") "scripts") "lib"
. (Join-Path $libDir "encoding-helper.ps1")
. (Join-Path $libDir "link-safety.ps1")

function New-TempDir2 {
    $d = Join-Path ([System.IO.Path]::GetTempPath()) ("ls-test-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return $d
}

Describe "Get-LinkState" {
    It "reports a missing path as non-existent" {
        $state = Get-LinkState -Path (Join-Path $env:TEMP "no-such-file-xyz.md")
        $state.Exists | Should Be $false
        $state.IsLink | Should Be $false
    }
    It "reports a regular file as existing and not a link" {
        $dir = New-TempDir2
        $f = Join-Path $dir "plain.md"
        Write-Utf8NoBom -Path $f -Content "hello"
        $state = Get-LinkState -Path $f
        $state.Exists | Should Be $true
        $state.IsLink | Should Be $false
        Remove-Item -Recurse -Force $dir
    }
    It "detects a reparse point from the attribute" {
        $stub = [PSCustomObject]@{
            Attributes = ([System.IO.FileAttributes]::Archive -bor [System.IO.FileAttributes]::ReparsePoint)
            Target     = 'C:\elsewhere\CLAUDE.user.md'
            LinkType   = 'SymbolicLink'
        }
        $state = Get-LinkState -Path 'C:\irrelevant' -ItemInfo $stub
        $state.IsLink | Should Be $true
        $state.Target | Should Be 'C:\elsewhere\CLAUDE.user.md'
        $state.LinkType | Should Be 'SymbolicLink'
    }
    It "treats a plain-attribute item as not a link" {
        $stub = [PSCustomObject]@{ Attributes = [System.IO.FileAttributes]::Archive }
        (Get-LinkState -Path 'C:\irrelevant' -ItemInfo $stub).IsLink | Should Be $false
    }
    It "still classifies when the host exposes no Target" {
        $stub = [PSCustomObject]@{
            Attributes = ([System.IO.FileAttributes]::Archive -bor [System.IO.FileAttributes]::ReparsePoint)
        }
        $state = Get-LinkState -Path 'C:\irrelevant' -ItemInfo $stub
        $state.IsLink | Should Be $true
        $state.Target | Should BeNullOrEmpty
    }
}

Describe "New-KitBackup" {
    It "returns null when there is nothing to back up" {
        $dir = New-TempDir2
        (New-KitBackup -Path (Join-Path $dir "absent.md") -BackupRoot $dir) | Should BeNullOrEmpty
        Remove-Item -Recurse -Force $dir
    }
    It "copies the content and writes a restore manifest" {
        $dir = New-TempDir2
        $src = Join-Path $dir "CLAUDE.md"
        Write-Utf8NoBom -Path $src -Content "original content"
        $backupRoot = Join-Path $dir "backups"

        $dest = New-KitBackup -Path $src -BackupRoot $backupRoot -Stamp "20261006-120000" -Note "test"
        Test-Path $dest | Should Be $true
        (Get-Content -LiteralPath $dest -Raw) | Should Match 'original content'

        $manifest = Join-Path (Join-Path $backupRoot "20261006-120000") "restore-manifest.json"
        Test-Path $manifest | Should Be $true
        $entries = @((Get-Content -LiteralPath $manifest -Raw -Encoding UTF8) | ConvertFrom-Json)
        $entries[0].OriginalPath | Should Be $src
        $entries[0].Note | Should Be 'test'
        Remove-Item -Recurse -Force $dir
    }
    It "appends a second entry to the same run manifest" {
        $dir = New-TempDir2
        $a = Join-Path $dir "a.md"; Write-Utf8NoBom -Path $a -Content "a"
        $b = Join-Path $dir "b.md"; Write-Utf8NoBom -Path $b -Content "b"
        $backupRoot = Join-Path $dir "backups"
        $null = New-KitBackup -Path $a -BackupRoot $backupRoot -Stamp "s1"
        $null = New-KitBackup -Path $b -BackupRoot $backupRoot -Stamp "s1"
        $manifest = Join-Path (Join-Path $backupRoot "s1") "restore-manifest.json"
        # PS 5.1 returns a bare object for a one-element array, so enumerate.
        $entries = @()
        ((Get-Content -LiteralPath $manifest -Raw -Encoding UTF8) | ConvertFrom-Json) | ForEach-Object { $entries += $_ }
        $entries.Count | Should Be 2
        Remove-Item -Recurse -Force $dir
    }
    It "does not clobber an earlier backup that shares a leaf name" {
        $dir = New-TempDir2
        $sub1 = Join-Path $dir "p1"; New-Item -ItemType Directory -Force -Path $sub1 | Out-Null
        $sub2 = Join-Path $dir "p2"; New-Item -ItemType Directory -Force -Path $sub2 | Out-Null
        $f1 = Join-Path $sub1 "same.md"; Write-Utf8NoBom -Path $f1 -Content "first"
        $f2 = Join-Path $sub2 "same.md"; Write-Utf8NoBom -Path $f2 -Content "second"
        $backupRoot = Join-Path $dir "backups"
        $d1 = New-KitBackup -Path $f1 -BackupRoot $backupRoot -Stamp "s1"
        $d2 = New-KitBackup -Path $f2 -BackupRoot $backupRoot -Stamp "s1"
        $d1 | Should Not Be $d2
        (Get-Content -LiteralPath $d1 -Raw) | Should Match 'first'
        (Get-Content -LiteralPath $d2 -Raw) | Should Match 'second'
        Remove-Item -Recurse -Force $dir
    }
    It "writes nothing in dry-run mode" {
        $dir = New-TempDir2
        $src = Join-Path $dir "CLAUDE.md"
        Write-Utf8NoBom -Path $src -Content "x"
        $backupRoot = Join-Path $dir "backups"
        $null = New-KitBackup -Path $src -BackupRoot $backupRoot -Stamp "s1" -IsDryRun
        Test-Path $backupRoot | Should Be $false
        Remove-Item -Recurse -Force $dir
    }
}

Describe "Remove-LinkOnly" {
    It "returns false for a missing path" {
        (Remove-LinkOnly -Path (Join-Path $env:TEMP "no-such-link-xyz")) | Should Be $false
    }
    It "removes a regular file" {
        $dir = New-TempDir2
        $f = Join-Path $dir "gone.md"
        Write-Utf8NoBom -Path $f -Content "x"
        (Remove-LinkOnly -Path $f) | Should Be $true
        Test-Path $f | Should Be $false
        Remove-Item -Recurse -Force $dir
    }
    It "removes nothing in dry-run mode" {
        $dir = New-TempDir2
        $f = Join-Path $dir "stay.md"
        Write-Utf8NoBom -Path $f -Content "x"
        (Remove-LinkOnly -Path $f -IsDryRun) | Should Be $true
        Test-Path $f | Should Be $true
        Remove-Item -Recurse -Force $dir
    }
}
