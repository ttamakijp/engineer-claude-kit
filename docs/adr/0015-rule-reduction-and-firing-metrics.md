---
status: Accepted
date: 2026-10-05
deciders: [Tetsuya]
tags: [rules, context, instruction-surface, observability, paths, statusline]
---

# ADR-0015: 指示面の削減と「発火の実測」優先 — 散文状態機械の脱却

**ステータス**: Accepted
**日付**: 2026-10-05
**Phase**: 5 (運用品質)

> 起票時は Proposed。「未解決の問い」1 (rules の Global 配布) と 2
> (`~/.claude/CLAUDE.md` の symlink を本キット管理へ戻す) の両方が user により
> 承認されたため Accepted に昇格した (2026-10-05)。実装は Step 1-6 の別 PR で進める。

## コンテキスト

本キットは CLAUDE.md + `source/rules/` の 7 ファイルで 40,142 B (UTF-8 bytes、日本語主体) の指示面を持つ。
指示量が増えるほど一件あたりの遵守率が下がるため、削減を検討する。

ただし削減対象を決める前に **「どのルールが実際に効いているか」を測る**のが順番である
(足す前に測る / 削る前に測る)。現状 `usage-insights.ps1` は token と cost のみを集計し、
ルールの遵守有無を一切見ていない。

### Phase 0 調査で判明した事実 (当初の前提を修正するもの)

#### 事実 1: `source/rules/` の 6 ファイル (31,851 B) は user 環境のどの session にも載っていない

`scripts/apply-claude-kit.ps1:248-255` は rules を **Project mode 限定**で配布し、
Global mode では意図的に skip する。コメントは理由を
"Rules are project-specific by Claude Code convention" と記述している。

この前提は **誤り**である。Claude Code 公式仕様では `~/.claude/rules/` は
user-level rules として正式にサポートされ、「machine 上の全 project に適用」される。
そして `~/.claude/rules/` は現在 **存在しない**。

結果として、user の table が挙げる 40 KB のうち実際に context に載っているのは
**CLAUDE.md の 8,291 B のみ**。残り 31,851 B は「毎 session のコストを払っている負債」ではなく
「一度も効いたことのない死蔵在庫」である。

- `work-end-reminder.md` / `project-skill-recommend.md` の散文状態機械が守られない
  silent fallback の真因は、Claude の実行精度ではなく **未配布** である可能性が高い
- したがって「削減による context 節約」の実効は CLAUDE.md 分のみ。
  rules 側の削減効果は **保守コストと将来の context コスト**に対して効く

#### 事実 2: rule frontmatter で Claude Code が読む key は `paths` だけ

公式の rule frontmatter reference は
「`paths` is the only field Claude Code reads from a rule; any other field is ignored without an error」
と明記する。本キットの 6 rule が持つ `id` / `title` / `description` / `audience` /
`priority` / `applyTo` / `tags` は **すべて無視**されている。

- `applyTo.default: "**"` は効いていない。`paths` が無い rule は **無条件に launch 時ロード**
  (`.claude/CLAUDE.md` と同格の優先度)
- `paths` 付き rule は Claude が Read / Write / Edit で match した時のみロードされる。
  さらに `/compact` 後も該当ファイルを読めば再ロードされる
- `build-rules.ps1` の `Build-Rule` は frontmatter を無変換 verbatim copy するため、
  rename は **source 側 6 ファイルの書き換えのみ**で完結し build script 変更は不要
- ただし `id` は `build-rules.ps1` が出力ファイル名 (`$id.md`) に使うため削除不可。
  frontmatter に残しても Claude 側では無視されるので無害

→ 当初「🥈 手が空いたら」に置かれた項目 7 は、削減技法 1 (読む対象を絞る) の
**前提条件**であり、最優先に昇格すべきである。

#### 事実 3: `@path` import は context を削減しない

公式: 「Imports help you organize a long file but don't reduce its context cost,
because imported files also load at launch」。

→ 「根拠節を docs へ逃がす」は `@import` で繋いではならない。
**素のパス言及 (必要時に Claude が Read する)** でなければ削減効果はゼロになる。
user の当初案 (「必要時に `Read` させれば十分」) はこの点で正しい。

#### 事実 4: 200 行ガイドラインは公式

公式: 「target under 200 lines per CLAUDE.md file. Longer files consume more context
and reduce adherence」。現 CLAUDE.md は 145 行で既に基準内だが、削減方針自体は公式見解と一致する。

#### 事実 5: skills / commands は常時ロードされない

公式 Note: skills は「only load when you invoke them or when Claude determines they're relevant」。
`templates/skills/` 16,326 ch と `templates/commands/` 8,188 ch は常時 context に載らない。
削減対象から外して良い。

#### 事実 6: user 環境の CLAUDE.md は本キット管理外

`~/.claude/CLAUDE.md` は `.dev-templates` 配下を指す symlink であり、本キットの
`templates/CLAUDE.md` ではない。実ロード内容は本キット現行 template より古い世代に相当する。
Phase 3 (再適用) は単純な上書きでは成立しないため、別途判断が必要。

#### 事実 7: 「ルールの発火」は JSONL に直接は記録されない

`usage-insights.ps1` が読む transcript JSONL (`<uuid>.jsonl`) には、
どの instruction file が context に載ったかの記録は無い。
観測できるのは **ルールが要求する行動の痕跡**だけである。

したがって項目 2 の metric は「rule が発火したか」ではなく
**「rule が要求する観測可能な行動が起きたか」** として定義し直す。

## 決定

### A. 作業順序

当初案の 4 段から、事実 1 / 事実 2 を踏まえて 5 段に修正する。

user 承認済の実行順序 (2026-10-05)。1 Step = 1 PR を原則とする。

| Step | 内容 | PR | 根拠 |
|---|---|---|---|
| **1** | `paths` 正規化 (旧項目 7) | #79 | Global 配布の前提条件 |
| **2** | 発火 metric 実装 + baseline 記録 (旧項目 2) | #80 | 削る前に測る |
| **3** | rules の Global 配布 + CLAUDE.md を本キット管理へ (事実 1 / 6 の修正) | #81 | 正しいスコープで配布 |
| **4** | file-by-file 削減 + 散文状態機械のスクリプト化 (旧項目 3 + 1) | #82 以降 | 測定済の状態で削る |
| **5** | 観察 (1-2 週間) → 戻す / 削除確定 | — | 「守られなくなった」= 本物の有効ルール |
| **6** | 残件 (旧項目 4 / 5 / 6) | #83 以降 | 余力 |

Step 1 を先行させる理由: `paths` が効いていない状態で security-mobile.md を
Global 配布すると、PowerShell / markdown しか触らない session にも 9,189 B が
無条件ロードされる。先に `paths` を正しくしてから配布しなければ改善が悪化に転じる。

Step 2 (測定) を Step 3 (配布) より前に置くため、baseline は
**rules 未ロード状態**で取得される。E の 3 指標はいずれも CLAUDE.md 由来の指示
(§2 / §3.1) を対象とするため baseline 自体は有効だが、Step 3 で rules がロードされると
指標が動く可能性がある。したがって **Step 3 完了直後に 2 回目の snapshot を取得**し、
Step 5 の比較対象は「削減前 / 配布後」の snapshot とする (配布と削減の効果を分離する)。

#### snapshot の記録

`usage-insights.ps1 -WriteBaseline` は比較対象の
`~/.claude/insights/rule-metrics-baseline.json` を上書きしつつ、日付付きの
`rule-metrics-baseline-<YYYY-MM-DD>.json` を archive として残す
(単一ファイル上書きでは 3 点比較が成立しないため Step 3 で追加した)。

| # | 時点 | 取得日 | plan-first | strict | delegation | commit-convention |
|---|---|---|--:|--:|--:|--:|
| 1 | 配布前 / 削減前 | 2026-10-06 | 55.6% (40/72) | 48.6% | 0% (0/159) | 100% (40/40) |
| 2 | 配布後 / 削減前 | (apply 実行後に取得) | - | - | - | - |
| 3 | 削減後 | (Step 4 完了後) | - | - | - | - |

snapshot 1 は Step 3 の実装完了時点、すなわち **rules が user 環境にまだ配布されて
いない状態**の値である。snapshot 2 は `apply-claude-kit.ps1 -Global` を実行して
`~/.claude/rules/` が実際に配置された後でなければ意味を持たない。PR の merge では
なく apply の実行が分界点になる。

### B. 削減技法 (3 つに統一)

#### B-1. 読む対象を絞る (`paths` 限定)

`applyTo` を Claude Code が解釈する `paths` に置き換える。

```diff
 ---
 id: security-mobile
-audience: [claude]
-priority: high
-applyTo:
-  default: "**"
-tags: [security, mobile]
+paths:
+  - "**/*.{kt,kts,java,swift,m,mm}"
+  - "**/*.gradle*"
+  - "**/Info.plist"
+  - "**/AndroidManifest.xml"
 ---
```

`id` は `build-rules.ps1` の出力名解決に必要なため残す。
`audience` は同 script の Claude 向けフィルタに使われるため残す。
`priority` / `applyTo` / `tags` / `title` / `description` は削除する
(Claude には無視され、キット側でも参照されていない)。

ファイル別の `paths` 方針:

| rule | paths | 効果 |
|---|---|---|
| security-mobile | Kotlin/Swift/gradle/plist/manifest | PowerShell / md session では完全に消える (最大の 9.2 KB) |
| commit-convention | (無し = 無条件) | commit は全 project 共通のため常時必要 |
| bilingual-notation | (無し = 無条件) | 応答文体の規定で全 session 対象 |
| file-granularity | `**/*.{kt,swift,ts,tsx,py,ps1}` | 設計時のみ必要 |
| work-end-reminder | (3 行に縮小、無条件) | B-3 / C でスクリプトへ移管 |
| project-skill-recommend | (削除) | C でスクリプトへ全面移管 |

#### B-2. 「根拠」「関連」「例」を ADR / docs へ逃がす

rule 本文は **「要件 / Do / Don't / 例外」の 4 節固定**とする。
`## 根拠` 節は該当 ADR への 1 行参照に置き換える。読み物は `docs/` へ移し、
**`@import` では繋がない** (事実 3)。

- `commit-convention.md` の「PR フロー」「TDD サイクル」「Stacked PR の落とし穴」
  → `docs/setup/git-workflow.md` へ移設

#### B-3. 表を文に戻す

CLAUDE.md の表形式を散文 1 行に圧縮する。

```diff
-### 3.1 Haiku 委譲する作業 (軽作業)
-
-| 作業種別 | 委譲先 sub-agent |
-|---|---|
-| コミットメッセージ生成 (Conventional Commits) | `commit-msg` |
-| 既存ファイルの軽微な編集 (typo / フォーマット / import 整理) | `lint-helper` |
-| ログ / エラー要約 (build log, test output, stack trace 等) | `log-summary` |
-| 単純な事実質問 | 直接 Haiku で処理 |
-
-**発火条件 (これらを検知したら委譲)**
-...
+- 委譲: commit message → `commit-msg` / 小さな整形 → `lint-helper` / ログ要約 → `log-summary`
+- 自分で: 設計判断・複数ファイル横断・因果推論。迷ったら自分で (品質 > コスト)
+- commit / push / branch 操作は必ず自分で実行
```

### C. 散文状態機械のスクリプト化 (旧項目 1)

marker file の読み書き・日付比較・多段分岐を Claude に毎ターン実行させる設計をやめる。
守られなくても silent fallback となり検知不能だからである。

| 現状 | 移管先 |
|---|---|
| `work-end-reminder.md` の 3 stage / 3 case 判定 (7,894 B) | `templates/statusline.ps1` に終業時刻比較を追加し `⏰` を表示。rule は「statusline に `⏰` が出ていたら大きな作業の前に一言確認する」の 3 行に縮小 |
| `project-skill-recommend.md` の type 検出 + 推薦 (3,636 B) | `apply-claude-kit.ps1` が適用時に 1 回だけ候補を出力。rule は削除 |

statusline は既に時刻ではなく context % を描画しているため、終業時刻の読み取り
(`~/.claude/work-schedule.yaml` + `~/.claude/.work-end-today`) と比較を追加する。
失敗時は無表示 (現行の `$ErrorActionPreference = 'SilentlyContinue'` 方針を踏襲)。

### D. file-by-file 目標

byte 基準 (UTF-8)。合計 40,142 B → 15,000 B 前後。

| ファイル | 現在 | 処置 | 目標 |
|---|--:|---|--:|
| security-mobile.md | 9,189 | `paths` 限定 + 根拠を ADR へ | 5,000 |
| CLAUDE.md | 8,291 | §3.1 表 / §8 / §9 を圧縮 | 3,500 |
| work-end-reminder.md | 7,894 | C で statusline へ移管、rule は 3 行 | 300 |
| commit-convention.md | 6,586 | PR フロー / TDD / Stacked PR を docs へ | 2,500 |
| project-skill-recommend.md | 3,636 | C で `/apply` へ移管、rule 削除 | 0 |
| bilingual-notation.md | 2,850 | 判断基準の表を削り Do/Don't だけ | 1,000 |
| file-granularity.md | 1,696 | 根拠節を削る | 1,000 |
| **合計** | **40,142** | | **13,300** |

CLAUDE.md 圧縮後の骨格 (目標 26 行 / 3.5 KB):
ペルソナ 3 / 応答ルール 4 (現状維持) / モデル使い分け 5 / sub-agent 原則 3 /
優先順位 2 / セキュリティ 3 / 環境 2 / context 2 / insights 2。

### E. 発火 metric の定義 (旧項目 2)

事実 7 より「rule のロード」は観測不能なので、**ルールが要求する行動の痕跡**を測る。
`usage-insights.ps1` の行正規化 (`Get-InsightsScope`、現 96-155 行) で
assistant の `message.content[]` を走査し、以下 3 指標を `Get-UsageMetrics` に追加する。

| 指標 | 観測対象 (JSONL) | 対応する指示 |
|---|---|---|
| `PlanFirstRate` | user prompt 直後の assistant turn の先頭 text block が 1-2 行の方針文か、かつ同 turn に Edit / Write の `tool_use` が無い | CLAUDE.md §2「実装前に 1 行の修正方針」 |
| `CommitDelegationRate` | `git commit` を含む Bash `tool_use` を持つ session のうち、先行して `Task` (`subagent_type: commit-msg`) が出現した割合 | CLAUDE.md §3.1 |
| `LogDelegationRate` | 2,000 token 超の Bash 出力を受けた turn のうち `log-summary` へ委譲した割合 | CLAUDE.md §3.1 |

いずれも **近似**であり、絶対値ではなく Phase 2 baseline と Phase 4 の差分を見る。
Phase 4 で「削減後も変化なし」なら元から効いていなかったと判定し削除確定、
「悪化した」なら本物の有効ルールとして復帰させる。

測れない指示 (例: 「曖昧さを排除し論理的な対話を維持」) は
**効いている前提で残さない**。Phase 3 の削除候補に入れる。

## 検討した代替案

### 代替案 1: 先に削減し、後から測る (user 当初案の Phase 1/2 を入替)

- メリット: 体感改善が早い。実装も単純
- デメリット: baseline が無いため Phase 4 の比較が成立しない。
  「削ったら守られなくなった」ルールと「元から守られていなかった」ルールを区別できず、
  削減の正否が永久に検証不能になる。却下

### 代替案 2: rules を全廃し CLAUDE.md 1 枚に統合

- メリット: 最も単純。配布経路も 1 本化され、事実 1 の不整合が構造的に消える
- デメリット: `paths` による条件付きロード (事実 2) を捨てることになる。
  security-mobile 9.2 KB を全 session に載せるか削るかの二択となり、
  最大の削減余地を自ら放棄する。却下

### 代替案 3: hook (PreToolUse) で強制する

- メリット: 公式も「Claude の判断に依存せず確実に止めるなら hook」と明言しており、
  silent fallback が構造的に起こらない
- デメリット: 本件対象の多くは「止める」ではなく「促す / 表示する」性質で hook と噛み合わない。
  ただし C の statusline 移管は hook と同系の「Claude 非依存化」であり、
  思想としては本決定に取り込んでいる。将来 commit 系の強制には再検討の価値あり

## 未解決の問い

1. ~~事実 1 の修正方針: rules を Global 配布に切り替えるべきか~~
   → **解決 (2026-10-05, user 承認)**: Global 配布に切り替える。Step 3 で実施
2. ~~事実 6 の symlink: `~/.claude/CLAUDE.md` を本キット管理へ戻すか~~
   → **解決 (2026-10-05, user 承認)**: 本キット管理へ戻す。Step 3 で実施。
   既存の手動オーバーライド内容は失わせず、差分は DEFERRED として記録する
3. `work-end-reminder` の marker file (`~/.claude/.work-end-today`) は存在するが
   rules は未配布である。どの経路で書かれたかは未確認 (調査を user が中断)

### DEFERRED (Step 3 で判明、対応は保留)

- **`.dev-templates` が `CLAUDE.user.md` を所有し続けている**: Step 3 以前の
  `~/.claude/CLAUDE.md` は `.dev-templates/templates/CLAUDE.user.md` への symlink
  だった。Global mode は書込先を無条件に上書きするため、`Write-Utf8NoBom` が
  **リンクを貫通して別リポジトリのファイルを書き換えていた** (deployed 内容が
  旧世代の kit template そのものだったことがその痕跡)。Step 3 でリンクを検出し、
  backup のうえ実ファイルへ置換するようにしたが、`.dev-templates` 側のファイル
  そのものは **意図的に残している**。同リポジトリや他の tooling がそれを参照して
  いる可能性があり、本キットの判断で削除すべきではない。整理は user が
  `.dev-templates` 側の用途を確認したうえで別途行う
- **deployed CLAUDE.md に user 独自の編集は無かった**: 置換前に diff した結果、
  deployed 側にしかない内容は「Sonnet 4.5」表記、削除済みの
  `subagent-orchestration.md` への dangling 参照、Bedrock 前提の §7 のみで、
  いずれも kit template 側が意図的に更新・削除済みだった。失われた user 編集は無い
4. `PlanFirstRate` の判定精度。「1-2 行の方針文」をヒューリスティックで取るため
   false negative が出る。Phase 2 で手動サンプリング照合が必要
5. Phase 4 の観察期間に他の変更 (model 変更、別 PR) が混入すると差分の帰属が崩れる。
   観察期間中は指示面を凍結する運用が必要か

## 結果

### 利点

- 削減の正否が事後検証可能になる (baseline → 差分)
- `paths` 正規化により、最大ファイル (security-mobile 9.2 KB) が
  関係ない session から構造的に消える。削減より効果が大きく、情報の損失がない
- 散文状態機械の撤去により、「守られたか」が marker file ではなく
  statusline / スクリプト出力として **目視可能**になる
- 指示面が「要件 / Do / Don't / 例外」4 節固定になり、追加時の判断が機械的になる

### 欠点

- Phase 1 → 4 で最短 2-3 週間を要する。即効性は無い
- metric は近似であり、絶対値としては信頼できない。誤った削除判断のリスクが残る
- `paths` 限定は「関係あるのに載らない」失敗も生む
  (例: Kotlin を触らずに security 設計を議論する session では security-mobile が載らない)
- 情報が rule / docs / ADR / statusline に分散し、「どこに書いてあるか」の
  索引コストが上がる

## 参照

- ADR-0001 (clean start design) — `source/rules/` → `dist/.claude/rules/` の build 方針
- ADR-0003 (bootstrap and abstraction) — ASCII only / PS 5.1 互換制約
- ADR-0006 (work-end-reminder) — C で statusline へ移管する対象の元決定
- ADR-0012 (context awareness convention) — statusline 色分けの既存仕様
- ADR-0014 (usage-insights) — E で拡張する metric 基盤
- Claude Code 公式 "How Claude remembers your project"
  (https://code.claude.com/docs/en/memory) — 事実 2 / 3 / 4 / 5 の出典
- `scripts/apply-claude-kit.ps1:248-255` — 事実 1 の該当箇所
