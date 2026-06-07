#requires -Version 5.1
# privilege-check.ps1
# Shared helper: Assert-NonElevated -- fail-fast when running as Administrator.
# engineer-claude-kit entry scripts are designed to run under a normal user
# account. Running them elevated makes ~/.claude/ owned by Administrators, which
# later causes permission-denied errors for normal-user runs. See ADR-0008.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0003 section C.

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

    if ($AllowElevated) {
        Write-Warning ("Running as Administrator. Continuing because -AllowElevated was specified, " +
            "but ~/.claude/ may become owned by Administrators, which can cause permission-denied " +
            "errors on later normal-user runs.")
        return
    }

    Write-Host ""
    Write-Warning "Running as Administrator. This script is designed to run as a normal user."
    Write-Host ""
    Write-Host "  - It only writes under `$env:USERPROFILE\.claude\ and needs no admin rights."
    Write-Host "  - Running elevated makes `$env:USERPROFILE\.claude\ owned by Administrators,"
    Write-Host "    which can cause permission-denied errors on later normal-user runs."
    Write-Host ""
    Write-Host "Fix: re-run from a normal (non-elevated) PowerShell session."
    Write-Host "     To force elevated execution anyway, pass -AllowElevated (not recommended)."
    Write-Host ""
    exit 2
}
