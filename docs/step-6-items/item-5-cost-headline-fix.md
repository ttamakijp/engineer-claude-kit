# Step 6 項目 5: 費用の見出しを実測値に揃える (draft)

**ステータス**: 提案のみ。実装着手は user の指示待ち。

> **スコープの確認**: 本項目は外部レビュー 7 項目のうち「README の −80% という
> 見出し」を指す。dispatch では「insights-report の cost headline 計算修正」と
> 表現されていたが、`Format-InsightsReport` の cost 行は計算そのものは正しく
> (pricing.psd1 の単価 × token 数)、問題は**単価が概算である旨の提示の弱さ**にある。
> 両方を対象として扱い、README を主、insights レポートを従とする。

## 背景

外部レビューの指摘:

> README の −80% は pricing 概算 + human-pace 想定の上に立つ → 社内で配ると数字が
> 一人歩きする。見出しを「1h TTL で cache miss が消える分」と効果の中身で書く、
> $ は「概算」と並記。測ってない +α は書かない

## 現状

### README

`README.md` の「なぜ engineer-claude-kit が必要か」節:

| 構成 | engineering 想定 cost | 削減率 |
|---|--:|--:|
| Bedrock デフォルト (Sonnet 4.6 / 5m TTL / Haiku) | $310 | 基準 |
| Sonnet 4.5 + **1h TTL** + Haiku | $60 | **−80%** |
| 上記 + **engineer-claude-kit** | $60 + 質的改善 | **−80% + α** |

事実関係を分解すると 3 層が混ざっている。

| 要素 | 性質 |
|---|---|
| 1 日 432 turn / 44 session | **実測** |
| $310 / $60 | **pricing 概算**から導いた推計 (`scripts/pricing.psd1` は「web 確認待ち」と自称) |
| −80% | 上記推計の比 |
| **+α** | **未測定**。「質的改善」という語のみ |
| human-pace 前提 / orchestration では −7% | 注記として下部にある |

問題は 3 つある。

1. **−80% が実測値のように読める。** turn 数が実測なので、金額も実測に見える
2. **+α が測られていない。** 「−80% + α」は −80% より良いという主張になるが、
   α の実体は定義も測定もされていない
3. **−7% の注記が表の下にある。** orchestration 中心の workload では削減が
   −7% に縮むという最も重要な制約が、表を見た人の目に入らない位置にある

### insights レポート

`Format-InsightsReport` は Key findings の先頭に次を出す。

```
- Est. cost: USD 12.3456 (+5.2% vs last)
```

`Est.` は付いているが、**pricing が概算である旨は「Notes」節まで降りないと分からない**。
`$CostAvailable` が false のときだけ「pricing.psd1 not loaded」と出る設計で、
load できていれば単価の信頼性には触れない。

## 提案

### A. README: 見出しを「効果の中身」に差し替える

```diff
-| 構成 | engineering 想定 cost | 削減率 |
-|---|--:|--:|
-| Bedrock デフォルト (Sonnet 4.6 / 5m TTL / Haiku) | $310 | 基準 |
-| Sonnet 4.5 + **1h TTL** + Haiku | $60 | **−80%** |
-| 上記 + **engineer-claude-kit** | $60 + 質的改善 | **−80% + α** |
+**効果の中身: turn 間隔が 5 分を超えると 5m TTL の cache は毎 turn 切れ、
+その都度 input 全体を再課金する。1h TTL はこの再課金を消す。**
+
+| 構成 | cache 再課金 | 概算 cost (実測 workload × pricing 概算) |
+|---|---|--:|
+| Bedrock デフォルト (5m TTL) | 毎 turn 発生 | 約 $310 |
+| 1h TTL + Haiku 委譲 | ほぼ発生しない | 約 $60 |
+
+- **実測なのは workload (1 日 432 turn / 44 session) のみ。** 金額は
+  `scripts/pricing.psd1` の概算単価による推計で、billing 照合には使えない
+- **この効果は human-pace (思考しながらの単独セッション) 前提。**
+  orchestration 中心 (子タスク並行) の workload では縮小し、実測では約 −7% だった
+- kit 自体の付加価値は cost ではなく運用の自動化と構造的保護 (下表)
```

主な変更は 4 点。

- 見出しを「−80%」から「cache 再課金が消える」という**機構の説明**に変える
- 金額に「概算」「約」を明示し、実測なのは workload だけだと書く
- **「+α」の行を削除する。** 測っていない値を表に置かない
- −7% の制約を表の**直後**に移す

### B. insights レポート: cost 行に概算であることを常時明記

```diff
-    $costLine = if ($Metrics.CostAvailable) { "Est. cost: USD $($Metrics.TotalCost) ($CostTrend)" } else { ... }
+    $costLine = if ($Metrics.CostAvailable) { "Est. cost: USD $($Metrics.TotalCost) ($CostTrend) -- concept pricing, not for billing reconciliation" } else { ... }
```

Key findings は session 冒頭で要約提示される 3-5 行 (ADR-0014 / CLAUDE.md §9) なので、
ここに注記がないと「概算」が読者に届かない。

### C. cost 比較の再実測を待たずに文面だけ直す

pricing の web 確認 (ADR-0014 の TBD) は未完了で、いつ終わるか未定である。
文面の修正は再実測を待つ必要がない — むしろ**待つあいだ誤読が続く**ため、文面を
先に直すのが筋である。

## trade-off

| 案 | 利点 | 欠点 |
|---|---|---|
| A (README 書き換え) | 誤読と数字の一人歩きが止まる。機構の説明は再実測でも陳腐化しない | 「−80%」という訴求力の強い見出しを失う。社内配布時のインパクトが落ちる |
| B (insights 注記) | 冒頭要約に注記が乗る。実装は 1 行 | Key findings が 1 行長くなる。冗長に感じる可能性 |
| C (再実測を待たない) | すぐ直る | 「正しい数字」は依然として未取得のまま |

A の欠点は実在する。−80% は実際に起きうる削減であり、それ自体は誤りではない。
失われるのは「断定的に見える提示」であって、効果そのものではない。社内配布で
数字が一人歩きしたときのコスト (誤った期待、後からの訂正) のほうが大きいと判断する。

B は「Notes に書いてあるので十分」という反論がありうる。しかし Key findings は
**session 冒頭で Claude が要約して提示する**設計なので、Notes まで読まれる保証がない。

## 実装イメージ

1. **README を先に直す** (A)。単独 PR、`docs:` scope。実装リスクゼロで効果が即出る
2. 同 PR で `docs/cost-analysis.md` 側の見出しも同様に点検する (README が参照している)
3. B は `lib/insights-report.ps1` の 1 行変更 + 既存テスト
   (`Format-InsightsReport plain-language hints` 系) への影響確認
4. pricing の web 確認が終わった時点で金額を更新し、「概算」の語を外すか判断する

## 未解決の問い

1. −7% の実測はどの workload で取ったのか。`docs/cost-analysis.md` に根拠があるなら
   README から明示的に参照したい
2. 「+α」として意図されていた質的改善は何だったのか。運用自動化 (下表) が
   それならば表の +α 行は冗長で、削除して下表に集約するのが正しい
3. `pricing.psd1` の単価はいつ時点のものか。ファイル内に取得日が書かれていなければ
   追記したい (概算の鮮度が分からないと「概算」の意味が薄れる)

## 関連

- `README.md` 「なぜ engineer-claude-kit が必要か」節
- `docs/cost-analysis.md` (実測詳細・計算根拠)
- `scripts/pricing.psd1` (概算単価、web 確認待ち)
- `scripts/lib/insights-report.ps1` (`Format-InsightsReport` の cost 行)
- ADR-0014 (usage insights / pricing は相対比較専用)
