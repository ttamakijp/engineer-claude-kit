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

さらに、**その日の初回ターンで「今日は何時に仕事を終わりますか?」と自然な対話で質問**し、user が yaml を編集せず・コマンドも意識せずに今日の終業時刻を Claude に伝えられるようにする (コマンド意識ゼロの hospitality)。回答は marker file (印・記録ファイル) に記録し、当日中は再質問しない。

## marker file (印・記録ファイル) 仕様

- **場所**: `~/.claude/.work-end-today` (global。Windows: `$env:USERPROFILE\.claude\.work-end-today`)
- **形式 (1 行のみ)**:
  - 時刻指定: `2026-06-08 17:30`
  - 休日: `2026-06-08 off`
  - yaml 参照モード: `2026-06-08 yaml`
  - skip (今日は不発火): `2026-06-08 skip`
- **日付** が今日と一致するかで「その日の初回か既回答か」を判定する。

### 優先順位

1. **marker file (今日付)** ← 最優先 (user の今日の意思)
2. **yaml schedule (曜日別)** ← fallback (marker = `yaml` モードでも fallback)
3. **両方なし** → rule 不発火 (silent)

## 動作

ターン開始時に bash で日付 + 曜日 + 現在時刻を取得 (例: `date +"%Y-%m-%d %a %H:%M"`、Windows なら `Get-Date -Format "yyyy-MM-dd ddd HH:mm"`)。

### Stage 1: marker file 読込 → 初回判定

marker file を読込む:

- **不在** → 「その日の初回」と判断 → Stage 2 (初回質問) へ
- **存在** → 1 行目を parse し、日付が今日と一致するか確認:
  - **一致** (既回答) → 質問せず Stage 3 (3 case 分岐) へ。内容で挙動決定:
    - `HH:MM` → その時刻を終業時刻として 3 case 判定
    - `off` → 今日は reminder 不発火 (silent)
    - `yaml` → yaml の曜日デフォルトを参照して 3 case 判定 (yaml も無ければ silent)
    - `skip` → 今日は rule 不発火 (silent)
  - **不一致** (前日以前) → 「その日の初回」と判断 → marker を上書き対象とし Stage 2 へ
- **読込エラー** → silent fallback (yaml を参照、それも無ければ不発火)

### Stage 2: 初回質問 (その日 1 回だけ)

response の冒頭で 1 行質問する (押し付けない、1 ターン内 1 回のみ):

> おはようございます。今日は何時に仕事を終わりますか?
> - `HH:MM` 形式で時刻指定 (例: 17:30)
> - 「休み」「off」「休日」 → 今日は reminder OFF
> - 「そのまま」「yaml」「いつも通り」 → yaml の曜日デフォルトを使用
> - 「答えない」「skip」 → 今日は質問・reminder ともに無し

user の **次のターンでの返答** を待ち、parse して marker に書込む:

| 返答 | marker 書込 | 以降の挙動 |
|---|---|---|
| `HH:MM` | `YYYY-MM-DD HH:MM` | その時刻で 3 case 判定 |
| 「休み」/「off」/「休日」 | `YYYY-MM-DD off` | 今日は不発火 |
| 「そのまま」/「yaml」/「いつも通り」 | `YYYY-MM-DD yaml` | yaml 参照モードで動作 |
| 「答えない」/「skip」 | `YYYY-MM-DD skip` | 今日は不発火 |
| 不明 | (書込まず) | 1 回だけ「もう一度教えてもらえますか?」と再質問 |

- user が初回質問を無視して別の話題を始めた場合、質問を **再表示しない** (押し付けない)。marker 不在のため次ターンで再判定されるが、1 ターン内の質問は 1 回だけ。
- user が `17:30` と答えたが既にその時刻を過ぎている場合、marker 書込みつつ即 Case 3 (終業時刻過ぎ) reminder を表示する。

### Stage 3: 3 case 分岐

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
- **初回質問は 1 日 1 回だけ**。回答後は marker (今日付) を信頼し再質問しない
- **yaml は fallback として残す**。marker = `yaml` モードや marker 不在時の曜日デフォルトとして機能
- yaml の曜日 null (例: 土日) → そもそも reminder 不発火
- bash 時刻取得・marker 読込失敗 → silent fallback (yaml 参照 or 不発火)
- 大タスク確認で user が (a) 「今着手」を選んだら、その session 中は再確認しない (1 回で十分)

## Don't

- yaml にも marker にも終業時刻が無い時に rule を発火させない (誤報のリスク)
- 毎ターン強制 reminder を出さない (押し付けがましい)
- **答え忘れを叱責しない** (user が初回質問を無視しても silent fallback、押し付けない)
- **同じターン内で複数回質問しない** (再質問は不明回答時の 1 回のみ)
- 大タスク確認後の終業時刻過ぎ reminder は省略可 (二重通知を避ける)
- 出張 / 在宅 等の特殊日対応を rule 内で複雑化しない (interactive 質問 or yaml 一時編集で対応)

## 根拠

- user use case: 「終業直前に大きなタスクを着手して後悔」を防ぐ
- ホスピタリティ機能なので、押し付けず、判断は user に委ねる
- **ホスピタリティ強化**: yaml を編集する摩擦・コマンドを意識する負荷をなくし、
  朝の自然な対話 1 往復で今日の終業時刻を伝えられるようにする (コマンド意識ゼロ)。
  在宅 / 早退 等の特殊日も interactive 質問への回答で吸収でき、yaml 一時編集が不要になる
- ADR-0006 (Daily interactive prompt 拡張含む) で確定した動作

## 例外

- 出張 / 在宅 / 早退 等の特殊日 → 初回質問への回答 (HH:MM / off) で吸収。yaml 一時編集は不要
- 祝日 → yaml で当該曜日を null にする (簡易対応)
