# item 4: sub-agent 委譲の実コスト測定

**測定日**: 2026-10-17 / **window**: 直近 14 日 / **ステータス**: 実装は user の指示待ち

## 測定の動機

外部レビューの指摘:

> Commit message の委譲は sub-agent 起動のたびに cache のない context を読み直す
> → main で書くより高くつく可能性

`docs/step-6-items/item-4-haiku-delegation-relaxation.md` では、この前提自体が
**未検証**であることを未解決の問い 1 として記録していた。snapshot 2' で
`commit-msg` が 4 回呼ばれたため、`isSidechain=true` 行の `message.usage` から
実コストを算出できるようになった。

## 測定結果

### sub-agent の起動実績 (直近 14 日)

| sub-agent | 起動回数 |
|---|--:|
| `commit-msg` | 4 |
| `log-summary` | 1 |
| `claude-code-guide` | 1 |

sidechain 行は 41 行 (main は 7,132 行)。model は **全 41 行が Haiku** だった。

### token と金額

`claude-code-guide` は調査用途で規模が別物なので除外し、`commit-msg` x4 +
`log-summary` x1 の 5 起動で集計する。

| | 合計 | 1 起動あたり |
|---|--:|--:|
| input | 190 | 38 |
| output | 16,706 | 3,341 |
| cacheCreate | 250,024 | 50,005 |
| cacheRead | 143,526 | 28,705 |

`scripts/pricing.psd1` の概算単価 (Haiku) を当てた金額:

| cache write | 5 起動合計 | **1 起動あたり** |
|---|--:|--:|
| 5m TTL 前提 | $0.411 | **$0.082** |
| 1h TTL 前提 | $0.598 | **$0.120** |

### コスト構成が答えを示している

| 項目 | 金額 | 比率 |
|---|--:|--:|
| input | $0.0002 | 0.0% |
| output | $0.0835 | 20.3% |
| **cacheCreate** | **$0.3125** | **76.1%** |
| cacheRead | $0.0144 | 3.5% |

**cacheCreate が 76% を占める。** 6 起動のうち 3 起動は `cacheRead = 0`、つまり
完全な cold start だった。sub-agent prompt は self-contained を要求される
(CLAUDE.md §4) ため、main の温まった cache を一切使えず、毎回自分の context を
作り直している。これがレビューの言う「cache のない context を読み直す」の実体で、
金額としてもここが支配的である。

### main (Opus) が自分で書く場合の増分

context は既に warm なので cache の追加費用は発生せず、増分は output token だけ。

| output token | 増分 |
|--:|--:|
| 300 | $0.023 |
| 500 | $0.038 |
| 800 | $0.060 |

### 結論

| | 1 回あたり |
|---|--:|
| sub-agent (Haiku) へ委譲 | **$0.082 - $0.120** |
| main (Opus) が自分で書く | **$0.023 - $0.060** |

**委譲のほうが約 1.4 - 5 倍高い。** Haiku の単価は Opus の 1/15 だが、
cacheCreate を毎回払うため総額では逆転する。**レビューの仮説は実測で裏付けられた。**

## ただし「委譲しない」が正解ではない

5 起動のうち 1 件は `log-summary` で、これは性質が違う。

commit message の委譲では、main は **diff を既に見ている**。委譲しても main の
context から diff が消えるわけではないので、sub-agent の cacheCreate は純粋な
追加コストである。

一方 log 要約の委譲では、**8,000 字超の出力を main の context に載せずに済む**。
載せてしまえばそれは main の context に残り、以降の cacheCreate (Opus は 1h write
で $30/M) に毎回乗り続ける。1 回の委譲コストと、main の context に恒久的に
積む負債を比べる話になる。

つまり判定軸は「作業が軽いか」ではなく **「大きな入力を main の context から
締め出したいか」** である。

| 作業 | 大きな入力を締め出せるか | 委譲の損得 |
|---|---|---|
| commit message | いいえ (diff は main が既に見ている) | **損** |
| 小さな整形 (typo / import) | いいえ | **損** |
| 大きな build / test 出力の要約 | **はい** | **得** |

## 提案

CLAUDE.md §3 の委譲条件を、作業の軽重ではなく **入力の締め出し**で書き直す。

```diff
-main agent は Opus 5。以下は **必ず** Haiku sub-agent へ委譲する (判断の余地なし):
-commit message → `commit-msg` / 小さな整形 (typo・フォーマット・import 整理) →
-`lint-helper` / build・test・lint 出力の要約 → `log-summary`。単純な事実確認は直接 Haiku。
+main agent は Opus 5。**大きな入力を自分の context に載せたくない**ときに Haiku
+sub-agent へ委譲する: 8,000 字を超える build / test / lint 出力の要約 →
+`log-summary`。大量ファイルの横断調査 → `Explore`。
+
+commit message と小さな整形は **自分で書く**。diff は既に context にあるので
+委譲しても締め出せるものがなく、sub-agent は self-contained prompt のため
+cache を作り直す。実測で委譲 $0.082-0.120/回 に対し自分で書くと $0.023-0.060/回
+(詳細: docs/step-6-items/item-4-subagent-cost-measurement.md)。
```

`commit-msg` / `lint-helper` の sub-agent 定義自体は残す。明示的に呼びたい場面
(context を汚さずに大量の commit を一括生成する等) は残るため、削除ではなく
「既定では使わない」に下げる。

## trade-off

| | 利点 | 欠点 |
|---|---|---|
| この提案 | 判定軸が実測に基づく。守れる文面になる | 「必ず」の明快さを失う。判断が入る余地が戻る |
| 現状維持 | 文面が明快 | 実測で損と分かっている行動を指示し続ける。かつ 14 日で 4 回しか守られていない |
| 全面削除 | 最小 | log 要約の委譲は実際に得なので、それも失う |

`DelegationRate` の分母も合わせて見直す必要がある。現在は `git commit` 呼出を
分母に入れているが、提案後は commit message の委譲は**推奨されない**ので、
分母から外さないと「遵守率が下がった」ように見える。

## 未解決の問い

1. `commit-msg` 4 件と `log-summary` 1 件を厳密に分離できていない。起動の
   グルーピングは「同一ファイル内で 10 分以内に連続する sidechain 行」という
   時刻ベースの推定である。`parentUuid` を辿れば正確に紐付けられる
2. 8,000 字という閾値は `$script:RuleMetricsLargeResultChars` の流用で、
   log 要約の損得分岐点として検証したものではない
3. main が commit message を書くときの実際の output token を測っていない
   (300-800 は見積り)。`git commit` を含む turn の output token を見れば実測できる

## 関連

- `docs/step-6-items/item-4-haiku-delegation-relaxation.md` (当初の draft)
- `docs/step-6-items/snapshot-2prime-analysis.md` (delegation 2% の解析)
- `templates/CLAUDE.md` §3 / §4
- `scripts/pricing.psd1` (概算単価。billing 照合には使えない)
