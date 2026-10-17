#requires -Version 5.1
# link-safety.ps1
# Provides: safe replacement of a deploy target that is a symlink / junction, plus
#           timestamped backups of files the apply run is about to overwrite.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0015 step 3.
#
# Functions:
#   Get-LinkState     - classify a path as missing / regular file / reparse point
#   New-KitBackup     - copy a file's CONTENT into a timestamped backup directory
#   Remove-LinkOnly   - delete a link without following it to its target
#
# Why this exists:
# apply-claude-kit.ps1 writes ~/.claude/CLAUDE.md unconditionally in Global mode.
# When that path is a symlink, Write-Utf8NoBom follows it and rewrites whatever it
# points at -- a file outside ~/.claude entirely. On the author's machine the link
# pointed into a different repository, so every Global apply had been silently
# editing that repository's copy. Replacing the link is therefore a destructive
# operation on someone else's file and must be backed up and reversible first.

function Get-LinkState {
    # Classify a deploy target. $ItemInfo is an injection point: tests pass a stub
    # exposing .Attributes (and optionally .Target / .LinkType) so the reparse-point
    # branch is covered on hosts where creating a real symlink needs privileges
    # this process may not hold. Production callers omit it.
    param(
        [Parameter(Mandatory)][string]$Path,
        $ItemInfo
    )

    if (-not $ItemInfo) {
        if (-not (Test-Path -LiteralPath $Path)) {
            return [ordered]@{ Exists = $false; IsLink = $false; Target = $null; LinkType = $null }
        }
        $ItemInfo = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if (-not $ItemInfo) {
            return [ordered]@{ Exists = $false; IsLink = $false; Target = $null; LinkType = $null }
        }
    }

    # ReparsePoint covers both symbolic links and junctions. Checking the attribute
    # rather than LinkType keeps this working on PS 5.1 builds where LinkType and
    # Target are not populated for every link kind.
    $isLink = $false
    if ($null -ne $ItemInfo.Attributes) {
        $isLink = [bool]([int]$ItemInfo.Attributes -band [int][System.IO.FileAttributes]::ReparsePoint)
    }

    # Target is informational (it goes into the restore manifest), so a host that
    # does not expose it must not break the classification.
    $target = $null
    try { if ($ItemInfo.Target) { $target = @($ItemInfo.Target)[0] } } catch { $target = $null }
    $linkType = $null
    try { if ($ItemInfo.LinkType) { $linkType = [string]$ItemInfo.LinkType } } catch { $linkType = $null }

    return [ordered]@{
        Exists   = $true
        IsLink   = $isLink
        Target   = $target
        LinkType = $linkType
    }
}

function Resolve-ReparsePath {
    # Rewrite $Path so that any DIRECTORY reparse point along it is replaced by
    # what it points at. Returns the path unchanged when nothing resolves, so
    # callers can use it unconditionally.
    #
    # Why: an elevated process is blocked from traversing a junction that a
    # non-administrator created ("untrusted mount point" / the redirection-trust
    # mitigation). A user who shares ~/.claude/skills across machines through a
    # OneDrive junction therefore cannot run an elevated apply at all -- the
    # write fails on traversal, not on permissions. Writing to the resolved
    # target reaches the same bytes without traversing the link.
    #
    # Only directories are resolved. A reparse point that is a FILE is left
    # alone: that is the ~/.claude/CLAUDE.md symlink case, which Get-LinkState
    # and Remove-LinkOnly handle by unlinking instead.
    param([Parameter(Mandatory)][string]$Path)

    if (-not $Path) { return $Path }
    $full = $Path
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return $Path }

    $root = [System.IO.Path]::GetPathRoot($full)
    if (-not $root) { return $full }
    $rest = $full.Substring($root.Length)
    if (-not $rest) { return $full }

    $current = $root.TrimEnd('\')
    $segments = @($rest -split '[\\/]' | Where-Object { $_ })
    $hops = 0
    foreach ($segment in $segments) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { continue }
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if (-not $item -or -not $item.PSIsContainer) { continue }
        if (-not ([int]$item.Attributes -band [int][System.IO.FileAttributes]::ReparsePoint)) { continue }

        $target = $null
        # Older PS 5.1 builds do not populate Target for every link kind; leaving
        # the path as-is is the safe outcome there.
        try { if ($item.Target) { $target = @($item.Target)[0] } } catch { $target = $null }
        if (-not $target) { continue }

        # A junction pointing at a network location is left alone: resolving it
        # buys nothing and following it can contact the host it names.
        if ($target -like '\\\\*') { continue }

        $hops++
        if ($hops -gt 8) { break }   # cycle guard
        $current = $target.TrimEnd('\')
    }
    return $current
}

function Resolve-DeployTargets {
    # Resolve directory links in each named *Dir variable of the CALLER's scope,
    # reporting every substitution. Kept here rather than inline in
    # apply-claude-kit.ps1, which sits at the kit's 500-line file-granularity cap.
    param(
        [Parameter(Mandatory)][string[]]$VariableNames
    )

    foreach ($var in $VariableNames) {
        $before = Get-Variable -Name $var -Scope 1 -ValueOnly -ErrorAction SilentlyContinue
        if (-not $before) { continue }
        $after = Resolve-ReparsePath -Path $before
        if ($after -eq $before) { continue }
        Write-Host "[link] $before -> $after (resolved; elevated runs cannot traverse the link)"
        Set-Variable -Name $var -Value $after -Scope 1
    }
}

function New-KitBackup {
    # Copy the CONTENT at $Path into <BackupRoot>/<stamp>/<name> and append a
    # restore manifest entry. Reading through a link on purpose: the point of the
    # backup is to preserve what the user currently sees at that path.
    #
    # Returns the backup file path, or $null when there was nothing to back up.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$Stamp,
        [string]$Note,
        [switch]$IsDryRun
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    if (-not $Stamp) { $Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss') }

    $dir = Join-Path $BackupRoot $Stamp
    $name = Split-Path -Leaf $Path
    $dest = Join-Path $dir $name

    if ($IsDryRun) {
        Write-Host "[dry-run] backup $Path -> $dest"
        return $dest
    }

    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    # A name collision inside one backup directory (same leaf from two places,
    # e.g. two rule files of the same id) would otherwise overwrite the first copy.
    if (Test-Path -LiteralPath $dest) {
        $suffix = 2
        while (Test-Path -LiteralPath (Join-Path $dir ("$name.$suffix"))) { $suffix++ }
        $dest = Join-Path $dir ("$name.$suffix")
    }

    $state = Get-LinkState -Path $Path
    # Copy-Item follows a file link and copies the content it resolves to, which is
    # what we want: the backup holds the bytes, the manifest holds the link target.
    Copy-Item -LiteralPath $Path -Destination $dest -Force

    $manifestPath = Join-Path $dir "restore-manifest.json"
    $entries = @()
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $existing = (Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8) | ConvertFrom-Json
            # PS 5.1 hands back a single object rather than a one-element array, so
            # force enumeration instead of indexing (see the ConvertFrom-Json note
            # in the kit's PS 5.1 compatibility rules).
            if ($existing) { $existing | ForEach-Object { $entries += $_ } }
        } catch {
            $entries = @()
        }
    }
    $entries += [PSCustomObject]@{
        OriginalPath = $Path
        BackupPath   = $dest
        WasLink      = [bool]$state.IsLink
        LinkTarget   = $state.Target
        LinkType     = $state.LinkType
        Note         = $Note
        BackedUpAt   = (Get-Date).ToString('s')
    }
    Write-Utf8NoBom -Path $manifestPath -Content ($entries | ConvertTo-Json -Depth 4)
    Write-Host "[backup] $Path -> $dest"
    return $dest
}

function Remove-LinkOnly {
    # Delete a link without following it. [System.IO.File]::Delete removes the link
    # entry itself; Remove-Item on a DIRECTORY link can recurse into the target on
    # older hosts, so directory links are handled through Directory.Delete($path,
    # $false) which likewise unlinks rather than descends.
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$IsDryRun
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if ($IsDryRun) {
        Write-Host "[dry-run] remove link $Path"
        return $true
    }

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and $item.PSIsContainer) {
        [System.IO.Directory]::Delete($Path, $false)
    } else {
        [System.IO.File]::Delete($Path)
    }
    return $true
}
