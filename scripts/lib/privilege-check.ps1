#requires -Version 5.1
# privilege-check.ps1
# Shared helper: Assert-NonElevated -- fail-fast when running as Administrator.
# engineer-claude-kit entry scripts are designed to run under a normal user
# account. Running them elevated makes ~/.claude/ owned by Administrators, which
# later causes permission-denied errors for normal-user runs. See ADR-0008.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0003 section C.

function Test-UacEnabled {
    # $true when UAC is on, $false when it is off, $null when unknown.
    #
    # This distinction decides whether the guard is actionable. With UAC ON a
    # member of Administrators gets a split token: the limited token carries the
    # Administrators SID as "deny only", so IsInRole(Administrator) is $false and
    # the guard stays quiet -- which is the common case and needs no escape hatch.
    # With UAC OFF there is no split token at all: every session runs with the
    # full administrator token, IsInRole is always $true, and "re-run from a
    # normal session" is impossible to follow because no such session exists.
    #
    # Reading this value needs no elevation (HKLM read). Returning $null on
    # failure keeps the caller on the conservative path.
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    try {
        $value = (Get-ItemProperty -Path $key -Name EnableLUA -ErrorAction Stop).EnableLUA
        if ($null -eq $value) { return $null }
        return ([int]$value -ne 0)
    } catch {
        return $null
    }
}

function Get-ElevationDiagnostics {
    # One line naming what was actually detected, so a surprising refusal can be
    # diagnosed from the message instead of guessed at. The previous message said
    # only "Running as Administrator", which gave the reader nothing to check.
    $integrity = 'unknown'
    try {
        $whoami = Join-Path $env:SystemRoot 'System32\whoami.exe'
        if (Test-Path -LiteralPath $whoami) {
            $line = & $whoami /groups 2>$null | Select-String 'S-1-16-\d+' | Select-Object -First 1
            if ($line -and $line.Line -match '(S-1-16-\d+)') { $integrity = $Matches[1] }
        }
    } catch {
        $integrity = 'unknown'
    }
    $uac = Test-UacEnabled
    $uacText = if ($null -eq $uac) { 'unknown' } elseif ($uac) { 'enabled' } else { 'DISABLED' }
    return "integrity=$integrity, UAC=$uacText"
}

function Assert-NonElevated {
    # Aborts the calling script (exit 2) when it is running with Administrator
    # privileges, unless -AllowElevated is passed (escape hatch -> warn + continue).
    # No-op on non-Windows PowerShell and when elevation cannot be determined.
    [CmdletBinding()]
    param(
        [switch]$AllowElevated
    )

    # Non-Windows PowerShell (Linux/macOS) has no Administrator concept here and
    # the WindowsIdentity APIs throw PlatformNotSupportedException, so treat it as
    # a no-op. PS 5.1 has no $IsWindows automatic variable, so probe it indirectly
    # (absence of the variable implies Windows PowerShell, which is Windows-only).
    $isWindowsOS = $true
    $isWindowsVar = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
    if ($isWindowsVar) { $isWindowsOS = [bool]$isWindowsVar.Value }
    if (-not $isWindowsOS) { return }

    $isAdmin = $false
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        # If elevation cannot be determined, do not block the user.
        Write-Warning "Could not determine elevation state (continuing): $_"
        return
    }

    if (-not $isAdmin) { return }

    $diag = Get-ElevationDiagnostics

    if ($AllowElevated) {
        Write-Warning ("Running as Administrator ($diag). Continuing because -AllowElevated was " +
            "specified, but ~/.claude/ may become owned by Administrators, which can cause " +
            "permission-denied errors on later normal-user runs.")
        return
    }

    # UAC off: there is no non-elevated session to switch to, so refusing would
    # make the kit unusable without a flag while adding no safety -- elevated is
    # the only state this machine has. Warn and continue instead. See ADR-0008.
    if ((Test-UacEnabled) -eq $false) {
        Write-Warning ("Running with the full administrator token because UAC is disabled on this " +
            "machine ($diag). There is no non-elevated session to re-run from, so continuing. " +
            "~/.claude/ will be owned by Administrators; if you later enable UAC and run as a " +
            "normal user, fix the ownership of that directory first.")
        return
    }

    Write-Host ""
    Write-Warning "Running as Administrator. This script is designed to run as a normal user."
    Write-Host ""
    Write-Host "  Detected: $diag"
    Write-Host ""
    Write-Host "  - It only writes under `$env:USERPROFILE\.claude\ and needs no admin rights."
    Write-Host "  - Running elevated makes `$env:USERPROFILE\.claude\ owned by Administrators,"
    Write-Host "    which can cause permission-denied errors on later normal-user runs."
    Write-Host ""
    Write-Host "Note: merely belonging to the Administrators group does NOT trigger this. With UAC"
    Write-Host "      on, the limited token carries that group as 'deny only', so this check stays"
    Write-Host "      quiet. Seeing this message means the session really is elevated."
    Write-Host ""
    Write-Host "Fix: re-run from a normal (non-elevated) PowerShell session."
    Write-Host "     To force elevated execution anyway, pass -AllowElevated (not recommended)."
    Write-Host ""
    exit 2
}
