# item 4: 委譲ルールの判断手順 (snapshot 3 後に実行)

**作成日**: 2026-10-17 / **ステータス**: 判断待ち。実行は snapshot 3 取得後

本書は `item-4-haiku-delegation-relaxation.md` (当初 draft) と
`item-4-subagent-cost-measurement.md` (実コスト測定) を踏まえ、**何を見たらどう
決めるか**を事前に固定するものである。測ってから決める原則に従い、判断基準を
データが出る前に書いておく。

## 既に確定している事実

### 1. 委譲は commit message では損

| | 1 回あたり |
|---|--:|
| sub-agent (Haiku) へ委譲 | $0.082 - $0.120 |
| main (Opus) が自分で書く | $0.023 - $0.060 |

**約 1.4 - 5 倍高い。** 理由は cacheCreate が 76.1% を占めること。sub-agent prompt
は self-contained を要求されるため main の cache を使えず、6 起動のうち 3 件は
`cacheRead = 0` の完全 cold start だった。外部レビューの仮説は裏付けられた。

### 2. ただし log 要約では得

判定軸は作業の軽重ではなく **「大きな入力を main の context から締め出せるか」**。

| 作業 | 締め出せるか | 損得 |
|---|---|---|
| commit message | いいえ (diff は main が既に見ている) | 損 |
| 小さな整形 | いいえ | 損 |
| 8,000 字超の build / test 出力の要約 | はい | 得 |

### 3. 「必ず委譲」は事実上機能していない

| snapshot | delegation |
|---|--:|
| 1 (配布前) | 0% (0/159) |
| 2 (配布直後) | 0% (0/147) |
| 2' (配布後) | 2% (5/247) |

## snapshot 3 で初めて分かること

snapshot 3 (2026-10-24 14:08 以降) は **削減版 rule が配布された状態での初回計測**
である。ここで分かるのは次の 1 点だけ。

> CLAUDE.md が 8,291 B から 3,763 B に縮んだあと、**委譲の遵守率が動くか**

縮小で §3 の委譲指示は表から散文 1 行になった。指示が短くなって守られやすく
なるのか、埋もれて守られにくくなるのかは、まだ観測していない。

### 併せて見る必要があるもの

PR #87 で入れた **プロジェクト別内訳**を必ず確認する。snapshot 1 → 2' の低下が
window のプロジェクト構成の入れ替わりで説明できた前例があるため、本 kit の
占有率が前回と大きく違えば、delegation の変化も構成由来の可能性がある。

```powershell
. .\scripts\usage-insights.ps1
$rows = Get-InsightsScope -WindowDays 7 -IncludeRuleMetrics
Get-ProjectMix -Entries $rows | Select-Object -First 5
Get-RuleMetrics -Entries $rows -ProjectFilter 'engineer-claude-kit'
```

## 判断表

snapshot 3 の `delegation` と、PR #90 で確定した**コストの向き**を組み合わせる。
**コストの結論は snapshot 3 の結果では変わらない** (実測であり、指示文面とは独立)
ので、判断は「文面をどう直すか」だけになる。

| snapshot 3 の delegation | 読み方 | 採る行動 |
|---|---|---|
| **0 - 5%** (ほぼ変化なし) | 縮小しても守られない。文面の長短が原因ではない | **案 A を実行** (下記)。守られない指示を残す意味がない |
| **6 - 30%** (上昇) | 縮小で読まれるようになった。ただし損な委譲が増えただけの可能性 | **案 A を実行**。遵守率が上がること自体は目的ではない。損な行動の遵守率が上がるのは悪化 |
| **30% 超** | 大幅に守られ始めた | **案 A を実行**。上と同じ理由。加えてコスト影響を次の snapshot で確認 |
| 計測不能 (本 kit の占有率が極小) | 判断材料にならない | 文面変更は保留し、`-ProjectFilter` で本 kit 分の母数が貯まるまで待つ |

**どの枝でも案 A に収束する。** それは snapshot 3 が答えるのが「遵守率」で、
**委譲が損か得かはコスト実測で既に決着している**ためである。snapshot 3 を待つ
理由は、文面を変える前後で測定を混ぜないという一点に尽きる。

> 逆に言えば、**snapshot 3 を待たずに案 A を入れてもコスト判断は変わらない**。
> 待つ目的は「削減効果」と「緩和効果」を snapshot 2' → 3 → 4 で分離することだけ
> である。急ぐ理由があるなら snapshot 3 の取得を先に済ませて即日入れればよい。

## 案 A: 委譲条件を「入力の締め出し」で書き直す

```diff
-main agent は Opus 5。以下は **必ず** Haiku sub-agent へ委譲する (判断の余地なし):
-commit message → `commit-msg` / 小さな整形 (typo・フォーマット・import 整理) →
-`lint-helper` / build・test・lint 出力の要約 → `log-summary`。単純な事実確認は直接 Haiku。
+main agent は Opus 5。**大きな入力を自分の context に載せたくない**ときに Haiku
+sub-agent へ委譲する: 8,000 字を超える build / test / lint 出力の要約 →
+`log-summary`。
+
+commit message と小さな整形は **自分で書く**。diff は既に context にあるので
+委譲しても締め出せるものがなく、sub-agent は self-contained prompt のため cache を
+作り直す。実測で委譲 $0.082-0.120/回 に対し自分で書くと $0.023-0.060/回
+(docs/step-6-items/item-4-subagent-cost-measurement.md)。
```

### 同時に必要な指標側の変更 (必須)

`DelegationEligible` は現在 `git commit` 呼出を分母に含む。案 A を入れると
commit message の委譲は**推奨されなくなる**ので、分母に残すと「遵守率が下がった」
と誤読される。

- `$script:RuleMetricsHaikuAgents` から `commit-msg` / `lint-helper` を外す
- `DelegationCommitEligible` を分母から外し、大出力 (`DelegationLogEligible`) のみを
  分母にする
- 変更は 1 PR にまとめる。指標だけ先に変えると過去の snapshot と比較できなくなる

### sub-agent 定義の扱い

`templates/agents/commit-msg.md` と `lint-helper.md` は**削除しない**。明示的に
呼びたい場面 (context を汚さずに大量 commit を一括生成する等) は残るため、
「既定では使わない」に下げるだけにする。

## 案 B (却下): 現状維持

| | 利点 | 欠点 |
|---|---|---|
| 現状維持 | 文面が明快。変更コストゼロ | **実測で損と分かっている行動を指示し続ける**。かつ 3 回の snapshot すべてで守られていない |

却下理由は「守られていないから」ではなく **「守られたら損をするから」**。遵守率
0% の指示を残すことの害は、指示面を無駄に占めることと、守った場合にコストが
増えることの両方である。

## 案 C (却下): 委譲を全面禁止

log 要約の委譲は実測で得なので、それも失う。ADR-0015 §E の「測れないルールは
効いている前提で残さない」は「測って損と分かったものは残さない」と対になるが、
**得と分かったものを捨てる理由はない**。

## 実行手順 (snapshot 3 取得後)

1. snapshot 3 を取得し、ADR-0015 §A の snapshot 表に追記する
2. プロジェクト別内訳を確認し、本 kit の占有率が snapshot 2' と大きく違わないか見る
3. 判断表に従う (どの枝でも案 A)
4. 案 A + 指標側の変更を 1 PR で入れる
5. その 7 日後に snapshot 4 を取得し、緩和の効果 (委譲コストの減少) を確認する

## 未解決の問い

1. 8,000 字という閾値は `$script:RuleMetricsLargeResultChars` の流用で、log 要約の
   損得分岐点として検証したものではない。snapshot 4 以降で調整する
2. `commit-msg` 4 件と `log-summary` 1 件を厳密に分離できていない (起動の
   グルーピングが時刻ベースの推定)。`parentUuid` を辿れば正確に紐付く
3. main が commit message を書くときの実 output token を測っていない (300-800 は
   見積り)。`git commit` を含む turn の output token を見れば実測できる

## 関連

- `docs/step-6-items/item-4-subagent-cost-measurement.md` (実コスト)
- `docs/step-6-items/item-4-haiku-delegation-relaxation.md` (当初 draft)
- `docs/step-6-items/snapshot-2prime-analysis.md` (構成由来の変動の前例)
- `docs/setup/snapshot-procedure.md` (取得手順と判定基準)
- ADR-0015 §A / §E
