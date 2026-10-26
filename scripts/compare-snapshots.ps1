#requires -Version 5.1
# compare-snapshots.ps1
# Provides: a side-by-side diff of two rule-metrics baseline archives, with the
#           changes that matter highlighted.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0015 / ADR-0016.
#
# Why a separate script rather than a -DiffFrom switch on usage-insights.ps1:
# usage-insights.ps1 sits at 486 lines against the kit's 500-line
# file-granularity cap, and comparing archives needs no transcript scan at all.
# Keeping it separate also means a comparison can be run long after the fact,
# against any two archives, without re-reading ~/.claude/projects.
#
# Usage:
#   compare-snapshots.ps1                           # newest two archives
#   compare-snapshots.ps1 -From <path> -To <path>    # explicit
#   compare-snapshots.ps1 -SuccessUsdPerMonth 20     # pass/fail on cost saving
#
# The noise floor measured in ADR-0015 is about +/-2 pt for the all-projects
# aggregate: a window sliding by one day moved plan-first 2.2 pt on its own. A
# delta below that is reported as "within noise", not as a change.

[CmdletBinding()]
param(
    [string]$From,
    [string]$To,
    [string]$InsightsDir,

    # Monthly saving (USD) at or above which the local-llm rollout counts as a
    # success. ADR-0016's goal; 0 disables the verdict.
    [double]$SuccessUsdPerMonth = 20.0,

    # Turns per week assumed when converting a per-turn cost delta to a monthly
    # figure. Defaults to the -To snapshot's own turn count when it is known.
    [int]$TurnsPerWeek = 0
)

$ErrorActionPreference = 'Stop'
$NoiseFloorPt = 2.0

if (-not $env:USERPROFILE) { $env:USERPROFILE = $env:HOME }
if (-not $InsightsDir) {
    $InsightsDir = Join-Path (Join-Path $env:USERPROFILE ".claude") "insights"
}

function Get-ArchiveList {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return @() }
    # rule-metrics-baseline-<date>.json only; the unsuffixed file is the active
    # comparison target and duplicates whichever archive was written last.
    return @(Get-ChildItem -LiteralPath $Dir -Filter "rule-metrics-baseline-*.json" -File |
        Sort-Object Name)
}

function Read-Baseline {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "baseline not found: $Path" }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "baseline is empty: $Path" }
    return ($raw | ConvertFrom-Json)
}

function Get-ReportCost {
    # Pull "Est. cost: USD <n>" and the turn count out of the dated report that
    # accompanies a baseline. Returns $null when the report is absent, so the
    # comparison still works from baselines alone.
    param([string]$Dir, [string]$DateStr)
    $report = Join-Path $Dir "$DateStr-weekly.md"
    if (-not (Test-Path -LiteralPath $report)) { return $null }
    $text = Get-Content -LiteralPath $report -Raw -Encoding UTF8
    $cost = $null; $turns = $null
    if ($text -match 'Est\. cost: USD ([0-9.]+)') { $cost = [double]$Matches[1] }
    if ($text -match 'Assistant turns: (\d+)') { $turns = [int]$Matches[1] }
    if ($null -eq $cost) { return $null }
    return [ordered]@{ Cost = $cost; Turns = $turns }
}

function Format-Delta {
    param([double]$From, [double]$To, [string]$Unit = 'pt')
    $d = [math]::Round($To - $From, 1)
    $sign = if ($d -gt 0) { '+' } else { '' }
    $note = ''
    if ($Unit -eq 'pt' -and [math]::Abs($d) -lt $NoiseFloorPt) { $note = '  (within noise)' }
    return "$sign$d $Unit$note"
}

# --- resolve the two archives ---

if (-not $From -or -not $To) {
    $archives = Get-ArchiveList -Dir $InsightsDir
    if ($archives.Count -lt 2) {
        Write-Host "Need at least two baseline archives in $InsightsDir (found $($archives.Count))."
        Write-Host "Take another snapshot first:"
        Write-Host "  powershell -NoProfile -File scripts/usage-insights.ps1 -Window Weekly -WriteBaseline"
        exit 1
    }
    if (-not $From) { $From = $archives[-2].FullName }
    if (-not $To)   { $To   = $archives[-1].FullName }
}

$a = Read-Baseline -Path $From
$b = Read-Baseline -Path $To

Write-Host ""
Write-Host "=== snapshot comparison ==="
Write-Host "  from: $($a.RecordedOn)  ($(Split-Path -Leaf $From))"
Write-Host "  to  : $($b.RecordedOn)  ($(Split-Path -Leaf $To))"
Write-Host ""

# --- rule adherence ---

Write-Host "Rule adherence"
$rows = @(
    @{ Label = 'plan-first';        Rate = 'PlanFirstRate';       Elig = 'PlanFirstEligible' },
    @{ Label = 'plan-first strict'; Rate = 'PlanFirstStrictRate'; Elig = 'PlanFirstEligible' },
    @{ Label = 'delegation';        Rate = 'DelegationRate';      Elig = 'DelegationEligible' },
    @{ Label = 'commit-convention'; Rate = 'CommitRate';          Elig = 'CommitExtracted' }
)
foreach ($row in $rows) {
    $fromRate = [double]$a.($row.Rate)
    $toRate   = [double]$b.($row.Rate)
    $fromElig = [int]$a.($row.Elig)
    $toElig   = [int]$b.($row.Elig)
    $delta = Format-Delta -From $fromRate -To $toRate
    Write-Host ("  {0,-18} {1,6}% -> {2,6}%   {3,-22} eligible {4} -> {5}" -f `
        $row.Label, $fromRate, $toRate, $delta, $fromElig, $toElig)
    # A denominator that moves by more than half tells you the workload changed,
    # which is the confound ADR-0015 kept running into.
    if ($fromElig -gt 0) {
        $ratio = [double]$toElig / [double]$fromElig
        if ($ratio -lt 0.5 -or $ratio -gt 2.0) {
            Write-Host ("  {0,-18} ^ eligible changed {1}x -- the rate above compares different workloads" -f '', [math]::Round($ratio, 2))
        }
    }
}
Write-Host ""

# --- local-llm delegation (ADR-0016) ---

# A baseline written before ADR-0016 has no local-llm keys at all. That is not
# the same as zero: the old aggregation could not see mcp__* calls, so a missing
# key means "unmeasured" and must not be rendered as a drop to 0.
$hasA = ($null -ne $a.PSObject.Properties['DelegationLocalLlm'])
$hasB = ($null -ne $b.PSObject.Properties['DelegationLocalLlm'])
if ($hasA -or $hasB) {
    Write-Host "local-llm delegation"
    if (-not $hasA) {
        Write-Host "  from: unmeasured (snapshot predates ADR-0016; mcp__* calls were not counted)"
        Write-Host ("  to  : {0} work call(s), {1} health probe(s)" -f [int]$b.DelegationLocalLlm, [int]$b.DelegationLocalLlmProbes)
        Write-Host "  No delta can be computed. This pair establishes the first measured point."
    } elseif (-not $hasB) {
        Write-Host "  to: unmeasured. Re-take the newer snapshot with a current usage-insights.ps1."
    } else {
        $callsA = [int]$a.DelegationLocalLlm
        $callsB = [int]$b.DelegationLocalLlm
        Write-Host ("  work calls   {0,6} -> {1,6}   {2}" -f $callsA, $callsB, (Format-Delta -From $callsA -To $callsB -Unit 'calls'))
        Write-Host ("  health probes{0,6} -> {1,6}" -f [int]$a.DelegationLocalLlmProbes, [int]$b.DelegationLocalLlmProbes)
        # The handler mix is the only honest way to read displacement: a rise in
        # Local that is not matched by a fall in Opus / Haiku is extra work, not
        # moved work. ADR-0016 unresolved question 3.
        $keys = @('Local', 'Haiku', 'Opus', 'Sonnet', 'Unknown')
        $anyMix = $false
        foreach ($k in $keys) {
            $va = if ($a.DelegationDisplaced) { [int]$a.DelegationDisplaced.$k } else { 0 }
            $vb = if ($b.DelegationDisplaced) { [int]$b.DelegationDisplaced.$k } else { 0 }
            if ($va -eq 0 -and $vb -eq 0) { continue }
            if (-not $anyMix) { Write-Host "  light-work handler mix"; $anyMix = $true }
            Write-Host ("    {0,-8} {1,6} -> {2,6}   {3}" -f $k, $va, $vb, (Format-Delta -From $va -To $vb -Unit 'events'))
        }
        if ($anyMix) {
            Write-Host "  Work moved only if Local rose AND Opus / Haiku fell by a similar amount."
            Write-Host "  Local rising on its own is additional delegation, not displaced cost."
        }
    }
    Write-Host ""
}

# --- cost ---

$costA = Get-ReportCost -Dir $InsightsDir -DateStr $a.RecordedOn
$costB = Get-ReportCost -Dir $InsightsDir -DateStr $b.RecordedOn

if ($null -eq $costA -or $null -eq $costB) {
    Write-Host "Cost: skipped (a dated weekly report is missing for one of the snapshots)"
    Write-Host ""
} else {
    $perA = if ($costA.Turns) { $costA.Cost / $costA.Turns } else { 0 }
    $perB = if ($costB.Turns) { $costB.Cost / $costB.Turns } else { 0 }
    Write-Host "Cost (concept pricing, relative comparison only)"
    Write-Host ("  total      USD {0,10} -> {1,10}   {2}" -f `
        [math]::Round($costA.Cost, 2), [math]::Round($costB.Cost, 2), (Format-Delta -From $costA.Cost -To $costB.Cost -Unit 'USD'))
    Write-Host ("  turns      {0,14} -> {1,10}" -f $costA.Turns, $costB.Turns)
    Write-Host ("  per turn   USD {0,10} -> {1,10}   {2}" -f `
        [math]::Round($perA, 4), [math]::Round($perB, 4), (Format-Delta -From $perA -To $perB -Unit 'USD'))
    Write-Host ""
    Write-Host "  The total tracks how much work was done. Read per-turn for efficiency:"
    Write-Host "  in ADR-0015 a -85% total was -33% once normalised by turn count."
    Write-Host ""

    # --- verdict ---
    if ($SuccessUsdPerMonth -gt 0) {
        $weekTurns = if ($TurnsPerWeek -gt 0) { $TurnsPerWeek } else { $costB.Turns }
        if ($weekTurns -gt 0) {
            $perTurnSaving = $perA - $perB
            $monthly = $perTurnSaving * $weekTurns * (30.0 / 7.0)
            Write-Host "Verdict"
            Write-Host ("  per-turn saving    USD {0}" -f [math]::Round($perTurnSaving, 4))
            Write-Host ("  assumed weekly turns {0}" -f $weekTurns)
            Write-Host ("  projected monthly  USD {0}   (threshold {1})" -f [math]::Round($monthly, 2), $SuccessUsdPerMonth)

            # A turn count that moved by more than 2x means the two windows did
            # different amounts of different work, and the per-turn delta carries
            # whatever else changed with it. Handing back a confident PASS from
            # that is worse than refusing: on the 10-16 -> 10-27 pair it projects
            # USD 1,736/month, which is an artefact of the workload shift and
            # nothing to do with any rollout.
            $turnRatio = if ($costA.Turns -gt 0) { [double]$costB.Turns / [double]$costA.Turns } else { 0 }
            if ($turnRatio -lt 0.5 -or $turnRatio -gt 2.0) {
                Write-Host ("  => UNRELIABLE: turn count moved {0}x between the windows." -f [math]::Round($turnRatio, 2))
                Write-Host "     The per-turn delta carries the workload change with it. Compare"
                Write-Host "     windows of similar size, or narrow both to one project first."
            } elseif ($monthly -ge $SuccessUsdPerMonth) {
                Write-Host "  => PASS: the projected monthly saving reaches the threshold."
            } else {
                Write-Host "  => NOT YET: below the threshold on this comparison."
            }
            Write-Host "  Projection only. It assumes the next month looks like the -to window,"
            Write-Host "  and the prices are the concept figures in scripts/pricing.psd1."
            Write-Host ""
        }
    }
}

Write-Host "Reminder: compare the 'Activity by project' tables in both reports before"
Write-Host "concluding anything. A shift in which repository dominated the window has"
Write-Host "explained every large swing so far (ADR-0015)."
Write-Host ""
