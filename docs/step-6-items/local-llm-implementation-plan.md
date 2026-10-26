# ADR-0016 実装 PR 設計書 (a / b / c / d)

**作成日**: 2026-10-27 / **ステータス**: 設計のみ。着手は user 承認後

ADR-0016 の決定を 4 本の PR に分ける。**(d) を最初に入れる**ことを推奨する
(理由は下記「順序」)。

## 順序の推奨: d → c → a → b

依頼の提示順は a/b/c/d だが、**計測 (d) を先に入れる**のが筋である。

snapshot 4 は 2026-11-03 以降に取得でき、それが **local-llm 稼働後の初回の
完全な window** になる。(d) が入っていなければ、その window でも local-llm への
委譲は指標に乗らず、snapshot 3 と同じ「delegation 0%」が出る。**一度しか来ない
初回計測を無駄にする**。

(a) の文面変更を先に入れると、snapshot 4 が「文面変更の効果」と「local-llm 稼働の
効果」の両方を含み、ADR-0015 で繰り返し苦労した混在データになる。

| 順 | PR | 入れる時期 | 理由 |
|---|---|---|---|
| 1 | **(d) 計測** | **11-03 の snapshot 4 取得前** | 初回 window を取り逃がさない |
| 2 | (c) fallback rule | (d) と同時でもよい | 文面変更の前提 |
| 3 | (a) CLAUDE.md §3 | snapshot 4 取得後 | 効果を分離する |
| 4 | (b) prompt template | (a) と同時 | (a) が参照する |

## (d) 指標に local-llm を含める

**branch**: `feat/insights-local-llm-delegation`

### 変更

| ファイル | 変更 |
|---|---|
| `scripts/lib/rule-metrics.ps1` | local-llm tool 名の定数追加、`DelegationLocalLlm` / `DelegationDisplaced` の集計、report 行の追加 |
| `tests/rule-metrics.tests.ps1` | 上記の Pester |
| `docs/adr/0015-...md` | snapshot 表に「delegation の定義が再度変わる」旨を追記 |

### 設計

```powershell
# local-llm MCP への委譲。tool 名は mcp__<server>__<tool> 形式で、server 名は
# 利用者の MCP 設定で決まるため完全一致ではなく部分一致で拾う。
$script:RuleMetricsLocalLlmPattern = 'local_llm__'

# health は可用性確認であって委譲ではないので分母にも分子にも入れない。
$script:RuleMetricsLocalLlmExclude = @('local_llm__health')
```

`DelegationDisplaced` は ADR-0016 未解決の問い 3 のとおり事後判定が自明でない。
**上限値として tool 呼出数をそのまま使い、「最大でこれだけ Opus を代替した」と
報告する**。下限は 0 であることを report に明記し、点推定として扱わない。

### commit 戦略

1. `feat(insights): local-llm への委譲を指標に含める` — 集計 + report
2. `test(insights): local-llm 委譲の集計を固定する` — Pester
3. `docs(adr): delegation 定義の再変更を ADR-0015 に記録する`

### 想定工数

**2-3 時間**。`rule-metrics.ps1` は 500 行上限に張り付いているため、**集計の追加
だけで上限を超える**。lib 抽出が事実上必須で、その分の時間を含む。

> 実装時の実測 (2026-10-27): 計画時に 499 行と書いたが実際は **528 行**で、
> PR #95 の時点で既に上限を超えていた。計画時の計測が誤っていた。実装 PR では
> `lib/baseline-io.ps1` と `lib/commit-subject.ps1` を抽出して 433 行に下げた。

## (c) local-llm 不達時の fallback rule

**branch**: `feat/local-llm-fallback-rule`

### 変更

| ファイル | 変更 |
|---|---|
| `source/rules/common/local-llm-fallback.md` | 新規 (3-5 行、`paths` なし = 無条件ロード) |
| `scripts/lib/plain-language-hints.json` | `HaikuZero` / `OpusHeavy` の文面修正 |
| `tests/build-rules.tests.ps1` | 新 rule が build されることの確認 |

### rule 本文の案

```markdown
## 要件

local-llm MCP tool が不達 (health 失敗 / 呼出エラー) のときは、その作業を
**main で自分で処理する**。Haiku sub-agent には戻さない。

## Do / Don't

- 不達を 1 回確認したら、その session 中は再確認しない
- 代替として Haiku sub-agent を使わない (委譲コストが main を上回るため)
- 不達を user に報告しない (作業は続行できているため)
```

### plain-language hint の修正 (重要)

snapshot 3 のレポートに、**現在の §3 と矛盾する hint** が出ている。

> commit message やログ要約のような単純作業も、複雑な分析と同じ AI で処理しています。
> 電卓で済む計算を博士号に頼んでいる状態です。

PR #95 で §3 から「必ず委譲」を外したとき、`HaikuZero` / `OpusHeavy` の文面を
更新し忘れた。本 PR で local-llm 前提に書き換える。

### commit 戦略

1. `fix(insights): §3 と矛盾する plain-language hint を修正する`
2. `feat(rules): local-llm 不達時の fallback rule を追加する`

### 想定工数

**1-2 時間**。rule は短く、hint は JSON の文言差し替え。

## (a) CLAUDE.md §3 の委譲先変更

**branch**: `feat/claude-md-local-llm-delegation`

### 変更

| ファイル | 変更 |
|---|---|
| `templates/CLAUDE.md` | §3 の委譲先を local-llm MCP tool に差し替え |
| `tests/usage-insights.tests.ps1` | README 回帰テストと同様に §3 の回帰を固定 |

### 決めるべきこと (ADR-0016 未解決の問い 5)

MCP tool 名を CLAUDE.md にハードコードすると、**local-llm を持たない利用者に
無効な指示が常時ロードされる**。本 kit は self-contained を原則とする (ADR-0003)。

| 案 | 内容 | 評価 |
|---|---|---|
| A-1 | tool 名を直書き | 最短。ただし他環境で無効な指示が残る |
| A-2 | `config/delegation.yaml` で宛先を定義し、apply 時に substitution | 既に `{{role:*}}` の仕組みがある。整合的 |
| A-3 | 「local-llm MCP が使えるなら」と条件付きで書く | 条件判断を Claude に戻すことになり ADR-0015 §C に逆行 |

**A-2 を推奨**する。`Invoke-TemplateSubstitution` が既にあり、local-llm を持たない
利用者には「自分で書く」(PR #95 の現状) が展開される形にできる。

### commit 戦略

1. `feat(config): 委譲先を config で切り替えられるようにする` (A-2 採用時)
2. `feat(rules): CLAUDE.md §3 の委譲先を local-llm へ向け直す`
3. `test(rules): §3 の委譲先の回帰を固定する`

### 想定工数

**3-4 時間** (A-2 採用時)。substitution の追加とテストが主。A-1 なら 1 時間。

## (b) sub-agent prompt template の local-llm 対応版

**branch**: `feat/local-llm-prompt-templates`

### 変更

| ファイル | 変更 |
|---|---|
| `templates/local-llm/summarize.md` | log 要約用の system prompt |
| `templates/local-llm/lint.md` | lint 用の system prompt |
| `scripts/apply-claude-kit.ps1` | 上記の配布 (Global / Project 両対応) |
| `tests/global-mode.tests.ps1` | 配布の確認 |

### 依頼との差分 (申告)

依頼では `templates/sub-agents/*` とあったが、**既存の配布先は
`templates/agents/`** (Claude Code の `~/.claude/agents/` に対応) である。
local-llm の prompt は Claude Code の sub-agent 定義ではなく **MCP 呼出時に渡す
system prompt** なので、`templates/agents/` に置くと Claude Code が sub-agent
定義として誤読する。別ディレクトリ `templates/local-llm/` を提案する。

### 想定工数

**2-3 時間**。`apply-claude-kit.ps1` は現在 **500 行ちょうど**で、配布ループの
追加だけで上限を超える。既存の配布ループを汎用化して lib へ抽出する必要があり、
その分を含む。

## 全体の工数と上限リスク

| PR | 工数 | 500 行上限に抵触するファイル |
|---|--:|---|
| (d) | 2-3 h | `rule-metrics.ps1` 528 行 (上限超過済) → **抽出必須** |
| (c) | 1-2 h | なし |
| (a) | 3-4 h | なし (A-2 採用時は `models-config.ps1` に追加) |
| (b) | 2-3 h | `apply-claude-kit.ps1` 500 行 → **抽出必須** |
| 合計 | **8-12 h** | |

**上限に 2 ファイルが張り付いている**ことが工数の主因である。機能追加そのものは
いずれも小さい。

## 関連

- ADR-0016 (本設計の決定)
- `docs/step-6-items/snapshot-3-analysis.md` (local-llm の利用痕跡)
- ADR-0015 §B (file-granularity の 500 行上限と抽出の先例)
- ADR-0003 (self-contained 原則)
