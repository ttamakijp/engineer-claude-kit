#requires -Version 5.1
# config-deploy.ps1
# Provides: Install-KitWorkSchedule / Install-KitLocalLlmConfig - deploy the
#           kit's config/ payloads into the Global target, returning the paths.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0017.
#
# Extracted from apply-claude-kit.ps1 to keep that script inside the kit's own
# 500-line file-granularity cap (same reason as models-config.ps1 and
# rules-deploy.ps1). Both payloads are Global-only: they describe the machine,
# not a project, and a per-project copy would be a second source of truth.
#
# Dependencies, dot-sourced by the caller before this file:
#   Read-Utf8NoBom / Write-Utf8NoBom (encoding-helper.ps1)

function Install-KitWorkSchedule {
    # config/work-schedule.yaml powers the work-end-reminder rule (ADR-0006). A
    # single global copy covers every project. Preserved when it already exists
    # so an edited schedule is never clobbered (same policy as the root config
    # files).
    param(
        [Parameter(Mandatory)][string]$KitRoot,
        [Parameter(Mandatory)][string]$HomeClaude,
        [switch]$IsDryRun
    )

    $applied = @()
    $source = Join-Path (Join-Path $KitRoot "config") "work-schedule.yaml"
    $dest = Join-Path $HomeClaude "work-schedule.yaml"
    if ((Test-Path $source) -and -not (Test-Path $dest)) {
        if ($IsDryRun) {
            Write-Host "[dry-run] $source -> $dest"
        } else {
            # Plain YAML, no role placeholders: verbatim UTF-8 (no BOM) copy.
            Write-Utf8NoBom -Path $dest -Content (Read-Utf8NoBom -Path $source)
            Write-Host "[apply] $source -> $dest"
            Write-Host "[hint] To enable work-end reminder, edit ~/.claude/work-schedule.yaml with your work schedule."
        }
        $applied += $dest
    } elseif (Test-Path $dest) {
        Write-Host "[skip] $dest already exists (preserving user customization)"
    }
    return $applied
}

function Install-KitLocalLlmConfig {
    # Deploy the local-llm delegation config and the system prompts it names.
    #
    # ADR-0017. CLAUDE.md used to point at ~/.claude-kit/config/, i.e. at the
    # kit checkout. On a machine where that path is a working clone (or a
    # symlink to one), the instruction a session follows then changes with
    # whatever branch happens to be checked out. Deploying a copy under
    # ~/.claude/ makes runtime behaviour depend on the last apply instead, the
    # same model as every other kit artifact, and puts these files under the
    # applied-files marker.
    #
    # Overwritten rather than preserved: this is generated kit content that
    # names MCP tools and their status, not a user-authored schedule. The
    # local-llm toggle that a user does edit is 'enabled', and the file is
    # backed up first whenever the deployed copy differs.
    param(
        [Parameter(Mandatory)][string]$KitRoot,
        [Parameter(Mandatory)][string]$HomeClaude,
        [string]$BackupRoot,
        [string]$BackupStamp,
        [switch]$IsDryRun
    )

    $applied = @()
    $kitConfig = Join-Path $KitRoot "config"
    $source = Join-Path $kitConfig "local-llm-delegation.yaml"
    if (-not (Test-Path $source)) {
        Write-Warning "local-llm-delegation.yaml not found at: $source"
        return $applied
    }

    $destDir = Join-Path $HomeClaude "config"
    $applied += Copy-KitConfigFile -Source $source -Dest (Join-Path $destDir "local-llm-delegation.yaml") `
        -BackupRoot $BackupRoot -BackupStamp $BackupStamp -IsDryRun:$IsDryRun

    # The prompts the config names. 'system_prompt_ref' is relative to the
    # directory holding the yaml, so config/local-llm/<name>.md in the kit has
    # to land at <target>/config/local-llm/<name>.md for those refs to resolve.
    $promptDir = Join-Path $kitConfig "local-llm"
    if (Test-Path $promptDir) {
        $destPromptDir = Join-Path $destDir "local-llm"
        foreach ($prompt in (Get-ChildItem -LiteralPath $promptDir -Filter "*.md" -File)) {
            $applied += Copy-KitConfigFile -Source $prompt.FullName `
                -Dest (Join-Path $destPromptDir $prompt.Name) `
                -BackupRoot $BackupRoot -BackupStamp $BackupStamp -IsDryRun:$IsDryRun
        }
    }
    return $applied
}

function Copy-KitConfigFile {
    # Verbatim UTF-8 (no BOM) copy with a backup of a diverging destination.
    # No role placeholders appear in config payloads, so Copy-Template's
    # substitution pass is not wanted here.
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Dest,
        [string]$BackupRoot,
        [string]$BackupStamp,
        [switch]$IsDryRun
    )

    $content = Read-Utf8NoBom -Path $Source
    if ($IsDryRun) {
        Write-Host "[dry-run] $Source -> $Dest"
        return $Dest
    }

    $parent = Split-Path -Parent $Dest
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    # Config payloads are generated, so an existing file usually matches byte
    # for byte and no backup is taken; only a diverging copy is worth keeping.
    if ($BackupRoot -and (Test-Path -LiteralPath $Dest)) {
        if ((Read-Utf8NoBom -Path $Dest) -ne $content) {
            $null = New-KitBackup -Path $Dest -BackupRoot $BackupRoot -Stamp $BackupStamp `
                -Note "config content differed from the kit copy; overwritten by apply"
        }
    }
    Write-Utf8NoBom -Path $Dest -Content $content
    Write-Host "[apply] $Source -> $Dest"
    return $Dest
}
