---
status: Accepted
date: 2026-06-11
deciders: [Tetsuya]
tags: [insights, observability, cost, cache, scheduled-task, ux]
---

# ADR-0014: Usage insights 機能

> 本 ADR は G6f PR で起票され、同 PR で実装まで含めて Accepted とする。

## Context

Kit user (engineer) は日常使いの中で、以下の改善余地に気づきにくい:

- Model 使い方の非効率 (Opus 多用、Haiku 委譲未発火 等)
- Cache 効率低下 (cold miss が多い = turn 間隔が空きすぎて 5m TTL を踏み越える)
- Token 浪費 (議論で終わる、短 turn 連続、commit 無しの高出力 turn)
- Stuck session の見落とし (異常に長い turn 間 gap)

観測値は `~/.claude/projects/*.jsonl` (Claude Code transcript) に蓄積されているが、
手動分析は現実的でない。`cost-observe-bedrock.ps1` (ADR-0002 portage) は AWS Cost
Explorer 経由の請求額しか見ないため、model / cache / 委譲の **内訳** までは追えない。

## Decision

週次 + 日次の **scheduled-task で自動解析**し、結果を `~/.claude/insights/` に Markdown
レポートとして蓄積する。Claude Code セッション開始時に CLAUDE.md instruction で
**passive に user へ提示** (未 ack 時のみ Key findings 1 行サマリ + 選択肢)。

### 設計

- 解析対象: `~/.claude/projects/*.jsonl` (Claude Code 公式 transcript path)。実ファイル
  は `<uuid>.jsonl` 命名のため glob は `*.jsonl` で吸収する。Dispatch transcript は
  当該 tree 外に置かれるため構造的に scope 外
- scope window: daily=1 日 / weekly=7 日
- 集計: model 別 token (input/output/cache_create/cache_read) + 概算 cost、cache
  cold-read share (prev turn が 5min 超なら cold)、stuck candidates (turn 間 gap が
  median+3sigma かつ 5min 超)、Haiku 委譲率、token 浪費 score (高出力 turn 比率)、
  workflow pattern (user prompt prefix の頻度 hash)、cost trend (前回 window 比)
- 出力: `~/.claude/insights/<YYYY-MM-DD>-{daily|weekly}.md` + `latest.md`
- ack 機構: `~/.claude/insights/.acked` (touch で timestamp 更新)。latest.md が
  .acked より新しいときのみ session 冒頭で提示
- pricing: 外出し `scripts/pricing.psd1`。web 確認待ちのため概算であることを注記し、
  相対比較専用 (billing 照合に使わない)
- opt-out: `apply -DisableInsights` で skill / command / scheduled-task の deploy を skip

### dot-source 設計

`usage-insights.ps1` は main 実行と関数 export を両立させるため、main 本体を
`Invoke-UsageInsights` に閉じ込め、`$MyInvocation.InvocationName -ne '.'` のときだけ
起動する。Pester test は dot-source して `Get-InsightsScope` / `Get-UsageMetrics` を
直接呼ぶ (main 副作用なし)。

### 既定 ON の根拠

- 負荷小 (週次 1 回 + 日次 1 回、解析は数秒)。古いファイルは LastWriteTime で pre-filter
- privacy: `~/.claude/insights/` 内のみ書出、外部送信なし
- 値: model / cache 最適化の発見は cost 削減に直結 (ADR-0002 cost 系の内訳補完)
- 破壊的副作用が無いため、cleanup-orphan-processes (ADR-0011、kill を伴うため opt-in)
  とは逆に opt-out を既定とする

## Alternatives considered

- (A) Active 通知 (Windows toast): 侵襲的、Claude Code workflow 外で割込 -> 却下
- (B) On-demand のみ (skill 経由): 受動的に気づきにくい -> 却下 (skill は補助入口として残す)
- (C) 既定 OFF + opt-in: 大多数の user が機能存在に気づかない -> 却下
- (D) 採用: passive + 既定 ON + opt-out

## Consequences

- `~/.claude/insights/` ディレクトリが新設される (latest.md / dated md / .cost-history.json)
- session 冒頭の挙動に CLAUDE.md §9 の instruction が追加される (passive、未 ack 時のみ)
- pricing が概算のため、cost 値は相対指標。確定値化は web 確認後の follow-up

## Refs

- ADR-0002 (cost-observation portage、本機能は内訳側を補完)
- ADR-0007 (hands-off settings、insights は user 設定と独立し ~/.claude/insights/ に隔離)
- ADR-0010 (skill / command 責務分離)
- ADR-0011 (cleanup-orphan-processes、skill + scheduled-task + opt-in/out の同パターン)
- ADR-0012 (statusLine context awareness、補完的 visualization)
