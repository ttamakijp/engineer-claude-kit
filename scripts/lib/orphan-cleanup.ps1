#requires -Version 5.1
# orphan-cleanup.ps1
# Provides: Get-KitPreviousAppliedFiles - the applied_files list recorded by the
#           previous apply run.
#           Remove-OrphanedKitFiles     - delete files the kit deployed on a
#           previous run but no longer ships.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0015 step 3.
#
# Deploy is additive: it writes what the kit ships now and never looks at what it
# shipped last time. Two bugs of that shape have now surfaced one directory
# apart. ADR-0015 deleted a rule whose deployed copy kept loading into every
# session, and withdrawing the three Haiku delegation agents (ADR-0016 decision
# B) would have left their descriptions in every session's agent roster for as
# long as the files sat in ~/.claude/agents/. The removal is therefore written
# once, generic over the subdirectory, rather than a second time per payload.
#
# Only files the kit itself deployed are removed, and the marker's applied_files
# is the record of that. A file the user wrote by hand was never in the list: it
# is reported and never deleted.
#
# Dependencies, dot-sourced by the caller before this file:
#   Read-Utf8NoBom (encoding-helper.ps1)
#   New-KitBackup  (link-safety.ps1)

function Get-KitPreviousAppliedFiles {
    # Read applied_files from the marker of the last run. The caller has to do
    # this BEFORE Write-AppliedMarker overwrites the marker with this run's list.
    param(
        [Parameter(Mandatory)][string]$MarkerRoot
    )

    $previous = @()
    $marker = Join-Path $MarkerRoot ".engineer-claude-kit-applied"
    if (-not (Test-Path -LiteralPath $marker)) { return $previous }
    try {
        $json = (Read-Utf8NoBom -Path $marker) | ConvertFrom-Json
        # Piped through ForEach-Object rather than cast: PS 5.1 hands a
        # single-element JSON array back as one object.
        if ($json.applied_files) {
            $json.applied_files | ForEach-Object { $previous += [string]$_ }
        }
    } catch {
        # A truncated or hand-edited marker must not abort the apply. With no
        # readable record nothing is attributable, so nothing gets removed.
        return @()
    }
    return $previous
}

function Remove-OrphanedKitFiles {
    # Delete the *.md files under $TargetDir that this kit deployed before and no
    # longer ships. Anything else in the directory is reported, not touched.
    param(
        [Parameter(Mandatory)][string]$TargetDir,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$CurrentApplied,
        # Directory name a marker entry must sit under to count as this payload
        # ('rules', 'agents'). Marker paths are absolute and cover every payload
        # the run deployed, so without this filter a withdrawn rule would
        # authorise deleting a same-named file under agents/ and the other way
        # round.
        [Parameter(Mandatory)][string]$PathSegment,
        # Singular noun used in the messages ('rule', 'agent').
        [string]$Kind = "file",
        [AllowEmptyCollection()][string[]]$PreviousAppliedFiles = @(),
        [string]$BackupRoot,
        [string]$BackupStamp,
        [switch]$IsDryRun
    )

    if (-not (Test-Path -LiteralPath $TargetDir)) { return }

    # Compare on leaf names: the marker stores absolute paths from the machine it
    # ran on, which may differ in casing or drive mapping.
    $currentNames = @{}
    foreach ($p in $CurrentApplied) { $currentNames[(Split-Path -Leaf $p).ToLowerInvariant()] = $true }
    # String containment on separator-normalised paths rather than a regex: on
    # Windows the path separator is also the regex escape character, so a
    # character class spelling it is easy to get wrong in a way that matches no
    # path at all and silently removes nothing.
    $needle = "/" + $PathSegment.ToLowerInvariant() + "/"
    $previousNames = @{}
    foreach ($p in $PreviousAppliedFiles) {
        $norm = $p.Replace('\', '/').ToLowerInvariant()
        if ($norm.Contains($needle)) { $previousNames[(Split-Path -Leaf $p).ToLowerInvariant()] = $true }
    }

    $unmanaged = @()
    foreach ($file in (Get-ChildItem -LiteralPath $TargetDir -Filter "*.md" -File)) {
        $leaf = $file.Name.ToLowerInvariant()
        if ($currentNames.ContainsKey($leaf)) { continue }

        if ($previousNames.ContainsKey($leaf)) {
            if ($IsDryRun) {
                Write-Host "[dry-run] would remove $($file.FullName) (no longer shipped by the kit)"
            } else {
                if ($BackupRoot) {
                    $null = New-KitBackup -Path $file.FullName -BackupRoot $BackupRoot -Stamp $BackupStamp `
                        -Note "$Kind removed: the kit no longer ships it"
                }
                Remove-Item -LiteralPath $file.FullName -Force
                Write-Host "[remove] $($file.FullName) (no longer shipped by the kit)"
            }
        } else {
            $unmanaged += $file.Name
        }
    }

    if ($unmanaged.Count -gt 0) {
        Write-Host ("[note] not shipped by this kit and left untouched: " + ($unmanaged -join ", "))
        Write-Host "       If one of these is a kit $Kind from an older version, delete it by hand:"
        Write-Host "       it is loaded into every session as long as it sits there."
    }
}
