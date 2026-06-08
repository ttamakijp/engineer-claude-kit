#requires -Version 5.1
# cleanup-processes.ps1
# Shared helper: Invoke-ProcessCleanup -- kill orphaned bash / gh / git
# subprocesses left behind by parallel Claude Code child sessions.
#
# Why this exists (see ADR-0011):
#   - Running Claude Code in many parallel child sessions spawns bash / gh / git
#     subprocesses. Watch-style commands (e.g. `gh pr checks --watch`) routinely
#     outlive their session and linger as orphaned background processes, piling
#     up in Task Manager.
#   - This helper finds and kills only processes that pass a conservative safety
#     filter, so active workers and IDE-owned shells are never touched.
#
# Safety filter -- a process is killed ONLY when ALL of these hold:
#   - started at least -IdleMinutes minutes ago (default 10)
#   - has used less than -MaxCpuSeconds CPU seconds (default 5; i.e. idle)
#   - has an empty MainWindowTitle (no GUI window -> background process)
#   - its parent process is NOT an IDE (VS Code / Cursor / Sublime / Atom / JetBrains)
#
# PowerShell hosts (pwsh / powershell) are intentionally NOT in the default
# target list: the kit's own cleanup runner is a PowerShell process, and killing
# it would be self-destructive. See ADR-0011.
#
# Usage (direct / scheduled):
#   pwsh scripts/lib/cleanup-processes.ps1            # apply (kill)
#   pwsh scripts/lib/cleanup-processes.ps1 -DryRun    # preview only
# Dot-sourcing (tests / callers) only loads the functions; no cleanup runs.
#
# ASCII only (no Japanese in code, comments, or strings). See ADR-0003 section C.
# PS 5.1 compatible: no PS 6+ syntax, no PS 6+ cmdlets.

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string[]]$Names = @('bash', 'gh', 'git'),
    [int]$IdleMinutes = 10,
    [double]$MaxCpuSeconds = 5.0
)

function Get-ParentProcessPath {
    # Resolve the executable path of the parent of -ProcessId, or $null when it
    # cannot be determined. Uses CIM (available since PS 3.0 / PS 5.1).
    # NOTE: the parameter is -ProcessId, NOT -Pid: $Pid is a PowerShell automatic
    # variable (the current process id) and binding a parameter to it is unsafe.
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][int]$ProcessId)

    try {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
        if (-not $proc) { return $null }
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.ParentProcessId)" -ErrorAction SilentlyContinue
        if (-not $parent) { return $null }
        return $parent.ExecutablePath
    } catch {
        return $null
    }
}

function Get-OrphanedProcesses {
    # Return the subset of candidate processes that are safe to kill per the
    # filter documented at the top of this file.
    #
    # Testability injection points (production callers leave these unset):
    #   -InputProcesses     : supply a fixed process list instead of Get-Process
    #   -Now                : supply a fixed "now" instead of Get-Date
    #   -ParentPathResolver : supply a { param($id) ... } resolver instead of
    #                         Get-ParentProcessPath (avoids real CIM calls)
    [CmdletBinding()]
    param(
        [string[]]$Names = @('bash', 'gh', 'git'),
        [int]$IdleMinutes = 10,
        [double]$MaxCpuSeconds = 5.0,
        [object[]]$InputProcesses,
        [datetime]$Now,
        [scriptblock]$ParentPathResolver
    )

    if (-not $PSBoundParameters.ContainsKey('Now')) { $Now = Get-Date }
    $threshold = $Now.AddMinutes(-$IdleMinutes)

    if ($PSBoundParameters.ContainsKey('InputProcesses')) {
        $candidates = $InputProcesses
    } else {
        $candidates = Get-Process -Name $Names -ErrorAction SilentlyContinue
    }

    $orphans = @()
    foreach ($p in $candidates) {
        if ($null -eq $p) { continue }

        # GUI-owning processes (a terminal window the user opened) are not orphans.
        if ($p.MainWindowTitle) { continue }

        # Recently started processes may still be doing useful work.
        try {
            if ($p.StartTime -gt $threshold) { continue }
        } catch {
            # StartTime can be inaccessible (permission). Stay safe: skip.
            continue
        }

        # Busy processes are active workers, not idle orphans.
        try {
            if ($p.CPU -gt $MaxCpuSeconds) { continue }
        } catch {
            continue
        }

        # Processes whose parent is an IDE are owned by that IDE (integrated
        # terminal, task runner); killing them would disrupt the user.
        if ($PSBoundParameters.ContainsKey('ParentPathResolver')) {
            $parentPath = & $ParentPathResolver $p.Id
        } else {
            $parentPath = Get-ParentProcessPath -ProcessId $p.Id
        }
        if ($parentPath -match 'Code\.exe$|cursor\.exe$|sublime|atom\.exe$|jetbrains') {
            continue
        }

        $orphans += $p
    }

    # Emit the matches to the pipeline. Callers wrap in @(...) so an empty result
    # is a zero-length array and a single match is still array-typed. (A comma
    # "return ,$orphans" was tried and rejected: it nests the array one level,
    # so @(call) sees a single element instead of the contents.)
    return $orphans
}

function Invoke-ProcessCleanup {
    # Find orphaned bash / gh / git processes and kill them (or, with -DryRun,
    # just report what would be killed). Default is to apply (kill); -DryRun is
    # the explicit opt-out. See ADR-0011.
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [switch]$DryRun,
        [string[]]$Names = @('bash', 'gh', 'git'),
        [int]$IdleMinutes = 10,
        [double]$MaxCpuSeconds = 5.0
    )

    Write-Host ""
    Write-Host "=== Cleanup orphan processes ==="
    Write-Host "Targets: $($Names -join ', ')"
    Write-Host "Filter:  idle >= $IdleMinutes min, CPU < $MaxCpuSeconds sec, no MainWindow, parent not IDE"
    if ($DryRun) { Write-Host "[DryRun] No processes will be killed" -ForegroundColor Yellow }
    Write-Host ""

    $orphans = @(Get-OrphanedProcesses -Names $Names -IdleMinutes $IdleMinutes -MaxCpuSeconds $MaxCpuSeconds)

    if ($orphans.Count -eq 0) {
        Write-Host "[OK] No orphan processes found."
        return
    }

    Write-Host "Found $($orphans.Count) orphan process(es):"
    foreach ($p in $orphans) {
        $age = '?'
        try { $age = [Math]::Floor(((Get-Date) - $p.StartTime).TotalMinutes) } catch { }
        $cpu = '?'
        try { $cpu = [Math]::Round($p.CPU, 1) } catch { }
        Write-Host "  PID=$($p.Id) $($p.ProcessName) (age=${age}m, CPU=${cpu}s)"
    }

    if ($DryRun) {
        Write-Host ""
        Write-Host "[DryRun] Would kill the above process(es). Re-run without -DryRun to apply."
        return
    }

    Write-Host ""
    Write-Host "Killing..."
    foreach ($p in $orphans) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-Host "  [killed] PID=$($p.Id) $($p.ProcessName)"
        } catch {
            Write-Warning "  [failed] PID=$($p.Id) $($p.ProcessName): $_"
        }
    }
    Write-Host ""
    Write-Host "[OK] Cleanup complete."
}

# When dot-sourced (the kit's convention) the functions are already visible in
# the caller scope, so Export-ModuleMember must be skipped: it errors outside a
# module and these scripts run with $ErrorActionPreference = 'Stop'.
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function Get-ParentProcessPath, Get-OrphanedProcesses, Invoke-ProcessCleanup
}

# Direct-invocation entry point. When the file is dot-sourced ($MyInvocation
# InvocationName is '.'), only the functions load and no cleanup runs -- that is
# what tests and library callers rely on. A direct run (pwsh ...file.ps1) reports
# InvocationName as the script name/path, so the cleanup executes.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ProcessCleanup -DryRun:$DryRun -Names $Names -IdleMinutes $IdleMinutes -MaxCpuSeconds $MaxCpuSeconds
}
