# setup-wizard.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# The interactive prompt path (Read-Host) is not exercised here: the wizard is
# verified through its pure helpers (deep merge, settings round-trip) and its
# non-interactive skip guard. See ADR-0010.

# $PSScriptRoot can be empty when Invoke-Pester is given a direct file path
# (vs a directory). Fall back to MyInvocation, then the current location.
$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path $here "..") "scripts") "setup-wizard.ps1"

function New-TempSettingsPath {
    Join-Path $env:TEMP ("eck-wiz-" + [System.IO.Path]::GetRandomFileName() + ".json")
}

Describe "setup-wizard.ps1" {

    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "parses without syntax errors" {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should Be 0
    }

    It "dot-sources and defines the public functions" {
        . $ScriptPath
        (Get-Command Invoke-SettingsSetupWizard -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Merge-Hashtable -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Read-CurrentSettings -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Save-SettingsWithBackup -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }
}

Describe "Merge-Hashtable (deep merge semantics)" {

    It "adds missing top-level keys" {
        . $ScriptPath
        $base = @{ a = 1 }
        $overlay = @{ b = 2 }
        $merged = Merge-Hashtable -Base $base -Overlay $overlay
        $merged['a'] | Should Be 1
        $merged['b'] | Should Be 2
    }

    It "never overwrites an existing scalar key" {
        . $ScriptPath
        $base = @{ a = 'keep' }
        $overlay = @{ a = 'CHANGED' }
        $merged = Merge-Hashtable -Base $base -Overlay $overlay
        $merged['a'] | Should Be 'keep'
    }

    It "merges nested hashtables, adding only missing nested keys" {
        . $ScriptPath
        $base = @{ env = @{ EXISTING = 'orig' } }
        $overlay = @{ env = @{ EXISTING = 'no'; ANTHROPIC_SMALL_FAST_MODEL = 'haiku' } }
        $merged = Merge-Hashtable -Base $base -Overlay $overlay
        $merged['env']['EXISTING'] | Should Be 'orig'
        $merged['env']['ANTHROPIC_SMALL_FAST_MODEL'] | Should Be 'haiku'
    }

    It "does not mutate the original base hashtable" {
        . $ScriptPath
        $base = @{ a = 1 }
        $null = Merge-Hashtable -Base $base -Overlay @{ b = 2 }
        $base.ContainsKey('b') | Should Be $false
    }
}

Describe "ConvertTo-HashtableRecursive" {

    It "converts a nested PSCustomObject into nested hashtables" {
        . $ScriptPath
        $obj = [PSCustomObject]@{ env = [PSCustomObject]@{ KEY = 'val' } }
        $h = ConvertTo-HashtableRecursive $obj
        ($h -is [hashtable]) | Should Be $true
        ($h['env'] -is [hashtable]) | Should Be $true
        $h['env']['KEY'] | Should Be 'val'
    }
}

Describe "Read-CurrentSettings / Save-SettingsWithBackup round-trip" {

    It "returns an empty hashtable when the file is missing" {
        . $ScriptPath
        $p = New-TempSettingsPath
        $result = Read-CurrentSettings -Path $p
        ($result -is [hashtable]) | Should Be $true
        $result.Count | Should Be 0
    }

    It "round-trips a settings hashtable through Save then Read" {
        . $ScriptPath
        $p = New-TempSettingsPath
        try {
            $settings = @{ env = @{ ANTHROPIC_SMALL_FAST_MODEL = 'claude-haiku-4-5-20251001' } }
            Save-SettingsWithBackup -Settings $settings -Path $p
            Test-Path $p | Should Be $true
            $loaded = Read-CurrentSettings -Path $p
            $loaded['env']['ANTHROPIC_SMALL_FAST_MODEL'] | Should Be 'claude-haiku-4-5-20251001'
        } finally {
            Get-ChildItem -LiteralPath (Split-Path -Parent $p) -Filter ((Split-Path -Leaf $p) + "*") -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    It "creates a timestamped backup when overwriting an existing file" {
        . $ScriptPath
        $p = New-TempSettingsPath
        try {
            Save-SettingsWithBackup -Settings @{ a = 1 } -Path $p
            Save-SettingsWithBackup -Settings @{ a = 1; b = 2 } -Path $p
            $backups = Get-ChildItem -LiteralPath (Split-Path -Parent $p) -Filter ((Split-Path -Leaf $p) + ".bak-*") -ErrorAction SilentlyContinue
            @($backups).Count | Should BeGreaterThan 0
        } finally {
            Get-ChildItem -LiteralPath (Split-Path -Parent $p) -Filter ((Split-Path -Leaf $p) + "*") -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    It "writes UTF-8 without a BOM" {
        . $ScriptPath
        $p = New-TempSettingsPath
        try {
            Save-SettingsWithBackup -Settings @{ a = 1 } -Path $p
            $bytes = [System.IO.File]::ReadAllBytes($p)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $hasBom | Should Be $false
        } finally {
            Get-ChildItem -LiteralPath (Split-Path -Parent $p) -Filter ((Split-Path -Leaf $p) + "*") -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Invoke-SettingsSetupWizard non-interactive guard" {

    It "skips and writes nothing when -NonInteractive is passed" {
        . $ScriptPath
        $p = New-TempSettingsPath
        try {
            # No prompt, no file creation: the guard returns before any I/O.
            Invoke-SettingsSetupWizard -NonInteractive -Path $p | Out-Null
            Test-Path $p | Should Be $false
        } finally {
            if (Test-Path $p) { Remove-Item -LiteralPath $p -Force }
        }
    }

    It "does not overwrite an existing configured settings file when skipping" {
        . $ScriptPath
        $p = New-TempSettingsPath
        try {
            Save-SettingsWithBackup -Settings @{ statusLine = @{ type = 'command' }; env = @{ ANTHROPIC_SMALL_FAST_MODEL = 'x' } } -Path $p
            $before = Get-Content -LiteralPath $p -Raw
            Invoke-SettingsSetupWizard -NonInteractive -Path $p | Out-Null
            $after = Get-Content -LiteralPath $p -Raw
            $after | Should Be $before
        } finally {
            Get-ChildItem -LiteralPath (Split-Path -Parent $p) -Filter ((Split-Path -Leaf $p) + "*") -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-IsInteractive" {

    It "returns false under CI" {
        . $ScriptPath
        $orig = $env:CI
        try {
            $env:CI = 'true'
            Test-IsInteractive | Should Be $false
        } finally {
            if ($null -eq $orig) { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { $env:CI = $orig }
        }
    }

    It "returns false when stdin is redirected (background process / slash command)" {
        . $ScriptPath
        # Isolate the IsInputRedirected branch: not CI, has a console, redirected.
        Test-IsInteractive -Ci $false -UserInteractive $true -StdinRedirected $true | Should Be $false
    }

    It "returns false when no interactive console (service / cron)" {
        . $ScriptPath
        Test-IsInteractive -Ci $false -UserInteractive $false -StdinRedirected $false | Should Be $false
    }

    It "returns true only when console present, stdin not redirected, and not CI" {
        . $ScriptPath
        Test-IsInteractive -Ci $false -UserInteractive $true -StdinRedirected $false | Should Be $true
    }
}
