# Step 6 項目 4: Haiku 委譲の「必ず」を緩和する (draft)

**ステータス**: 提案のみ。実装着手は snapshot 3 取得後の判断次第。

## 背景

CLAUDE.md §3 は commit message / 小さな整形 / ログ要約を「**必ず** Haiku sub-agent へ
委譲する (判断の余地なし)」と規定している。外部レビューはこの「必ず」に次の疑義を
呈した:

> Commit message の委譲は sub-agent 起動のたびに cache のない context を読み直す
> → main で書くより高くつく可能性

ADR-0015 Step 2 で導入した `DelegationRate` がこの疑義を実測で裏付けた。

## 現状

| snapshot | 取得日 | delegation |
|---|---|--:|
| 1 (配布前) | 2026-10-06 | **0% (0/159)** |
| 2 (配布直後) | 2026-10-07 | **0% (0/147)** |

7 日間で委譲対象イベント 147-159 件に対し、`commit-msg` / `lint-helper` /
`log-summary` の起動は **1 件もない**。sub-agent 起動自体は期間中 1 件
(`claude-code-guide`) のみだった。

つまり「必ず」は**文面として存在するだけで一度も機能していない**。これは
ADR-0015 §E が定義した「測れないルールは効いている前提で残さない」の典型例である。

重要な区別が 2 つある。

1. **未遵守なのか、不適切なのか。** 0% は「Claude が指示に従わなかった」とも
   「従うべきでない状況が続いた」とも読める。前者なら文面の強化、後者なら緩和が
   正しい処置になる。
2. **cache の経済性。** sub-agent は self-contained prompt を要求されるため
   (CLAUDE.md §4)、main の温まった cache を使えない。commit message 生成のために
   diff を読み直すコストが、Haiku の単価差で回収できるかは未測定である。

## 提案

### A. 文面を「必ず」から条件付きに変える (推奨)

```diff
-main agent は Opus 5。以下は **必ず** Haiku sub-agent へ委譲する (判断の余地なし):
-commit message → `commit-msg` / 小さな整形 (typo・フォーマット・import 整理) →
-`lint-helper` / build・test・lint 出力の要約 → `log-summary`。単純な事実確認は直接 Haiku。
+main agent は Opus 5。入力が大きく出力が短い作業は Haiku sub-agent へ委譲する:
+diff が 200 行を超える commit message → `commit-msg` / 複数ファイルにまたがる整形 →
+`lint-helper` / 8,000 字を超える build・test 出力の要約 → `log-summary`。
+それ以下の規模は委譲往復のほうが高くつくため自分で処理する。
```

閾値を入れる理由は 2 つある。第一に `DelegationRate` の分母が
「`git commit` を含む Bash 呼出」「8,000 字超の tool 出力」で定義されており、
後者はそのまま流用できる。第二に「判断の余地なし」を外すと単に守られなくなるだけ
なので、守るべき境界を数値で示す必要がある。

### B. 指標側の分母を提案 A に合わせる

現在の `DelegationEligible` は `git commit` 呼出すべてを数えている。提案 A を入れる
なら、分母も「diff が閾値を超えた commit」に絞らないと、緩和しただけで数値が
改善したように見えてしまう。`lib/rule-metrics.ps1` の
`$script:RuleMetricsLargeResultChars` と同様に閾値を定数化し、`BashCommand` から
`git diff --cached --stat` 相当の情報は取れないため、**代替として commit message の
行数**を使う案がある (長い本文を書いた commit は大きい変更であることが多い)。

### C. 1 週間の A/B 測定を先に行う

文面を変えずに、1 週間だけ意識的に委譲してみて `DelegationRate` と token / cost を
snapshot で比較する。測ってから決める、という ADR-0015 の原則には最も忠実。

## trade-off

| 案 | 利点 | 欠点 |
|---|---|---|
| A (条件付きに緩和) | 守れる文面になる。閾値が検証可能 | 閾値の根拠が未実測。緩和が「諦め」に見える |
| B (分母を揃える) | 指標が自己正当化しなくなる | A と同時でないと意味がない。実装コストが増える |
| C (先に A/B 測定) | 根拠が実測になる | 1 週間余計にかかる。意識的な委譲は自然な運用ではないためバイアスが入る |

A を単独で入れる最大のリスクは、**「高くつく」という疑義自体が未検証**のままである
こと。外部レビューの指摘は妥当に見えるが、sub-agent の cache miss コストと Haiku の
単価差を実測した数字はまだない。

逆に C を待つ最大のリスクは、0% が「指示が守られていない」側の説明だった場合、
その 1 週間も 0% のまま過ぎることである。

## 実装イメージ

1. **測定の分離を先に済ませる** — snapshot 3 (削減後) を取るまで文面を変えない。
   削減効果と緩和効果が混ざると、どちらが効いたか分からなくなる
2. snapshot 3 の後に提案 A + B を 1 PR で入れる。A だけでは指標が甘くなる
3. 同じ PR で `rule-metrics.ps1` に `DelegationSkippedSmall` (閾値未満で委譲対象外と
   判定した件数) を追加し、緩和後も「対象なのに委譲しなかった」件数を追えるようにする
4. 閾値 (diff 200 行 / 出力 8,000 字) は初期値として置き、snapshot 4 以降で調整する

## 未解決の問い

1. sub-agent 1 回の実コストは? `isSidechain=true` の行に `message.usage` があるので
   transcript から算出できる。期間中 43 行しかないためサンプルは少ない
2. 0% の原因は未遵守か不適切か。transcript から「commit message を自分で書いた turn」
   の output token を見れば、委譲すべき規模だったかの目安は出る
3. `commit-msg` / `lint-helper` / `log-summary` の 3 sub-agent 定義自体を残すか。
   緩和後も使われないなら `templates/agents/` から外す判断もありうる

## 関連

- ADR-0015 §E (指標の定義) / snapshot 表
- `templates/CLAUDE.md` §3
- `scripts/lib/rule-metrics.ps1` (`$script:RuleMetricsHaikuAgents`)
- `templates/agents/commit-msg.md` / `lint-helper.md` / `log-summary.md`
