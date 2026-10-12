#requires -Version 5.1
# scheduled-tasks-deploy.ps1
# Provides: Copy-ScheduledTaskDir - deploy one scheduled-task spec directory.
# ASCII only (no Japanese in code, comments, or strings).
#
# Extracted from apply-claude-kit.ps1 to keep that script inside the kit's own
# 500-line file-granularity cap (same reason as models-config.ps1 and friends).
# Merging the branch-protection task spec pushed that script to 507 lines.
#
# Dependencies, dot-sourced by the caller before this file:
#   Read-Utf8NoBom / Write-Utf8NoBom (encoding-helper.ps1)

function Copy-ScheduledTaskDir {
    # Copy every *.md under one task subdir to
    # ~/.claude/scheduled-tasks/<name>/<file>.md, preserving the parent directory
    # as the task name (mirrors the skills layout). Specs carry no role
    # placeholders, so they are copied verbatim. Returns the deployed dest paths.
    param([string]$SourceTaskDir, [string]$TargetSchedTasksDir, [switch]$IsDryRun)

    $deployed = @()
    if (-not (Test-Path -LiteralPath $SourceTaskDir)) { return $deployed }
    $taskName = Split-Path -Leaf $SourceTaskDir
    foreach ($file in (Get-ChildItem -LiteralPath $SourceTaskDir -Filter "*.md" -File)) {
        $dest = Join-Path (Join-Path $TargetSchedTasksDir $taskName) $file.Name
        if ($IsDryRun) {
            Write-Host "[dry-run] $($file.FullName) -> $dest"
        } else {
            $body = Read-Utf8NoBom -Path $file.FullName
            # The task subdir is absent on first deploy and Write-Utf8NoBom does
            # not create parents (same ensure as Copy-Template).
            $destDir = Split-Path -Parent $dest
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            }
            Write-Utf8NoBom -Path $dest -Content $body
            Write-Host "[apply] $($file.FullName) -> $dest"
        }
        $deployed += $dest
    }
    return $deployed
}
