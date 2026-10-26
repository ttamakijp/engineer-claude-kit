#requires -Version 5.1
# baseline-io.ps1
# Provides: Read-RuleMetricsBaseline / Write-RuleMetricsBaseline -- persistence
#           for the rule-firing baseline that snapshots are compared against.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0015 section E.
#
# Split out of rule-metrics.ps1, which had grown past the kit's own 500-line
# file-granularity cap (528 lines) once ADR-0015 item 4 landed. Persistence is a
# separate concern from aggregation, and the baseline schema changes on its own
# cadence as new metrics are added.
#
# Dependencies, dot-sourced by the caller before this file:
#   Write-Utf8NoBom (encoding-helper.ps1)

function Read-RuleMetricsBaseline {
    # Load the stored baseline. Returns $null when absent or unreadable so the
    # report simply omits deltas instead of failing the run.
    param([string]$Path)
    if (-not $Path) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-RuleMetricsBaseline {
    # Persist the current rates as the baseline for later comparison. Only the
    # three rates plus provenance are stored; the full metric object is not, so a
    # later schema change cannot make an old baseline unreadable.
    #
    # Two files are written: $Path is the active comparison target (overwritten
    # each time), and a dated sibling is kept as an archive. ADR-0015 compares
    # three snapshots -- before distribution, after distribution, after reduction
    # -- to separate the effect of deploying rules from the effect of trimming
    # them, which a single overwritten file cannot support.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$RuleMetrics,
        [string]$DateStr,
        [int]$WindowDays = 7,
        [switch]$NoArchive
    )
    if (-not $DateStr) { $DateStr = (Get-Date).ToString('yyyy-MM-dd') }
    $payload = [ordered]@{
        RecordedOn          = $DateStr
        WindowDays          = $WindowDays
        PlanFirstRate       = $RuleMetrics.PlanFirstRate
        PlanFirstStrictRate = $RuleMetrics.PlanFirstStrictRate
        PlanFirstEligible   = $RuleMetrics.PlanFirstEligible
        DelegationRate      = $RuleMetrics.DelegationRate
        DelegationEligible  = $RuleMetrics.DelegationEligible
        CommitRate          = $RuleMetrics.CommitRate
        CommitExtracted     = $RuleMetrics.CommitExtracted
    }
    # ADR-0016 decision C, appended after the existing keys so an older reader
    # that indexes by name is unaffected and compare-snapshots.ps1 can treat a
    # missing key as "this snapshot predates local-llm" rather than as zero.
    # Written only when the counters are present, so a caller that did not run
    # Add-RuleMetricsMcpStats produces a byte-identical baseline.
    if ($null -ne $RuleMetrics.DelegationLocalLlm) {
        $payload['DelegationLocalLlm'] = [int]$RuleMetrics.DelegationLocalLlm
        $payload['DelegationLocalLlmProbes'] = [int]$RuleMetrics.DelegationLocalLlmProbes
        $payload['DelegationLocalLlmByTool'] = $RuleMetrics.DelegationLocalLlmByTool
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $json = $payload | ConvertTo-Json -Depth 3
    Write-Utf8NoBom -Path $Path -Content $json

    if (-not $NoArchive) {
        # <name>-<date>.json beside the active baseline. Re-running on the same
        # day replaces that day's archive, which keeps one entry per day rather
        # than one per invocation.
        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $ext = [System.IO.Path]::GetExtension($Path)
        $archiveName = "$leaf-$DateStr$ext"
        $archive = if ($dir) { Join-Path $dir $archiveName } else { $archiveName }
        if ($archive -ne $Path) { Write-Utf8NoBom -Path $archive -Content $json }
    }
    return $Path
}

