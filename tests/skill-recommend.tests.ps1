# skill-recommend.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Covers lib/skill-recommend.ps1 (ADR-0015 section C), which took over the
# project-type detection and skill suggestion that project-skill-recommend.md
# used to ask Claude to redo on the first turn of every session.
#
# Every path is injectable, so the real config and the real ~/.claude/skills are
# never consulted.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$repoRoot = Split-Path -Parent $here
. (Join-Path (Join-Path (Join-Path $repoRoot "scripts") "lib") "skill-recommend.ps1")
$RealConfig = Join-Path (Join-Path $repoRoot "config") "recommended-skills.yaml"

function New-RecFixture {
    # project root + a fake global skills library + a fake project skills dir
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("rec-test-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path (Join-Path $root "project") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $root "skills") | Out-Null
    return $root
}

function Add-GlobalSkill {
    param([string]$Fixture, [string]$Name)
    New-Item -ItemType Directory -Force -Path (Join-Path (Join-Path $Fixture "skills") $Name) | Out-Null
}

Describe "Read-SkillRecommendConfig" {
    It "returns empty for a missing file" {
        $types = Read-SkillRecommendConfig -Path (Join-Path $env:TEMP "no-such-rec-config.yaml")
        @($types.Keys).Count | Should Be 0
    }
    It "parses the shipped config" {
        $types = Read-SkillRecommendConfig -Path $RealConfig
        $types.ContainsKey('android') | Should Be $true
        $types['android'].Detect -contains 'gradlew' | Should Be $true
        $types['android'].Recommend -contains 'android-build' | Should Be $true
    }
    It "records an empty recommend list as empty" {
        $types = Read-SkillRecommendConfig -Path $RealConfig
        # rust ships with "recommend: []" (no skill implemented yet).
        @($types['rust'].Recommend).Count | Should Be 0
        @($types['rust'].Detect).Count | Should BeGreaterThan 0
    }
    It "strips quotes and trailing comments from list items" {
        $f = Join-Path $env:TEMP ("rec-cfg-" + [System.Guid]::NewGuid().ToString("N") + ".yaml")
        @(
            'project_types:',
            '  demo:',
            '    detect:',
            '      - "marker.txt"   # inline comment',
            '    recommend:',
            "      - demo-skill"
        ) | Set-Content -LiteralPath $f
        $types = Read-SkillRecommendConfig -Path $f
        $types['demo'].Detect[0] | Should Be 'marker.txt'
        $types['demo'].Recommend[0] | Should Be 'demo-skill'
        Remove-Item -Force $f
    }
}

Describe "Test-ProjectType" {
    It "matches a literal file at the project root" {
        $fx = New-RecFixture
        $proj = Join-Path $fx "project"
        Set-Content -LiteralPath (Join-Path $proj "gradlew") -Value "x"
        (Test-ProjectType -ProjectRoot $proj -DetectPatterns @('gradlew')) | Should Be $true
        Remove-Item -Recurse -Force $fx
    }
    It "matches a glob pattern" {
        $fx = New-RecFixture
        $proj = Join-Path $fx "project"
        New-Item -ItemType Directory -Force -Path (Join-Path $proj "App.xcodeproj") | Out-Null
        (Test-ProjectType -ProjectRoot $proj -DetectPatterns @('*.xcodeproj')) | Should Be $true
        Remove-Item -Recurse -Force $fx
    }
    It "does not match a file nested below the root" {
        # A package.json inside node_modules must not make this a Node project.
        $fx = New-RecFixture
        $proj = Join-Path $fx "project"
        $nested = Join-Path $proj "node_modules"
        New-Item -ItemType Directory -Force -Path $nested | Out-Null
        Set-Content -LiteralPath (Join-Path $nested "package.json") -Value "{}"
        (Test-ProjectType -ProjectRoot $proj -DetectPatterns @('package.json')) | Should Be $false
        Remove-Item -Recurse -Force $fx
    }
    It "returns false for an empty pattern list" {
        $fx = New-RecFixture
        (Test-ProjectType -ProjectRoot (Join-Path $fx "project") -DetectPatterns @()) | Should Be $false
        Remove-Item -Recurse -Force $fx
    }
}

Describe "Get-RecommendedSkills" {
    It "suggests a skill that exists globally and not in the project" {
        $fx = New-RecFixture
        $proj = Join-Path $fx "project"
        Set-Content -LiteralPath (Join-Path $proj "gradlew") -Value "x"
        Add-GlobalSkill -Fixture $fx -Name "android-build"
        $rec = @(Get-RecommendedSkills -ProjectRoot $proj -ConfigPath $RealConfig `
            -GlobalSkillsDir (Join-Path $fx "skills"))
        $rec.Count | Should Be 1
        $rec[0].Skill | Should Be 'android-build'
        $rec[0].Type | Should Be 'android'
        Remove-Item -Recurse -Force $fx
    }
    It "says nothing when the skill is missing from the global library" {
        $fx = New-RecFixture
        $proj = Join-Path $fx "project"
        Set-Content -LiteralPath (Join-Path $proj "gradlew") -Value "x"
        $rec = @(Get-RecommendedSkills -ProjectRoot $proj -ConfigPath $RealConfig `
            -GlobalSkillsDir (Join-Path $fx "skills"))
        $rec.Count | Should Be 0
        Remove-Item -Recurse -Force $fx
    }
    It "still reports a skill the project already has (apply deploys them all)" {
        $fx = New-RecFixture
        $proj = Join-Path $fx "project"
        Set-Content -LiteralPath (Join-Path $proj "gradlew") -Value "x"
        Add-GlobalSkill -Fixture $fx -Name "android-build"
        New-Item -ItemType Directory -Force -Path (Join-Path (Join-Path (Join-Path $proj ".claude") "skills") "android-build") | Out-Null
        $rec = @(Get-RecommendedSkills -ProjectRoot $proj -ConfigPath $RealConfig `
            -GlobalSkillsDir (Join-Path $fx "skills"))
        $rec.Count | Should Be 1
        Remove-Item -Recurse -Force $fx
    }
    It "drops an already-present skill under -OnlyMissing" {
        $fx = New-RecFixture
        $proj = Join-Path $fx "project"
        Set-Content -LiteralPath (Join-Path $proj "gradlew") -Value "x"
        Add-GlobalSkill -Fixture $fx -Name "android-build"
        New-Item -ItemType Directory -Force -Path (Join-Path (Join-Path (Join-Path $proj ".claude") "skills") "android-build") | Out-Null
        $rec = @(Get-RecommendedSkills -ProjectRoot $proj -ConfigPath $RealConfig `
            -GlobalSkillsDir (Join-Path $fx "skills") -OnlyMissing)
        $rec.Count | Should Be 0
        Remove-Item -Recurse -Force $fx
    }
    It "says nothing for a project that matches no type" {
        $fx = New-RecFixture
        Add-GlobalSkill -Fixture $fx -Name "android-build"
        $rec = @(Get-RecommendedSkills -ProjectRoot (Join-Path $fx "project") -ConfigPath $RealConfig `
            -GlobalSkillsDir (Join-Path $fx "skills"))
        $rec.Count | Should Be 0
        Remove-Item -Recurse -Force $fx
    }
    It "reports every matching type for a hybrid project" {
        $fx = New-RecFixture
        $proj = Join-Path $fx "project"
        Set-Content -LiteralPath (Join-Path $proj "package.json") -Value "{}"
        Set-Content -LiteralPath (Join-Path $proj "pyproject.toml") -Value "x"
        Add-GlobalSkill -Fixture $fx -Name "web-test"
        Add-GlobalSkill -Fixture $fx -Name "python-test"
        $rec = @(Get-RecommendedSkills -ProjectRoot $proj -ConfigPath $RealConfig `
            -GlobalSkillsDir (Join-Path $fx "skills"))
        $rec.Count | Should Be 2
        ($rec | ForEach-Object { $_.Skill } | Sort-Object) -join ',' | Should Be 'python-test,web-test'
        Remove-Item -Recurse -Force $fx
    }
    It "ignores a type whose recommend list is empty" {
        $fx = New-RecFixture
        $proj = Join-Path $fx "project"
        Set-Content -LiteralPath (Join-Path $proj "Cargo.toml") -Value "x"
        $rec = @(Get-RecommendedSkills -ProjectRoot $proj -ConfigPath $RealConfig `
            -GlobalSkillsDir (Join-Path $fx "skills"))
        $rec.Count | Should Be 0
        Remove-Item -Recurse -Force $fx
    }
}

Describe "Write-SkillRecommendation" {
    It "prints nothing when there is nothing to suggest" {
        $out = Write-SkillRecommendation -Recommendations @() 6>&1
        @($out).Count | Should Be 0
    }
    It "prints the detected type and the relevant skills" {
        $items = @([PSCustomObject]@{ Type = 'android'; Skill = 'android-build' })
        $out = (Write-SkillRecommendation -Recommendations $items 6>&1) -join "`n"
        $out | Should Match 'android-build'
        $out | Should Match 'Detected project type'
    }
    # Regression: a function returning an empty @() emits nothing, so the call
    # site's argument arrives as $null and @($null) is a one-element array. That
    # printed a hint with blank fields on every real apply run.
    It "prints nothing when the argument is null" {
        $out = Write-SkillRecommendation -Recommendations $null 6>&1
        @($out).Count | Should Be 0
    }
}
