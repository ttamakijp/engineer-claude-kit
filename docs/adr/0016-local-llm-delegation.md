---
status: Proposed
date: 2026-10-27
deciders: [Tetsuya]
tags: [delegation, local-llm, mcp, cost, insights]
---

# ADR-0016: 委譲先を Haiku sub-agent から local-llm MCP へ向け直す

**ステータス**: Proposed
**日付**: 2026-10-27
**Phase**: 6 (運用品質)

## コンテキスト

ADR-0015 item 4 で、Haiku sub-agent への委譲は commit message のような作業では
**main で書くより高くつく**ことを実測した。

| | 1 回あたり |
|---|--:|
| Haiku sub-agent へ委譲 | $0.082 - $0.120 |
| main (Opus) が自分で書く | $0.023 - $0.060 |

理由は cacheCreate が 76.1% を占めること。sub-agent prompt は self-contained を
要求されるため main の cache を使えず、毎回自分の context を作り直す。PR #95 で
「必ず委譲」を撤回し、委譲は 8,000 字超の出力要約に限定した。

その結果 snapshot 3 (2026-10-27) では **Haiku turn が 0**、delegation も 0% に
なった。これは意図どおりだが、**軽作業を安く処理する手段が無くなった**状態でもある。

### 2026-10-26 に前提が変わった

`hx99g-local-llm` (private) の Phase 1/2 が稼働し、local-llm MCP が使える状態に
なった。snapshot 3 の window には既に利用痕跡がある。

| tool | 回数 |
|---|--:|
| `mcp__local-llm__local_llm__generate_commit_message` | 5 |
| `mcp__local-llm__local_llm__chat` | 2 |
| `mcp__local-llm__local_llm__health` | 2 |

local-llm は **API 課金が発生しない** (ローカル推論) ため、Haiku 委譲の経済的な
不利 (cacheCreate を払い直す) がそのまま利点に反転する。cacheCreate を払っても
課金されないので、self-contained prompt の制約がコスト上の問題でなくなる。

### 現在の指標は local-llm を数えていない

`Get-RuleMetrics` は `Agent` / `Task` の `subagent_type` しか見ておらず
(`$script:RuleMetricsAgentTools = @('Agent', 'Task')`)、`mcp__*` を一切数えない。
そのため snapshot 3 の `delegation 0%` は「委譲が起きなかった」ではなく
**「測っている宛先への委譲が起きなかった」**の意味しかない。実際には 7 件
(health を除く) が local-llm に向いていた。

## 決定

### A. 委譲先を local-llm MCP に向け直す

CLAUDE.md §3 の委譲先を Haiku sub-agent から local-llm MCP tool に差し替える。

| 従来 (Haiku sub-agent) | 変更後 (local-llm MCP) |
|---|---|
| `commit-msg` | `local_llm__generate_commit_message` |
| `log-summary` | `local_llm__chat` (要約用 system prompt) |
| `lint-helper` | `local_llm__chat` (lint 用 system prompt) |

PR #95 で「commit message は自分で書く」としたのは **Haiku 委譲が高かったから**
であり、課金のない宛先ができた以上その理由は失効する。判定軸を
「大きな入力を締め出せるか」から **「ローカルで十分な品質が出るか」**に戻す。

### B. 不達時は Claude 本体へ escalate する

local-llm は常時稼働が保証されない (ホスト PC の電源、モデルのロード状態)。
`local_llm__health` が不達、または tool 呼出が失敗した場合は **main で自分で
処理する** (Haiku へ戻さない)。Haiku に戻すと A で解消した不利が復活する。

fallback の判断を Claude の毎ターンの推論に委ねない。rule として 3 行で書き、
`health` の結果に基づく機械的な分岐にする (ADR-0015 §C と同じ方針: 散文の
状態機械を作らない)。

### C. 指標に local-llm を含め、displaced を区別する

`Get-RuleMetrics` に local-llm tool 呼出を数える経路を追加する。単に合算すると
「Haiku への委譲」と「local-llm への委譲」が区別できなくなるため、宛先ごとに
分けて集計する。

| フィールド | 意味 |
|---|---|
| `DelegationHits` | 推奨された宛先への委譲 (snapshot 3 時点の定義で凍結。下記注記 1) |
| `DelegationLocalLlm` | local-llm MCP tool の呼出数 (宛先別) |
| `DelegationLegacy` | 非推奨の Haiku sub-agent が使われた数 (既存) |
| `DelegationDisplaced` | **local-llm が肩代わりし、Opus / Haiku のどちらでも処理されなかった件数** |

`DelegationDisplaced` は `item-4-subagent-cost-measurement.md` §2 で使った
「締め出せた入力量」の考え方を件数に流用したもので、削減額の推定に使う。

#### 注記 1: `DelegationHits` / `DelegationRate` の定義は凍結し、local-llm は別 bucket

`DelegationHits` および `DelegationRate` の定義は **snapshot 3 時点で凍結**する。
local-llm は separate bucket (`Local`) として集計する。

上の表の初稿は「`DelegationHits` に local-llm を合算する」と読める書き方だったが、
**採用しない**。合算すると delegation の定義が 3 度目の変更となり、snapshot 1 ->
2' -> 3 の `delegation` trend の連続性が失われる。既存の分子・分母はそのまま残し、
local-llm は新しいフィールドとして**追加**する。

実装は PR #98 (`scripts/lib/mcp-metrics.ps1`)。

#### 注記 2: `displaced` は per-event で移管を証明する指標ではない

`DelegationDisplaced` は**軽作業をどの model が処理したか**の内訳
(`Local` / `Haiku` / `Opus` / `Sonnet`) であり、個々の呼出について「Opus の作業が
local-llm に移った」ことを証明する指標ではない。

- `Local` は**上限値**として扱う (下限は 0)
- 2 つの snapshot 間の delta で **`Local` 増 + `Opus` / `Haiku` 減が揃った時のみ**
  有意な移動として読む。`Local` の単独増加は委譲の純増であり、削減ではない
- 単一 snapshot の `Local` を点推定として報告してはならない

この注記により**未解決の問い 3 を close** する (下記)。

#### 注記 3: fallback rule は Phase 1 では repo 保全のみ、配布しない

`local-llm-fallback.md` (決定 B の rule) は repo に置くが、**Phase 1 の時点では
配布しない** (`audience` に `claude` を含めず、build-rules.ps1 の出力から外す)。

理由:

- **local-llm の不達はまだ 1 件も観測されていない。** 実測は work 呼出 7 件 +
  health probe 2 件で、失敗 0 件 (PR #98 の計測)
- 未観測 (0 件) の障害に対して常時ロードの指示を先回りで足すのは、ADR-0015 の
  「足す前に測る」に反する。ADR-0015 で指示面を 77% 削った方向とも逆向き
- 常時ロード面が 9,505 -> 11,073 B (+16.5%) になり、**snapshot 4 で測ろうとしている
  常時ロード面そのものを汚す**。測定前に測定対象を動かすことになる

rule の内容は先に固めてある (不達時の分岐を毎ターンの推論に委ねない形)。足りないのは
「足す根拠」だけなので、配布だけを保留する。切替条件は未解決の問い 6。

## 検討した代替案

### 代替案 1: Haiku と local-llm の併用 (task type で routing)

- メリット: local-llm が不達でも Haiku で継続でき、可用性が上がる
- デメリット: routing 規則を CLAUDE.md に書く必要があり、指示面が再び増える
  (ADR-0015 で 77% 削った方向に逆行)。かつ Haiku 経路のコスト不利は残るので、
  効果が限定される。**却下**

### 代替案 2: 完全に local-llm 専用 (Haiku を使わない) — 本案

- メリット: 指示が 1 本化され短い。課金が発生しないので委譲の損得計算が不要になる
- デメリット: local-llm 不達時に委譲が完全に止まる (決定 B の fallback で緩和)。
  ローカルモデルの品質が Haiku を下回る可能性がある (未検証)

### 代替案 3: 現状維持 (Haiku 0% / delegation 0% のまま)

- メリット: 変更コストゼロ。PR #95 の状態で既に「損な委譲」は止まっている
- デメリット: 軽作業を安く処理する手段が無い。local-llm が既に動いているのに
  使わないのは機会損失。**却下**

## 未解決の問い

1. **local-llm の出力品質が Haiku と比べてどうか未検証。** commit message は
   Conventional Commits 形式の充足で機械判定できる (`CommitRate` が既にある) が、
   log 要約の品質は機械判定できない
2. ~~**不達の検出コスト。**~~ **決定済 (PR (c))。** `health` は委譲が実際に必要に
   なった時に 1 回だけ叩く。session 冒頭の先回り確認はしない。一度不達なら その
   session 中は再確認せず自分で処理し続ける (`local-llm-fallback.md`)
3. ~~**`DelegationDisplaced` の定義。**~~ **決定済 (決定 C の注記 2)。** 事後の
   per-event 判定はできないため、handler mix の内訳とし、`Local` を上限値
   (下限 0) として snapshot 間の delta で読む。
4. **snapshot の比較可能性。** ADR-0015 §A に記録したとおり delegation は既に
   snapshot 3 で定義が変わっている。本 ADR の実装で**再度変わる**ため、
   snapshot 5 以降としか比較できなくなる
5. **local-llm 側 repo (private) への依存。** 本 kit は self-contained を原則と
   している (ADR-0003)。MCP tool 名をハードコードすると、local-llm を持たない
   利用者には無効な指示が常時ロードされる。`config/` で宛先を切り替えられる形に
   するかは実装 PR (a) で決める
6. **fallback rule を配布へ切り替える trigger。** 注記 3 のとおり Phase 1 では
   repo 保全のみ。**local-llm の失敗が 1 件でも観測された時点で (B) -> (A) に
   切り替える** (`audience` を `[claude]` に戻して配布する)。観測の手段は
   `DelegationLocalLlm` の呼出数に対して成果物が得られなかった turn の有無で、
   現状これを機械判定する経路は無い (失敗した MCP 呼出の結果が transcript 上で
   どう見えるかは未調査)。snapshot 4 の時点で手で確認し、1 件でもあれば切り替える。
   **0 件なら保留を続ける** — 「使われていないから配る」は根拠にならない

## 結果

### 利点

- 軽作業の委譲コストが実質ゼロになる (ローカル推論、API 課金なし)
- PR #95 で失った「軽作業を安く処理する」手段が、より安い形で戻る
- 指標が local-llm を数えるようになり、`delegation 0%` の誤読が解消される

### 欠点

- local-llm 不達時の挙動が 1 つ増える (fallback rule)
- delegation 指標の定義が再び変わり、snapshot 3 以前と比較できなくなる
- local-llm を持たない利用者には §3 の指示が無効になる (未解決の問い 5)

## 参照

- ADR-0015 (指示面の削減と発火実測) §E / item 4
- `docs/step-6-items/item-4-subagent-cost-measurement.md` (Haiku 委譲の実コスト)
- `docs/step-6-items/snapshot-3-analysis.md` (local-llm の利用痕跡と指標の不可視)
- `docs/step-6-items/local-llm-implementation-plan.md` (実装 PR a/b/c/d)
- ADR-0003 (self-contained 原則、ASCII only / PS 5.1 互換)
