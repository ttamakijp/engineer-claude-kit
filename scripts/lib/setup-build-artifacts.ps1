#!/usr/bin/env pwsh
# setup-build-artifacts.ps1
# Configure BUILD_OUTPUT_DIR in ~/.claude/settings.json and project .claude/config/build-artifacts.yaml
# Called from apply-claude-kit.ps1 after deploying build-artifacts.yaml template.
# Sets up default build output directory at ~/build-artifacts/<project-name>/

param(
    [string]$ProjectRoot = $null
)

$ErrorActionPreference = 'Stop'

# If running in project mode, set up project-specific build artifact dir
if ($ProjectRoot -and (Test-Path $ProjectRoot)) {
    $projectName = Split-Path -Leaf $ProjectRoot
    $buildArtifactsDir = Join-Path (Join-Path $env:USERPROFILE "build-artifacts") $projectName

    Write-Host "[build-artifacts] Project: $projectName"
    Write-Host "[build-artifacts] Output directory: $buildArtifactsDir"

    # Ensure the directory exists
    if (-not (Test-Path $buildArtifactsDir)) {
        $null = New-Item -ItemType Directory -Force -Path $buildArtifactsDir
        Write-Host "[build-artifacts] Created output directory"
    }

    # Update settings.json with BUILD_OUTPUT_DIR environment variable
    $homeClaude = Join-Path $env:USERPROFILE ".claude"
    $settingsJsonPath = Join-Path $homeClaude "settings.json"

    if (Test-Path $settingsJsonPath) {
        try {
            $settings = Get-Content $settingsJsonPath -Raw | ConvertFrom-Json
            if (-not $settings.env) {
                $settings | Add-Member -MemberType NoteProperty -Name "env" -Value @{}
            }
            $settings.env.BUILD_OUTPUT_DIR = $buildArtifactsDir

            $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsJsonPath -Encoding UTF8
            Write-Host "[build-artifacts] Updated settings.json with BUILD_OUTPUT_DIR"
        } catch {
            Write-Warning "Could not update settings.json: $_"
            Write-Host "[hint] Set BUILD_OUTPUT_DIR manually in settings.json:"
            Write-Host "      `"env`": { `"BUILD_OUTPUT_DIR`": `"$buildArtifactsDir`" }"
        }
    }
}
