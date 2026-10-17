#requires -Version 5.1
# rules-deploy.ps1
# Provides: Install-KitRules - build (if stale) and deploy dist/.claude/rules/*.md
#           into a target rules directory, returning the deployed paths.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0015 step 3.
#
# Extracted from apply-claude-kit.ps1 to keep that script inside the kit's own
# 500-line file-granularity cap (same reason as models-config.ps1).
#
# Claude Code loads rules from two places: ~/.claude/rules/ for every project on
# the machine, and <project>/.claude/rules/ for that project, user-level first.
# Global mode deploys the former, Project mode the latter. Deploying both on one
# machine loads each rule twice -- neither location overrides the other -- so the
# Project path warns when a rule of the same id already exists globally.
#
# Dependencies, dot-sourced by the caller before this file:
#   Read-Utf8NoBom / Write-Utf8NoBom (encoding-helper.ps1)
#   New-KitBackup                    (link-safety.ps1)

function Update-KitRulesBuild {
    # Rebuild dist/.claude/rules/ when it is absent, empty, or older than source.
    # build-rules.ps1 compiles source/rules/*.md into dist/.claude/rules/<id>.md
    # with audience filtering.
    param(
        [Parameter(Mandatory)][string]$KitRoot,
        [Parameter(Mandatory)][string]$DistRulesDir,
        [switch]$IsDryRun
    )

    $sourceRulesDir = Join-Path (Join-Path $KitRoot "source") "rules"
    $buildScript = Join-Path (Join-Path $KitRoot "scripts") "build-rules.ps1"

    $needBuild = $false
    if (-not (Test-Path $DistRulesDir)) {
        $needBuild = $true
    } elseif (Test-Path $sourceRulesDir) {
        $newestSource = Get-ChildItem -LiteralPath $sourceRulesDir -Recurse -Filter "*.md" -File |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        $newestDist = Get-ChildItem -LiteralPath $DistRulesDir -Filter "*.md" -File |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if ($null -eq $newestDist) {
            $needBuild = $true
        } elseif ($null -ne $newestSource -and $newestSource.LastWriteTimeUtc -gt $newestDist.LastWriteTimeUtc) {
            $needBuild = $true
        }
    }
    if (-not $needBuild) { return }

    if ($IsDryRun) {
        Write-Host "[dry-run] would build rules from source/rules/ (dist missing or stale)"
        return
    }
    if (-not (Test-Path $buildScript)) {
        Write-Warning "build-rules.ps1 not found at: $buildScript"
        return
    }
    Write-Host "[rules] dist is missing or stale; building from source/rules/"
    # Switch cwd to the kit root while invoking build-rules.ps1, then restore.
    Push-Location $KitRoot
    try {
        & $buildScript | Out-Null
    } finally {
        Pop-Location
    }
}

function Install-KitRules {
    # Deploy every built rule into $TargetRulesDir. Returns the deployed paths so
    # the caller can record them in the applied-files marker.
    # -PreviousAppliedFiles is the applied_files list from the marker of the LAST
    # run. Deploy used to be additive only, so a rule the kit stopped shipping was
    # left behind and kept loading forever. ADR-0015 deleted
    # project-skill-recommend.md, yet the deployed copy (3,554 B, no paths, so
    # unconditional) survived the apply and silently inflated the context the
    # reduction was supposed to shrink.
    #
    # Only files the kit itself deployed last time are removed. A rule the user
    # wrote by hand was never in applied_files and is reported, never deleted.
    param(
        [Parameter(Mandatory)][string]$KitRoot,
        [Parameter(Mandatory)][string]$TargetRulesDir,
        [Parameter(Mandatory)][string]$Mode,
        [string]$BackupRoot,
        [string]$BackupStamp,
        [string[]]$PreviousAppliedFiles = @(),
        [switch]$IsDryRun
    )

    $distRulesDir = Join-Path (Join-Path (Join-Path $KitRoot "dist") ".claude") "rules"
    Update-KitRulesBuild -KitRoot $KitRoot -DistRulesDir $distRulesDir -IsDryRun:$IsDryRun

    $applied = @()
    if (-not (Test-Path $distRulesDir)) { return $applied }

    # Double-load check (Project mode only): a rule already present in
    # ~/.claude/rules/ is loaded alongside the project copy.
    $globalRulesDir = $null
    if ($Mode -eq "Project") {
        $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        $globalRulesDir = Join-Path (Join-Path $userHome ".claude") "rules"
    }
    $duplicates = @()

    foreach ($ruleFile in (Get-ChildItem -LiteralPath $distRulesDir -Filter "*.md" -File)) {
        $destRule = Join-Path $TargetRulesDir $ruleFile.Name
        if ($globalRulesDir -and (Test-Path (Join-Path $globalRulesDir $ruleFile.Name))) {
            $duplicates += $ruleFile.Name
        }

        # Verbatim UTF-8 (no BOM) copy; rules contain no role placeholders.
        $ruleContent = Read-Utf8NoBom -Path $ruleFile.FullName
        if ($IsDryRun) {
            Write-Host "[dry-run] $($ruleFile.FullName) -> $destRule"
        } else {
            if (-not (Test-Path $TargetRulesDir)) {
                New-Item -ItemType Directory -Force -Path $TargetRulesDir | Out-Null
            }
            # Back up a hand-edited rule before clobbering it. Rules are generated,
            # so an existing file usually matches byte for byte and no backup is
            # taken; only a divergent copy is worth preserving.
            if ($BackupRoot -and (Test-Path -LiteralPath $destRule)) {
                $existing = Read-Utf8NoBom -Path $destRule
                if ($existing -ne $ruleContent) {
                    $null = New-KitBackup -Path $destRule -BackupRoot $BackupRoot -Stamp $BackupStamp `
                        -Note "rule content differed from the kit build; overwritten by apply"
                }
            }
            Write-Utf8NoBom -Path $destRule -Content $ruleContent
            Write-Host "[apply] $($ruleFile.FullName) -> $destRule"
        }
        $applied += $destRule
    }

    if ($duplicates.Count -gt 0) {
        Write-Warning ("These rules also exist in " + $globalRulesDir + ", so Claude Code loads each of them twice: " + ($duplicates -join ", "))
        Write-Warning "Keep one copy: delete the project copies, or deploy globally only."
    }

    Remove-OrphanedKitRules -TargetRulesDir $TargetRulesDir -CurrentApplied $applied `
        -PreviousAppliedFiles $PreviousAppliedFiles -BackupRoot $BackupRoot `
        -BackupStamp $BackupStamp -IsDryRun:$IsDryRun

    return $applied
}

function Remove-OrphanedKitRules {
    # Delete rules the kit deployed on a previous run but no longer ships.
    # Anything else that happens to sit in the directory is reported, not touched.
    param(
        [Parameter(Mandatory)][string]$TargetRulesDir,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$CurrentApplied,
        [AllowEmptyCollection()][string[]]$PreviousAppliedFiles = @(),
        [string]$BackupRoot,
        [string]$BackupStamp,
        [switch]$IsDryRun
    )

    if (-not (Test-Path -LiteralPath $TargetRulesDir)) { return }

    # Compare on leaf names: the marker stores absolute paths from the machine it
    # ran on, which may differ in casing or drive mapping.
    $currentNames = @{}
    foreach ($p in $CurrentApplied) { $currentNames[(Split-Path -Leaf $p).ToLowerInvariant()] = $true }
    $previousNames = @{}
    foreach ($p in $PreviousAppliedFiles) {
        if ($p -match '[\\/]rules[\\/]') { $previousNames[(Split-Path -Leaf $p).ToLowerInvariant()] = $true }
    }

    $unmanaged = @()
    foreach ($file in (Get-ChildItem -LiteralPath $TargetRulesDir -Filter "*.md" -File)) {
        $leaf = $file.Name.ToLowerInvariant()
        if ($currentNames.ContainsKey($leaf)) { continue }

        if ($previousNames.ContainsKey($leaf)) {
            if ($IsDryRun) {
                Write-Host "[dry-run] would remove $($file.FullName) (no longer shipped by the kit)"
            } else {
                if ($BackupRoot) {
                    $null = New-KitBackup -Path $file.FullName -BackupRoot $BackupRoot -Stamp $BackupStamp `
                        -Note "rule removed: the kit no longer ships it"
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
        Write-Host "       If one of these is a kit rule from an older version, delete it by hand:"
        Write-Host "       it is loaded into every session as long as it sits there."
    }
}
