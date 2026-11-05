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
#   Remove-OrphanedKitFiles          (orphan-cleanup.ps1)

function Update-KitRulesBuild {
    # Rebuild dist/.claude/rules/ from source/rules/ before deploying.
    # build-rules.ps1 compiles source/rules/*.md into dist/.claude/rules/<id>.md
    # with audience filtering, and prunes dist outputs it did not produce.
    #
    # The build used to be skipped when no source file was newer than the newest
    # dist file. An mtime comparison cannot see a rule that STOPPED being built:
    # deleting source/rules/common/<x>.md, or dropping 'claude' from its audience
    # in a commit older than the dist copy, leaves every surviving source file
    # untouched, so the newest source stayed older than dist, the build was
    # skipped, and the orphaned dist copy was deployed again. ADR-0015 hit that
    # with project-skill-recommend.md. Six small reads and writes do not justify
    # a staleness heuristic that is blind in exactly the case that matters.
    param(
        [Parameter(Mandatory)][string]$KitRoot,
        [switch]$IsDryRun
    )

    $buildScript = Join-Path (Join-Path $KitRoot "scripts") "build-rules.ps1"

    if ($IsDryRun) {
        Write-Host "[dry-run] would build rules from source/rules/"
        return
    }
    if (-not (Test-Path $buildScript)) {
        Write-Warning "build-rules.ps1 not found at: $buildScript"
        return
    }
    Write-Host "[rules] building from source/rules/"
    # Switch cwd to the kit root while invoking build-rules.ps1, then restore.
    Push-Location $KitRoot
    try {
        # Per-rule [build] lines would drown out apply's own output, but a stale
        # removal must stay visible: it is the one thing here that deletes a file
        # the previous apply deployed.
        # 6>&1 is required: build-rules.ps1 reports through Write-Host, which goes
        # to the information stream, and "2>&1" alone leaves it to pass straight
        # through to the host -- capturing nothing and filtering nothing.
        $buildOutput = & $buildScript 6>&1 2>&1
        foreach ($line in $buildOutput) {
            if ("$line" -match '^\[clean\]') { Write-Host "$line" }
        }
    } finally {
        Pop-Location
    }
}

function Install-KitRules {
    # Deploy every built rule into $TargetRulesDir. Returns the deployed paths so
    # the caller can record them in the applied-files marker.
    # -PreviousAppliedFiles is the applied_files list from the marker of the LAST
    # run, used to remove a rule the kit has stopped shipping. See
    # lib/orphan-cleanup.ps1 for why deploy cannot be additive only.
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
    Update-KitRulesBuild -KitRoot $KitRoot -IsDryRun:$IsDryRun

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

    Remove-OrphanedKitFiles -TargetDir $TargetRulesDir -CurrentApplied $applied `
        -PathSegment "rules" -Kind "rule" -PreviousAppliedFiles $PreviousAppliedFiles `
        -BackupRoot $BackupRoot -BackupStamp $BackupStamp -IsDryRun:$IsDryRun

    return $applied
}
