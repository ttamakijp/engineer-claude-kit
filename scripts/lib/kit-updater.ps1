#requires -Version 5.1
# kit-updater.ps1
# Shared helpers: Test-KitBehind, Invoke-KitUpdate -- kit self-update support.
#
# Why this exists (see ADR-0013):
#   - After a user installs the kit (e.g. cloned to ~/.claude-kit/), new commits
#     on origin do not reach their working copy. Running `apply` then deploys
#     stale skills / templates without the user noticing.
#   - Test-KitBehind detects (quietly, with a timeout) whether the local checkout
#     is behind origin so the apply entry script can print an opt-in hint.
#   - Invoke-KitUpdate performs the explicit, user-requested fast-forward pull
#     (or a -Force hard reset escape hatch). It is never run automatically.
#
# Design notes:
#   - The real `git` paths are wrapped in overridable scriptblock injection points
#     (-FetchAction / -BranchResolver / -BehindCounter / -GitRunner). This mirrors
#     the kit's testing convention (see cleanup-processes.ps1): tests drive the
#     control flow deterministically instead of mocking the native git executable,
#     which is unreliable under Pester 3.4 on Windows PowerShell 5.1.
#   - Default behavior (no injection) is exactly the production git flow described
#     in ADR-0013: fetch with a timeout, then compare HEAD against origin/<branch>.
#   - Network / non-git / timeout failures are swallowed and reported as -1 so the
#     caller can stay silent (never block apply on a flaky network).
#
# ASCII only (no Japanese in code, comments, or strings). See ADR-0003 section C.
# PS 5.1 compatible: no PS 6+ syntax, no PS 6+ cmdlets.

function Test-KitBehind {
    # Returns the number of commits the local checkout is behind origin/<branch>.
    #   >= 0 : behind by that many commits (0 == up to date)
    #   -1   : could not determine (not a git repo, fetch failed/timed out, or
    #          any git error) -- the caller should treat this as "stay silent".
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$KitRoot,
        [int]$FetchTimeoutSec = 5,

        # Injection points (tests). Defaults run the real git flow.
        # FetchAction:    returns $true on a successful fetch, $false otherwise.
        # BranchResolver: returns the current branch name (or $null on failure).
        # BehindCounter:  given a branch name, returns the behind count as a
        #                 string/int (or $null/empty on failure).
        [scriptblock]$FetchAction,
        [scriptblock]$BranchResolver,
        [scriptblock]$BehindCounter
    )

    # A git repo has a .git entry (directory for a normal clone, file for a
    # worktree); Test-Path matches both. Absent -> not a kit clone -> -1.
    if (-not (Test-Path (Join-Path $KitRoot '.git'))) { return -1 }

    if (-not $FetchAction) {
        $FetchAction = {
            param($root, $timeoutSec)
            # Run fetch in a background job so a hung network call cannot block
            # apply longer than the timeout. The job is always cleaned up.
            $job = Start-Job -ScriptBlock {
                param($r) git -C $r fetch --quiet origin 2>$null
            } -ArgumentList $root
            try {
                Wait-Job -Job $job -Timeout $timeoutSec | Out-Null
                if ($job.State -eq 'Running') {
                    Stop-Job -Job $job
                    return $false
                }
                return $true
            } finally {
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }
    }
    if (-not $BranchResolver) {
        $BranchResolver = {
            param($root)
            git -C $root rev-parse --abbrev-ref HEAD 2>$null
        }
    }
    if (-not $BehindCounter) {
        $BehindCounter = {
            param($root, $branch)
            git -C $root rev-list --count "HEAD..origin/$branch" 2>$null
        }
    }

    try {
        $fetched = & $FetchAction $KitRoot $FetchTimeoutSec
        if (-not $fetched) { return -1 }
    } catch {
        return -1
    }

    try {
        $branch = & $BranchResolver $KitRoot
        if ([string]::IsNullOrWhiteSpace($branch)) { return -1 }
        $branch = "$branch".Trim()

        $behind = & $BehindCounter $KitRoot $branch
        if ([string]::IsNullOrWhiteSpace("$behind")) { return -1 }
        return [int]("$behind".Trim())
    } catch {
        return -1
    }
}

function Invoke-KitUpdate {
    # Performs the explicit, user-requested update of the kit checkout.
    #   default : git pull --ff-only origin <branch>  (fast-forward only; a
    #             divergent history fails loudly rather than creating a merge)
    #   -Force  : git reset --hard origin/<branch>     (escape hatch; discards
    #             any local edits to the kit checkout)
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$KitRoot,
        [switch]$Force,

        # Injection point (tests). Receives the git arguments as a single array
        # and is expected to run them. Defaults to invoking the real git.
        [scriptblock]$GitRunner,
        [scriptblock]$BranchResolver
    )

    if (-not $BranchResolver) {
        $BranchResolver = {
            param($root)
            git -C $root rev-parse --abbrev-ref HEAD 2>$null
        }
    }
    if (-not $GitRunner) {
        $GitRunner = {
            param($gitArgs)
            & git @gitArgs
        }
    }

    $branch = & $BranchResolver $KitRoot
    if ([string]::IsNullOrWhiteSpace($branch)) {
        Write-Warning "Could not resolve current branch; skipping kit update."
        return
    }
    $branch = "$branch".Trim()

    if ($Force) {
        & $GitRunner @('-C', $KitRoot, 'fetch', 'origin') | Out-Null
        & $GitRunner @('-C', $KitRoot, 'reset', '--hard', "origin/$branch")
        Write-Host "[WARN] kit force-reset to origin/$branch"
    } else {
        & $GitRunner @('-C', $KitRoot, 'pull', '--ff-only', 'origin', $branch)
        Write-Host "[OK] kit updated (fast-forward) on $branch"
    }
}

# When dot-sourced (the kit's convention) the functions are already visible in
# the caller scope, so Export-ModuleMember must be skipped: it errors outside a
# module and these scripts run with $ErrorActionPreference = 'Stop'. See the same
# guard in cleanup-processes.ps1 / models-config.ps1 / encoding-helper.ps1.
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function Test-KitBehind, Invoke-KitUpdate
}
