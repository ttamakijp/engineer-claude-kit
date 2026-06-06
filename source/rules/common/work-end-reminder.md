---
id: work-end-reminder
title: 終業時刻リマインダ (Claude 使用中のホスピタリティ機能)
description: ターン毎に時刻を取得し、終業 30 分前以降に軽量 reminder / 大タスク着手前確認を行う
audience: [claude]
priority: medium
applyTo:
  default: "**"
tags: [reminder, time-aware, hospitality]
---

# 要件

`config/work-schedule.yaml` (project) または `~/.claude/work-schedule.yaml` (global) の終業時刻を尊重し、ホスピタリティ (おもてなし = hospitality) として終業前のリマインダ (reminder) を表示する。

押し付けず、強制中断しない。判断は user に委ねる。

## 動作

ターン開始時に bash で曜日 + 現在時刻を取得 (例: `date +"%a %H:%M"`、Windows なら `Get-Date -Format "ddd HH:mm"`)。

yaml から終業時刻を読込。yaml が無ければ rule 不発火 (silent)。

### 3 case 分岐

#### Case 1: 終業 N 分前 (`warning_window_minutes` 内)、user の依頼が小さい (1-2 tool call で完結)

応答末尾に 1 行追記:

> ⏰ そろそろ終業時刻 (HH:MM)。必要なら `/checkpoint` で state 保存を推奨。

#### Case 2: 終業 N 分前 (`warning_window_minutes` 内)、user の依頼が大きい (3+ tool call、実装 (implementation) / refactor (リファクタリング) / 新規 PR / ADR 起票 等)

着手前に確認:

> ⚠️ 終業 30 分前 (HH:MM)。このタスクは推定 N 分かかります。
>
> どう進めますか:
> (a) 今着手 (終業を超えても続ける)
> (b) 明日に / 翌セッションで
> (c) `/checkpoint` 保存して今日は終了
>
> 選択肢を教えてください。

#### Case 3: 終業時刻過ぎ

応答末尾に 1 行追記:

> ⏰ 終業時刻過ぎ (HH:MM)。`/checkpoint` での state 保存を強く推奨。引き続きの作業も可能ですが、お疲れ様でした。

### タスク規模推定 (Claude 自己判断)

判定基準:

- **大判定**: prompt 内に以下キーワード、または影響 file 3 以上、または期待 tool call 3 以上
  - 「実装」「rewrite」「新規 PR」「ADR 起票」「全体」「リファクタリング」「refactor」
- **曖昧時**: conservative (保守的) に「大」扱い (誤検知でも害は確認 1 回増えるだけ)

## Do

- 終業 N 分前以降のみ発火 (それ以前は完全 silent)
- ホスピタリティ寄せ: 軽い 1 行 reminder、強制中断しない
- yaml の曜日 null (例: 土日) → そもそも reminder 不発火
- bash 時刻取得失敗 → silent fallback (rule 不発火)
- 大タスク確認で user が (a) 「今着手」を選んだら、その session 中は再確認しない (1 回で十分)

## Don't

- yaml に終業時刻が無い時に rule を発火させない (誤報のリスク)
- 毎ターン強制 reminder を出さない (押し付けがましい)
- 大タスク確認後の終業時刻過ぎ reminder は省略可 (二重通知を避ける)
- 出張 / 在宅 等の特殊日対応を rule 内で複雑化しない (user が yaml を一時編集すれば対応)

## 根拠

- user use case: 「終業直前に大きなタスクを着手して後悔」を防ぐ
- ホスピタリティ機能なので、押し付けず、判断は user に委ねる
- ADR-0006 で確定した 4 軸の動作

## 例外

- 出張 / 在宅 等の特殊日 → user が yaml を一時編集 (rule 側は無関心)
- 祝日 → yaml で当該曜日を null にする (簡易対応)
