#requires -Version 5.1
# commit-subject.ps1
# Provides: Get-CommitSubject -- recover the commit subject line a shell command
#           would have produced, so commit-convention adherence can be measured.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0015 section E.
#
# Split out of rule-metrics.ps1 to keep that file clear of the 500-line
# file-granularity cap once ADR-0016's local-llm counters landed. This is a
# parser with its own failure modes and its own test cases, and it changes on a
# different cadence from the aggregation that consumes it: PR #87 reworked it
# four times (prose heredoc, -m scoped to the first invocation line, multi-line
# -m, -F <file> returning null) and took the metric from 83.3% to 98.5% precision.
#
# Dependencies: $script:RuleMetricsGitCommitPattern (rule-metrics.ps1), which the
# caller dot-sources first.
function Get-CommitSubject {
    # Extract the subject line from a shell command that runs git commit.
    # Returns $null when no subject is present in the command text (for example
    # 'git commit --amend --no-edit', or a message piped in from a file).
    param([string]$Command)

    if (-not $Command) { return $null }

    $lines = $Command -split "`r?`n"

    # Mark every line that sits inside a heredoc body. A report or an ADR written
    # through a heredoc routinely contains the words "git commit", and treating
    # such prose as an invocation produced subjects like
    # "| | #25 rationale | conclusion |".
    $inBody = @{}
    $openTag = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($openTag) {
            if ($lines[$i].Trim() -eq $openTag) { $openTag = $null } else { $inBody[$i] = $true }
            continue
        }
        if ($lines[$i] -match '<<-?\s*[''"]?([A-Za-z_][A-Za-z0-9_]*)[''"]?') { $openTag = $Matches[1] }
    }

    # Locate the first real invocation. Scoping everything below to THIS line
    # matters: searching the whole command for -m picked up an unrelated later
    # 'git commit -m "x"' and reported "x" as the subject of the first commit.
    $cmdLine = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($inBody.ContainsKey($i)) { continue }
        if ($lines[$i] -match $script:RuleMetricsGitCommitPattern) { $cmdLine = $i; break }
    }
    if ($cmdLine -lt 0) { return $null }
    $line = $lines[$cmdLine]

    # -m "subject" / -m 'subject'. The message may be multi-line, in which case
    # the closing quote is on a later line and the SUBJECT is the remainder of
    # this one. The previous newline-anchored pattern required the closing quote
    # on the same line, so every multi-line -m fell through to the heredoc branch
    # and reported a body paragraph instead.
    if ($line -match 'git\s+commit\b[^\r\n]*?\s-m\s+(["''])(.*)$') {
        $quote = $Matches[1]
        $rest = $Matches[2]
        $end = $rest.IndexOf($quote)
        $subject = if ($end -ge 0) { $rest.Substring(0, $end) } else { $rest }
        $subject = $subject.Trim()
        # '$(' only opens a command substitution; the real subject is the first
        # line of the heredoc it reads from, handled next.
        if ($subject -and $subject -notmatch '^\s*\$\(') { return $subject }
    }

    # Message fed through a heredoc on this line ('-F -' or -m "$(cat <<TAG").
    # Requiring '<<' here is the point: 'git commit -F <path>' and a bare '-F -'
    # fed by a pipe carry no subject in the command text, and guessing from the
    # next line returned the next shell command ("git log --oneline -1").
    if ($line -match '<<') {
        for ($j = $cmdLine + 1; $j -lt $lines.Count; $j++) {
            if ($lines[$j].Trim()) { return $lines[$j].Trim() }
        }
    }
    return $null
}
