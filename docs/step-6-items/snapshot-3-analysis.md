# snapshot 3 解析 — 1 → 2' → 3 の遷移

**取得日**: 2026-10-27 / **window**: 2026-10-20 - 10-27 / **解析日**: 2026-10-27

## 結論から 3 点

1. **削減後の計測としては有効**。配布は 10-17 14:08、window は 10-20 以降なので
   全体が削減後に収まっている。snapshot 2' → 3 は設計どおり「削減効果」の比較になる
2. **ただし plan-first は下がった** (42.4% → 22.2%)。本 kit 単体では **12.5% (2/16)**。
   ADR-0015 Step 5 の「守られなくなった rule = 本物の有効ルール」に該当しうる
3. **delegation 0% は「委譲しなかった」ではない。** local-llm MCP への委譲が
   **9 件**発生しているが、指標がそれを数えていない

## 数値の遷移

| # | 取得日 | turns | cost | **cost/turn** | Haiku turns | plan-first | delegation | commit-conv |
|---|---|--:|--:|--:|--:|--:|--:|--:|
| 1 | 10-06 | 1,886 | $2,213.32 | $1.173 | 20 (1.1%) | 55.6% (40/72) | 0% (0/159) ¹ | 100% (40/40) |
| 2 | 10-07 | 1,608 | $1,939.51 | $1.206 | 20 (1.2%) | 57.8% (37/64) | 0% (0/147) ¹ | 100% (39/39) |
| 2' | 10-16 | 3,992 | $5,401.61 | $1.353 | 21 (0.5%) | 42.4% (53/125) | 2% (5/247) ¹ | 83.3% (70/84) ² |
| 3 | 10-27 | 894 | $804.51 | **$0.900** | **0 (0%)** | **22.2% (10/45)** | **0% (0/57)** ³ | 100% (6/6) |

¹ 旧分母 (git commit 呼出 + 大出力) / ² 抽出器修正前 / ³ 新分母 (大出力のみ)

### cost は −$4,597 だが、ほぼ稼働量の差

raw の削減額 **−$4,597 (−85%)** は turns が 3,992 → 894 (**−78%**) に減ったことが
主因である。1 turn あたりに正規化すると:

```
$1.353 -> $0.900   (-33.5%)
```

**向きは削減と整合する**が、本設計では帰属できない。同 window の作業内容が
入れ替わっている (下記) ため、指示面の縮小だけの効果とは言えない。pricing は
`scripts/pricing.psd1` の概算で billing 照合には使えない点も変わらない。

## プロジェクト構成 (PR #87 の内訳、必須確認)

| Project | Rows | Share | prompts |
|---|--:|--:|--:|
| `C:\dev\hx99g-local-llm` | 473 | 33.1% | 4 |
| `C:\Users\t_tamaki` (配下合算) | 303 | 21.2% | 22 |
| **`engineer-claude-kit`** | **198** | **13.8%** | **15** |
| `tackt` | 195 | 13.6% | 2 |
| `dev-templates` | 134 | 9.4% | 2 |
| `contact-position-detector` | 111 | 7.8% | 1 |

snapshot 2' では `dev-templates` + `semantic-system` が 90% 近くを占めていた。
**3 回連続で構成が入れ替わっている**ため、全プロジェクト合算の比較は今後も
そのままでは成立しない。

### プロジェクト別 plan-first

| Project | plan-first |
|---|--:|
| `hx99g-local-llm` | 100% (4/4) |
| **`engineer-claude-kit`** | **12.5% (2/16)** |
| `tackt` | 50% (1/2) |
| `dev-templates` | 0% (0/2) |
| `contact-position-detector` | 0% (0/1) |

> `C:\Users\t_tamaki` を filter にすると配下の全プロジェクトに部分一致する
> (`-ProjectFilter` は `Contains` 判定)。上表はその行を除いた内訳である。

**本 kit 単体で 12.5% (2/16)** は全体の 22.2% よりさらに低い。構成の入れ替わりで
説明できる範囲を超えている可能性が高く、**削減が plan-first を悪化させた**という
読みが最も素直である。

## delegation 0% の正しい読み方

### 定義変更の artifact ではない

PR #95 (10-26 merge) で分母を「大出力のみ」に変えたため、報告の `-2 pt` は
定義をまたいだ比較で無効である。そこで**旧定義で再計算**した。

```
旧定義 (git commit 呼出 + 大出力 / commit-msg + lint-helper + log-summary): 0/62 = 0%
```

**旧定義でも 0% である。** 2% (snapshot 2') からの低下は定義変更の影響ではない。

### 本 kit では「not exercised」

| | 値 |
|---|--:|
| 8,000 字超の出力 (log-summary の分母) 全体 | 56 件 |
| うち `hx99g-local-llm` | 32 件 |
| うち **`engineer-claude-kit`** | **0 件** |

本 kit の `DelegationLogEligible` は **0** なので、delegation は 0% ではなく
**「該当イベントなし」**である。ADR-0015 §E の「not exercised は削除根拠に
ならない」がそのまま当てはまる。

### 指標が local-llm を数えていない (最重要)

本 window の tool 使用に **local-llm MCP が既に現れている**。

| tool | 回数 |
|---|--:|
| `mcp__local-llm__local_llm__generate_commit_message` | 5 |
| `mcp__local-llm__local_llm__chat` | 2 |
| `mcp__local-llm__local_llm__health` | 2 |

`Get-RuleMetrics` は `Agent` / `Task` の `subagent_type` しか見ない
(`$script:RuleMetricsAgentTools = @('Agent', 'Task')`)。**`mcp__*` は一切数えて
いない。**

したがって snapshot 3 の `delegation 0%` の意味は

> 委譲が起きなかった

ではなく

> **測っている宛先への委譲が起きなかった。実際には 7 件 (health を除く) が
> local-llm に向いており、指標はそれを見ていない**

である。ADR-0016 がこの不可視を解消する。

## Haiku rate 0% の解釈

まず**判定表の cell が違う**。PR #94 の判定表は `delegation` (rule 遵守率) の表で、
`Haiku rate` は `Get-UsageMetrics` 側の別指標 (assistant turn のうち Haiku の割合)
である。混同しないこと。

本 window の model 内訳:

```
Opus    913 turns
(none)    2 turns
Haiku     0 turns
```

**Haiku turn はゼロ**。これは PR #95 で緩和した §3 の**期待どおりの結果**である。
新しい §3 は commit message と小さな整形を main で書くよう指示しており、委譲は
8,000 字超の出力要約に限定される。本 kit にその該当が 0 件なら、Haiku 0 は正常な
帰結であって未遵守ではない。

### 副作用: plain-language hint が §3 と矛盾している

snapshot 3 のレポートには次が出ている。

> commit message やログ要約のような単純作業も、複雑な分析と同じ AI で処理しています。
> 電卓で済む計算を博士号に頼んでいる状態です。

> 複雑じゃない仕事まで一番頭のいい人 (Opus) に任せている状態です。

**どちらも現在の §3 と矛盾する。** §3 は「commit message は自分で書く」と指示して
いるのに、hint は委譲を勧めている。PR #95 で文面を変えたとき
`scripts/lib/plain-language-hints.json` の `HaikuZero` / `OpusHeavy` を更新し忘れた
ためである。**ADR-0016 の実装 PR (c) で合わせて直す。**

## PR #94 判定表への照合

| snapshot 3 の delegation | 該当 | 判定表の行 |
|---|---|---|
| 0% | ✓ | **「0 - 5% (ほぼ変化なし)」→ 案 A を実行** |

ただし本 kit 単体では `DelegationLogEligible = 0` なので、厳密には
**「計測不能 (本 kit の占有率が極小)」の行にも該当する**。どちらに読んでも
行動は変わらない。

**案 A は既に実行済である** (PR #95、10-26 merge → 本日 apply)。判定表の指示は
完了しており、snapshot 3 はその妥当性を事後に裏づけた形になる。

- Haiku 0 turns + delegation 0% は「緩和前の指示が守られていなかった」ことの確認
- 同時に local-llm への 7 件は「**委譲先を変えれば使われる**」ことの最初の証拠

## local-llm の window カバレッジ

**本 snapshot に含まれる local-llm 稼働は 10-26 以降の約 2 日分のみ**である
(Phase 1/2 の稼働開始が 10-26)。window は 10-20 - 10-27 なので、7 日のうち
**2 日 (約 29%)** しか反映されていない。

9 件の tool 呼出はその 2 日で発生したものであり、定常状態の利用頻度を示す数字と
しては扱えない。

### snapshot 4 (2026-11-03 以降) の見込み

| | snapshot 3 | snapshot 4 の見込み |
|---|---|---|
| local-llm 稼働日数 | 2 / 7 日 | **7 / 7 日** |
| local-llm tool 呼出 | 9 件 | 不明 (2 日で 9 件なら線形外挿で 30 件前後) |
| Haiku turns | 0 | 0 のまま (§3 が Haiku 委譲をほぼ求めない) |
| cost/turn | $0.900 | **削減の初期 signal が出る見込み** |

snapshot 4 が **local-llm 稼働後の初回の完全な window** になる。ADR-0016 の
実装 PR (d) を入れておけば、local-llm への委譲件数が指標に乗った状態で測れる。

## 未解決の問い

1. plan-first の悪化が削減由来かを切り分けられていない。本 kit 単体 12.5% は
   母数 16 で、ノイズフロア (±2 pt は全体集計での値) を当てられない
2. plan-first を戻すか。ADR-0015 Step 5 は「守られなくなった rule は戻す」と
   しているが、戻す対象は CLAUDE.md §2 (4 行) で、削減量は小さい。費用対効果の
   判断が必要
3. cost/turn の −33.5% を削減に帰属できない。workload 構成が毎回変わるため、
   `-ProjectFilter` 単位の cost 集計 (現在は未実装) が必要

## 関連

- ADR-0015 §A (snapshot 表) / §E (指標の定義と限界)
- ADR-0016 (local-llm への委譲先変更)
- `docs/step-6-items/snapshot-2prime-analysis.md` (構成入れ替わりの前例)
- `docs/step-6-items/item-4-decision.md` (判定表)
- `docs/step-6-items/item-4-subagent-cost-measurement.md` (委譲コストの実測)
