---
status: Accepted
date: 2026-06-08
deciders: [Tetsuya]
tags: [context, compact, statusline, ux, convention]
---

# ADR-0012: Context awareness convention - visual statusline + CLAUDE.md guideline

> 本 ADR は P13 PR で起票され、同 PR で実装まで含めて Accepted とする。

## Context

Claude Code には `/compact` の **真の auto-trigger 機構が存在しない**:

- hooks は slash command を発火できない (hooks の責務外)
- Claude 自身は context window の使用率をリアルタイムに把握できない (会話の途中で % を可視できない)
- 外部 process / scheduled task からも slash command は発火できない

組込みの auto-compact は内部 ~95% trigger でのみ動作し、summary loss (進行中タスクや未完成の決定が
要約で欠落する) リスクがある。長時間 session で context window が満杯になる前に、user が能動的に
`/compact` できるよう、半自動的に気づかせる仕組みが必要。

なお statusLine 設定自体の deploy は ADR-0010 (interactive settings wizard) が担う。本 ADR は
その statusLine に **context % の視覚的警告 (色分け)** を持たせる convention と、それを補う
CLAUDE.md ガイドラインを定義する。

## Decision

「真の自動化」は Claude Code 公式実装が無い限り不可能。代わりに 2 つの組合せで **半自動化** する:

1. **statusline 色分け**: context % に応じて ANSI escape で色を変える。視覚的に警告する。
   - 緑 (ANSI `32`): `< 75%` (通常運用)
   - 黄 (ANSI `33`): `75-90%` (区切りの良いタイミングで `/compact` 推奨)
   - 赤 (ANSI `31`): `>= 90%` (即座に `/compact` 推奨、auto-compact 95% を回避)
2. **CLAUDE.md ガイドライン**: 「context % が高い場合は早めに手動 `/compact`」を kit template
   (`templates/CLAUDE.md` §8) に明記し、新規 user にも自然に伝わるようにする。

setup wizard (ADR-0010) で deploy される statusLine は **色分け版を default** とする
(`docs/setup/statusline-powershell.example.json` と `scripts/setup-wizard.ps1` で同一の command を ship)。

実装上の制約:

- ANSI escape の prefix は `[char]27` (ESC, 0x1B) で記述する。PS 5.1 では `` `e `` の expansion が
  無いため `[char]27` が互換 (ADR-0003 §C)。reset は `[0m`。
- 色選択は PowerShell の if-expression 代入 (`$c = if (...) {'31'} elseif (...) {'33'} else {'32'}`)
  で PS 5.1 / PS 7 双方互換。
- Windows Terminal は ANSI 対応。legacy cmd.exe console は非対応だが Claude Code は Windows Terminal
  推奨のため実害なし。
- threshold は user が `~/.claude/settings.json` の statusLine を編集して調整可能。

## Alternatives considered

| 案 | 内容 | 採否 |
|---|---|---|
| hooks で auto `/compact` | 何らかの hook で compact を自動発火 | 否決。hooks は slash command を発火できない |
| prompt で Claude に auto 判断させる | CLAUDE.md で「% が高ければ自分で compact」と指示 | 否決。Claude は context % をリアルタイム不可視 |
| scheduled task で trigger | 外部 process から定期発火 | 否決。外部 process から slash command は発火不可 |
| `/compact-now` wrapper command | compact を呼ぶだけの薄い command | 否決。素の `/compact` と価値が変わらず冗長 |

## Consequences

### 利点

- context % が視覚的に常時可視化され、満杯前に user が能動的に `/compact` できる。
- 色分け版を wizard default にすることで、新規 install から色付き statusline が有効化される。
- CLAUDE.md ガイドラインにより、statusline を見落としても運用方針として `/compact` が促される。

### 欠点 / 留意

- これは **半自動化** であり真の自動 compact ではない。最終判断は依然 user 任せ。
- legacy console (ANSI 非対応) では色が制御文字として表示され得る。Windows Terminal 前提で許容。
- CLAUDE.md ガイドラインが Claude 自身の挙動を変える効果は限定的 (Claude は % を可視できないため、
  あくまで user 向けの運用指針)。

## Refs

- ADR-0010 (interactive settings wizard): statusLine の deploy 経路
- ADR-0003 §C (encoding & PS 5.1 compatibility / ASCII only): `[char]27` / if-expression 互換
- Claude Code context window doc: https://code.claude.com/docs/en/context-window

## Open questions

- Claude Code 公式が `/compact` の auto-trigger (hook 発火 or 内部 threshold 設定) を提供したら、
  本 convention の statusline 色分けは残しつつ自動化に移行する余地がある。
- CLAUDE.md ガイドラインが Claude の振る舞いに与える効果は検証対象 (現状は user 向け運用指針)。
