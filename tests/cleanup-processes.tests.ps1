# cleanup-processes.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# The real Get-Process / Get-CimInstance / Stop-Process paths are never exercised
# here: Get-OrphanedProcesses is driven through its injection points
# (-InputProcesses / -Now / -ParentPathResolver) so the filter logic is
# deterministic, and the kill path is checked with a mocked Stop-Process so no
# real process is ever terminated. See ADR-0011.
#
# The script is dot-sourced ONCE at file scope (not inside each It). Re-sourcing
# it inside an It re-defines the functions and silently defeats Pester 3.4 Mocks
# of those functions, so it is done a single time here.

# $PSScriptRoot can be empty when Invoke-Pester is given a direct file path
# (vs a directory). Fall back to MyInvocation, then the current location.
$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path (Join-Path $here "..") "scripts") "lib") "cleanup-processes.ps1"

# Dot-sourcing only loads the functions; the direct-invocation guard in the
# script sees InvocationName '.' and runs no cleanup.
. $ScriptPath

# Build a fake process object with the properties Get-OrphanedProcesses reads.
# StartTimeMinutesAgo: how long ago the process started (older = more orphan-like).
function New-FakeProcess {
    param(
        [int]$Id,
        [string]$Name = 'bash',
        [string]$MainWindowTitle = '',
        [double]$StartTimeMinutesAgo = 30,
        [double]$Cpu = 0.0,
        [datetime]$Now
    )
    return [PSCustomObject]@{
        Id              = $Id
        ProcessName     = $Name
        MainWindowTitle = $MainWindowTitle
        StartTime       = $Now.AddMinutes(-$StartTimeMinutesAgo)
        CPU             = $Cpu
    }
}

# A parent-path resolver that always reports a non-IDE parent (a plain shell).
$NonIdeResolver = { param($id) "C:\Windows\System32\cmd.exe" }
# A parent-path resolver that always reports VS Code as the parent.
$VsCodeResolver = { param($id) "C:\Users\me\AppData\Local\Programs\Microsoft VS Code\Code.exe" }

Describe "cleanup-processes.ps1" {

    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "parses without syntax errors" {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should Be 0
    }

    It "defines the public functions (dot-sourcing runs no cleanup)" {
        (Get-Command Get-OrphanedProcesses -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Invoke-ProcessCleanup -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Get-ParentProcessPath -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }
}

Describe "Get-OrphanedProcesses filter logic" {

    It "keeps an idle, old, windowless, non-IDE-parented process" {
        $now = Get-Date
        $procs = @(New-FakeProcess -Id 100 -StartTimeMinutesAgo 30 -Cpu 0.1 -Now $now)
        $orphans = @(Get-OrphanedProcesses -InputProcesses $procs -Now $now -ParentPathResolver $NonIdeResolver)
        $orphans.Count | Should Be 1
        $orphans[0].Id | Should Be 100
    }

    It "excludes a process that started within the idle window" {
        $now = Get-Date
        # Started 2 minutes ago; default IdleMinutes is 10 -> too young to kill.
        $procs = @(New-FakeProcess -Id 101 -StartTimeMinutesAgo 2 -Cpu 0.1 -Now $now)
        $orphans = @(Get-OrphanedProcesses -InputProcesses $procs -Now $now -ParentPathResolver $NonIdeResolver)
        $orphans.Count | Should Be 0
    }

    It "excludes a busy (high-CPU) process" {
        $now = Get-Date
        # 42 CPU seconds; default MaxCpuSeconds is 5 -> active worker, keep alive.
        $procs = @(New-FakeProcess -Id 102 -StartTimeMinutesAgo 30 -Cpu 42.0 -Now $now)
        $orphans = @(Get-OrphanedProcesses -InputProcesses $procs -Now $now -ParentPathResolver $NonIdeResolver)
        $orphans.Count | Should Be 0
    }

    It "excludes a process that owns a GUI window" {
        $now = Get-Date
        $procs = @(New-FakeProcess -Id 103 -MainWindowTitle 'My Terminal' -StartTimeMinutesAgo 30 -Cpu 0.1 -Now $now)
        $orphans = @(Get-OrphanedProcesses -InputProcesses $procs -Now $now -ParentPathResolver $NonIdeResolver)
        $orphans.Count | Should Be 0
    }

    It "excludes a process whose parent is VS Code" {
        $now = Get-Date
        $procs = @(New-FakeProcess -Id 104 -StartTimeMinutesAgo 30 -Cpu 0.1 -Now $now)
        $orphans = @(Get-OrphanedProcesses -InputProcesses $procs -Now $now -ParentPathResolver $VsCodeResolver)
        $orphans.Count | Should Be 0
    }

    It "returns only the orphans from a mixed candidate list" {
        $now = Get-Date
        $procs = @(
            (New-FakeProcess -Id 200 -StartTimeMinutesAgo 30 -Cpu 0.1 -Now $now)             # orphan
            (New-FakeProcess -Id 201 -StartTimeMinutesAgo 1  -Cpu 0.1 -Now $now)             # too young
            (New-FakeProcess -Id 202 -StartTimeMinutesAgo 30 -Cpu 99.0 -Now $now)            # busy
            (New-FakeProcess -Id 203 -MainWindowTitle 'x' -StartTimeMinutesAgo 30 -Now $now)  # has window
            (New-FakeProcess -Id 204 -StartTimeMinutesAgo 30 -Cpu 0.1 -Now $now)             # orphan
        )
        $orphans = @(Get-OrphanedProcesses -InputProcesses $procs -Now $now -ParentPathResolver $NonIdeResolver)
        $orphans.Count | Should Be 2
        ($orphans | ForEach-Object { $_.Id }) -join ',' | Should Be '200,204'
    }

    It "returns an empty array (not null) when there are no candidates" {
        $now = Get-Date
        $orphans = @(Get-OrphanedProcesses -InputProcesses @() -Now $now -ParentPathResolver $NonIdeResolver)
        $orphans.Count | Should Be 0
    }
}

Describe "Invoke-ProcessCleanup kill path" {

    It "does not call Stop-Process when -DryRun is passed" {
        # Force a non-empty orphan list and intercept the kill call.
        Mock Get-OrphanedProcesses { @([PSCustomObject]@{ Id = 999; ProcessName = 'bash'; StartTime = (Get-Date).AddMinutes(-30); CPU = 0.1 }) }
        Mock Stop-Process { }
        Invoke-ProcessCleanup -DryRun | Out-Null
        Assert-MockCalled Stop-Process -Times 0 -Scope It
    }

    It "calls Stop-Process when not in DryRun and orphans exist" {
        Mock Get-OrphanedProcesses { @([PSCustomObject]@{ Id = 999; ProcessName = 'bash'; StartTime = (Get-Date).AddMinutes(-30); CPU = 0.1 }) }
        Mock Stop-Process { }
        Invoke-ProcessCleanup | Out-Null
        Assert-MockCalled Stop-Process -Times 1 -Scope It
    }

    It "does not call Stop-Process when no orphans are found" {
        Mock Get-OrphanedProcesses { @() }
        Mock Stop-Process { }
        Invoke-ProcessCleanup | Out-Null
        Assert-MockCalled Stop-Process -Times 0 -Scope It
    }
}
