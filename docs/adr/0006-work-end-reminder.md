---
status: Accepted
date: 2026-06-07
deciders: [Tetsuya]
tags: [reminder, work-life-balance, rule, time-aware]
---

# ADR-0006: work-end-reminder rule

> **昇格メモ**: 本 ADR は Proposed → Accepted に昇格済み。確定設計に基づき
> `config/work-schedule.yaml` / `source/rules/common/work-end-reminder.md` を同一 PR
> (Group F') で実装し、README §4 ADR Index に本 ADR を追記した。`drafts/proposed-`
> から `0006-` への rename も本 PR で実施済み (ADR-0005 と同じ運用)。下記
> "Implementation plan" の各項目は本 PR で実施済み (残課題は "Open questions" 参照)。

## Context

user は Claude Code を日常的に使う中で、就業終了時刻 (終業時刻) の直前に大きな
タスクを着手してしまい「終わらず後悔する」事例が頻発している。中断しづらい
実装・refactor・新規 PR 起票などを終業間際に始めると、退勤時刻を超過するか、
中途半端な状態で session を畳むことになり、いずれも体験が悪い。

この課題に対し、**Claude 自身が現在時刻と就業終了時刻を認識**し、終業 30 分前
以降は次の 3 case に応じた挙動を取る rule (ルール) を導入する:

- (a) 軽量タスクには応答末尾に控えめな reminder (リマインダ) を 1 行表示する
- (b) 大きなタスク着手前には「本当に今やるか」を確認する
- (c) 終業時刻を過ぎた後は `/checkpoint` 保存を強く推奨する

実装方式として、Cowork / Dispatch (scheduled task) は engineer-claude-kit の主要
target である business 環境で利用できない制約があるため不採用とする。代わりに
**Claude 自身がターン毎に時刻をチェックする** rule-based (ルールベース) 実装を
採用する。OS-level scheduler (Windows Task Scheduler) を介する複雑な解決は、
過剰判断として不採用とする (詳細は "Alternatives" 参照)。

## Decision

確定済みの設計判断は以下のとおり。

### 1. 時刻取得

ターン開始時に shell で現在時刻を取得する。低コスト (ミリ秒単位) で完結する:

- bash: `date +%H:%M`
- PowerShell: `Get-Date -Format "HH:mm dddd"`

### 2. 終業時刻設定

`config/work-schedule.yaml` で曜日別に終業時刻を定義する (user customizable):

```yaml
schedule:
  mon: "17:30"
  tue: "17:30"
  wed: "17:30"
  thu: "17:30"
  fri: "17:00"
  sat: null   # 終業 reminder 不要 (休日)
  sun: null
warning_window_minutes: 30
```

`null` の曜日は終業 reminder を発火しない (休日扱い)。`warning_window_minutes`
で「終業何分前から警告するか」を制御する (既定 30 分)。

### 3. 動作分岐 (3 case)

| 時刻条件 | user request の規模 | Claude の挙動 |
|---|---|---|
| 終業 30 分前以降 | 小さい質問 (1-2 tool call で完結) | 応答末尾に `⏰ そろそろ終業時刻 (HH:MM)、必要なら /checkpoint 推奨` を 1 行表示 |
| 終業 30 分前以降 | 大きいタスク (3+ tool call、実装/refactor/新規 PR 等) | **着手前に確認**: `⚠️ 終業 30 分前です。このタスクは推定 N 分。本気で着手しますか? (a) 今着手 (b) 明日 / 翌セッションで (c) checkpoint 保存して保留` |
| 終業時刻過ぎ | 規模を問わず全て | 応答末尾に `⏰ 終業時刻過ぎ。/checkpoint 強推奨` + 中断選択肢を表示 |

### 4. タスク規模推定 (Claude 自己判断)

Claude がターン毎に user request の規模を自己判断する:

- **大判定の条件** (いずれかに該当):
  - prompt 内に「実装」「rewrite」「新規 PR」「ADR 起票」「全体」
    「リファクタリング」などのキーワードを含む
  - 影響 file 数 3 以上が言及されている
  - 3+ tool call が期待される
- **判定が曖昧な場合** → conservative (保守的) に「大」扱いとする。
  誤検知 (false positive) でも害は「確認が 1 回増える」だけで小さく、
  逆に大タスクを小と誤判定して reminder を出し損ねる方が損失が大きいため。

### 5. rule の発火条件

全プロジェクト / 全ターンで発火する。CLAUDE.md のグローバル設定から常時参照される
(`applyTo: global`)。

## Daily interactive prompt (Phase 2 extension)

初版 (Group F') は yaml の曜日別終業時刻のみを参照する設計だった。しかし運用上、
user が yaml を編集する摩擦が大きく、「在宅 / 早退 day の override」(Open questions
参照) が未解決のまま残っていた。本拡張では、**その日の初回ターンで Claude 側から
終業時刻を質問する** daily interactive prompt を追加し、この摩擦を解消する。

### 設計理由

- **yaml 編集の摩擦を回避**: user が設定ファイルを開かずとも今日の終業時刻を指定できる
- **コマンド意識ゼロ**: slash command も覚える必要がなく、朝の自然な対話 1 往復で完結
- **特殊日 override の自然な解決**: 在宅 / 早退 day も「今日は 15:00」と答えるだけで吸収。
  yaml を恒久編集する必要がない

### marker file 仕様

質問の回答は global marker file に記録し、当日中の再質問を抑止する:

- **場所**: `~/.claude/.work-end-today` (Windows: `$env:USERPROFILE\.claude\.work-end-today`)
- **形式 (1 行)**: `YYYY-MM-DD <value>`
  - `<value>` = `HH:MM` (時刻) / `off` (休日) / `yaml` (曜日デフォルト参照) / `skip` (今日は不発火)
- 日付が今日と一致 → 既回答 (再質問しない)。前日以前 / 不在 → その日の初回。

### 動作フロー

1. ターン開始時に marker file を読込む。
2. **初回** (marker 不在 or 日付不一致): 冒頭で「今日は何時に仕事を終わりますか?」と
   1 行質問。次ターンの回答を parse し marker に書込む (`HH:MM` / `off` / `yaml` / `skip`)。
   不明回答は 1 回だけ再質問。
3. **既回答** (marker 今日付): 質問せず内容に従い従来の 3 case 分岐で動作。

### 優先順位 (新規)

1. **marker file (今日付)** ← 最優先 (user の今日の意思)
2. **yaml schedule (曜日別)** ← fallback (marker = `yaml` モードでも fallback)
3. **両方なし** → rule 不発火 (silent)

yaml はこの拡張後も廃止せず **fallback** として存続する (marker 不在時 / `yaml` モード時の曜日デフォルト)。

### Edge cases

- **marker 読込エラー**: silent fallback (yaml を参照、それも無ければ不発火)
- **初回質問を無視して別話題**: 質問を再表示しない (押し付けない)。marker 不在のため
  次ターンで再判定されるが、1 ターン内の質問は 1 回のみ
- **回答時刻が既に過去** (例: 17:30 と答えたが現在 18:00): marker 書込みつつ即 Case 3
  (終業時刻過ぎ) reminder を表示
- **PII (個人識別情報) 保護**: marker は global (`~/.claude/`) に置くが、念のため
  `templates/.gitignore` でも project 内 `.claude/.work-end-today` を除外

### 実装範囲

- markdown のみ変更 (rule body + 本 ADR + README + `.gitignore`)。PowerShell スクリプト
  (`build-rules.ps1` / `apply-claude-kit.ps1`) は不変。marker file の読書きは Claude が
  ターン毎に bash / shell で行うため、配布スクリプト拡張は不要。

## Alternatives

採用しなかった候補と、その理由:

| 案 | 採用しなかった理由 |
|---|---|
| Windows Task Scheduler 連携 (取下げた Group F) | OS-level scheduler が必要で Bedrock 環境依存・構成が複雑。Claude 起動毎の time check で代替可能なため過剰 |
| Outlook / Google Calendar 連携 | calendar integration が必要で user 環境依存が大きい |
| PowerShell profile での起動毎 reminder | Claude 起動とは独立に発火するため、Claude 内 reminder と二重化してしまう |
| 終業 60 分前から段階的 reminder | 「短期記憶への押し付け感」が強い。30 分前に 1 回で十分との user 判断 |
| 規模推定を全て user 確認に投げる | UX 負荷が大きい。Claude 自己判断 + 保守的 fallback の方が摩擦が少ない |

> 当初の Group F (OS-level scheduler + Windows Task Scheduler 連携) は、上表のとおり
> 過剰判断として取下げた。本 ADR の rule-based 方式 (Group F') がその代替である。

## Open questions

Accepted 昇格レビューで議論すべき未解決点 (現時点では全て **保留**):

- **祝日対応**: 日本の祝日に終業 reminder を抑制する仕組み。日本祝日 API 連携 か、
  yaml への手動 holiday list 拡張か未定。
- ~~**特殊日 override**: 出張 / 在宅 / 早退 day の一時的な schedule 変更の仕組み。~~
  → **Closed** (Phase 2 extension): daily interactive prompt により解決。初回質問へ
  「今日は HH:MM」「休み」等と答えるだけで当日の override が可能になり、yaml の
  一時編集が不要になった。詳細は "Daily interactive prompt (Phase 2 extension)" 参照。
- **Claude 非起動時**: 席に居るが Claude を使っていない時間帯には reminder が
  届かない。別 channel (OS 通知等) が必要かは未判断。
- **timezone**: 時刻表示は現状 OS local time に依存。明示的な timezone 設定を
  yaml に持たせるべきかは未定。
- **規模推定の評価**: precision / recall の評価方法。false positive を許容する
  方針なら定量評価は不要だが、運用後に review して判断する。
- **downstream project への yaml 配布**: 本 PR では `apply-claude-kit.ps1` を変更
  せず (既存構造不変方針)、`config/work-schedule.yaml` の project 配布は未配線。
  kit repo 自身では参照されるが、apply 先 project では rule が silent fallback と
  なる。利用には user が `~/.claude/work-schedule.yaml` を global 設置する必要が
  ある。apply 配布の追加は別 PR とするか未定 (**保留**)。

## Implementation plan

本 PR (Group F') で実施済み:

1. `config/work-schedule.yaml` 新規作成 (上記スキーマ、user customizable) — 実施済み
2. `source/rules/common/work-end-reminder.md` 新規作成 (rule body、
   frontmatter で `priority: medium` / `applyTo: "**"`) — 実施済み
3. `templates/CLAUDE.md` への追記 — rule 本体で完結するため省略 (任意項目)
4. `build-rules.ps1` の generic ループで自動 build (script 変更不要) — 確認済み
5. `apply-claude-kit.ps1` の `.claude/rules/` 配布で自動配布 (Project mode、
   script 変更不要) — rule は配布済み。yaml の project 配布は未配線 (Open questions 参照)
6. `tests/apply-claude-kit.tests.ps1` で rule の配布動作確認 (任意) — smoke test 追加
7. README §4 ADR Index に本 ADR を追記 — 実施済み
8. 本 ADR を Proposed → Accepted へ昇格、`drafts/proposed-work-end-reminder.md`
   を `0006-work-end-reminder.md` へ rename — 実施済み

## Refs

- ADR-0001 (kit clean-start design)
- ADR-0004 (auto model routing — 規模推定で Haiku 利用の候補)
- ADR-0005 (`/checkpoint` 連携 — case (a)(c) の checkpoint 推奨で参照)
- 取下げ案: 当初 Group F (OS-level scheduler + Windows Task Scheduler) — 過剰判断で取下げ
