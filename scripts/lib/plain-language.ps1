#requires -Version 5.1
# plain-language.ps1
# Shared helper: render a plain-language (Japanese) blockquote hint for a usage
# finding category, to be appended after the technical metric in the insights
# report. Provides: Get-PlainLanguageHint, Format-KitBehindBanner.
#
# Why the hint text lives in an external JSON, not inline here (see ADR-0014):
#   - This kit enforces ASCII-only PowerShell sources (no Japanese literals in
#     .ps1). PS 5.1 also parses BOM-less .ps1 files with the system ANSI codepage
#     (CP932 on Japanese Windows), so inline Japanese would mojibake at parse time.
#   - Routing the Japanese through plain-language-hints.json + Read-Utf8NoBom (a
#     forced, codepage-independent UTF-8 decode) keeps this script ASCII-only and
#     renders correctly on every PowerShell version. Read-Utf8NoBom is supplied by
#     encoding-helper.ps1, which usage-insights.ps1 dot-sources before this file.
#
# ASCII only (no Japanese in code, comments, or strings). See ADR-0014.

function Get-PlainLanguageHint {
    # Return the plain-language hint for $Category as a Markdown blockquote block:
    # a leading blank line, then one "> <sentence>" line per mapped sentence. An
    # unknown category, a missing data file, or a malformed file yields '' so the
    # caller appends nothing (the technical metric is always preserved separately).
    # $Metrics (optional) supplies values for "{key}" placeholders inside the hint
    # sentences (e.g. "{Behind}" -> $Metrics.Behind), substituted before rendering.
    param(
        [Parameter(Mandatory)][string]$Category,
        [hashtable]$Metrics,
        [string]$HintsFile
    )
    if (-not $HintsFile) {
        $HintsFile = Join-Path $PSScriptRoot 'plain-language-hints.json'
    }
    if (-not (Test-Path -LiteralPath $HintsFile)) { return '' }

    $map = $null
    try { $map = (Read-Utf8NoBom -Path $HintsFile) | ConvertFrom-Json } catch { return '' }
    if (-not $map) { return '' }

    $sentences = $map.$Category
    if (-not $sentences) { return '' }

    $out = @('')
    foreach ($s in $sentences) {
        $line = [string]$s
        if ($Metrics) {
            foreach ($k in $Metrics.Keys) { $line = $line.Replace('{' + $k + '}', [string]$Metrics[$k]) }
        }
        $out += "> $line"
    }
    return ($out -join "`n")
}

function Format-KitBehindBanner {
    # Render the "kit update available" banner for a positive behind count, or ''
    # when the checkout is up to date / unknown. Combines an ASCII technical line
    # with the Japanese plain-language blockquote (Get-PlainLanguageHint). See
    # ADR-0014 (G6h). The leading "kit-behind" count is supplied by the caller
    # (usage-insights.ps1 -> Test-KitBehind), keeping this renderer side-effect free.
    param([Parameter(Mandatory)][int]$KitBehind)
    if ($KitBehind -le 0) { return '' }
    $cw = if ($KitBehind -eq 1) { 'commit' } else { 'commits' }
    $lines = @(
        "## Kit update available ($KitBehind $cw behind)"
        ''
        "- Kit checkout is $KitBehind $cw behind origin"
        '- Apply: `/apply --update` or `pwsh apply-claude-kit.ps1 -Global -Update`'
        (Get-PlainLanguageHint -Category 'KitBehind' -Metrics @{ Behind = $KitBehind })
    )
    return ($lines -join "`n")
}
