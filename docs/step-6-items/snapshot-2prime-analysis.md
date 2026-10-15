# snapshot 2' 解析と Step 6 のロードマップ

**取得日**: 2026-10-16 / **window**: 2026-10-09 - 10-16 (全体が apply 後) / **解析日**: 2026-10-16

## 結論から

**snapshot 1 → 2' の比較は配布効果の測定として成立していません。** 原因は rule が
効かなかったからではなく、**2 つの window の作業内容がほぼ別物**だからです。

plan-first の −13.2 pt と commit-convention の −16.7 pt は遵守率の劣化ではなく、
(a) window を占めるプロジェクトの入れ替わりと (b) commit subject 抽出の偽陽性で
説明できます。以下、実データで示します。

## 1. window の内訳 — 本 kit は 3.3% しかない

`cwd` でセッションを分類した結果:

| session | 行数 | cwd |
|---|--:|---|
| 8012efc6 | 5,119 | `dev-templates` |
| 3cc55d4c | 3,516 | `semantic-system` |
| **6de92116** | **319** | **engineer-claude-kit (本件)** |
| 71285395 | 164 | `~` |
| bedfcde3 | 157 | `r4-remote-spotify` |
| 0ce8e302 | 64 | `C:\dev` |
| e629c29b | 54 | `pal-for-mizusumashi-2026` |
| d73fe410 | 33 | `contact-position-detector` |

実ユーザ prompt は 8 session で 127 件、うち **engineer-claude-kit は 11 件 (8.7%)**、
行数ベースでは **3.3%** です。

snapshot 1 (10-06) は本 kit の作業が window の大半を占めていました。snapshot 2' は
`dev-templates` と `semantic-system` の作業が 90% 近くを占めます。

**指標は `~/.claude/projects/` 全体を集計するため、`~/.claude/` への変更の効果を
測るには workload の構成が安定している必要があります。していません。**

### 分母の変化がそれを裏付ける

| 指標 | snapshot 1 | snapshot 2' | 分母の伸び |
|---|--:|--:|--:|
| PlanFirstEligible | 72 | 125 | +74% |
| DelegationEligible | 159 | 247 | +55% |
| CommitExtracted | 40 | 84 | +110% |

plan-first は **hit 数自体は 40 → 53 に増えています**。率が下がったのは分母が
それ以上に増えたからです。「やらなくなった」のではなく「対象が倍増した」が実態です。

## 2. commit-convention −16.7 pt は抽出器の偽陽性

非適合と判定された 14 件を全件確認しました。**大半が commit subject ではありません。**

| 判定された「subject」 | 件数 | 実体 |
|---|--:|---|
| `git log --oneline -1` | 2 | 同一コマンド内の後続行 |
| `&& git add firmware/src/...` | 3 | 複数行に分かれたコマンド鎖の継続行 |
| `| | #25 論点 | 結論 |` 等の日本語散文 | 8 | heredoc 本文 (ADR / 報告書) の行 |
| `x` | 1 | ゴミ |

原因は `Get-CommitSubject` のヒューリスティックです。「`git commit` を含む行の次の
非空行が subject」と仮定していますが、

- `git add ... && \` のように**コマンド鎖が複数行**に分かれている
- 散文 heredoc の中に `git commit` の語が出てくる

場合に破綻します。PR #83 で `-m "$(cat <<MSG` 形式は直しましたが、穴が残っていました。

**したがって実際の遵守率は 83.3% より高い**はずです。14 件の偽陽性を除くと
70/70 = 100% に近づきます (厳密には未抽出分の検証が必要)。

さらに **133 回の `git commit` 呼出のうち 49 回 (37%) は subject を抽出できていません**。
盲点が大きく、この指標は現状「下がったら疑う」程度の信頼度しかありません。

## 3. plan-first の miss は調査作業の性質

text なしで着手した 73 turn の「最初の tool」:

| tool | 件数 |
|---|--:|
| Bash | 59 |
| PowerShell | 8 |
| その他 (Write / Grep / browser / ToolSearch 等) | 6 |

**67/73 (92%) がシェルコマンド**です。`dev-templates` と `semantic-system` の作業は
CI 調査・ログ確認が中心で、「まず 1 コマンド叩いて状況を見る」turn が大量にあります。
これは「実装前に方針を述べる」が適用される場面とは言えません。

指標の定義 (`IsUserPrompt` 直後の論理ターンに text が先行するか) が、調査 turn と
実装 turn を区別していないのが限界です。

## 4. Step 6 各項目への影響

### item 4 (Haiku 委譲の緩和) — 2% は緩和を正当化しない

```
delegation: 5/247 = 2%   (commit-msg=4, lint-helper=0, log-summary=1)
```

**初めて非ゼロになりました**が、これは緩和の根拠には**なりません**。

1. **5 件はすべて他プロジェクトの作業**です。本 kit セッションでの委譲は 0 件のままで、
   「必ず」が守られていないという状況は変わっていません
2. **「委譲は高くつく」という前提は依然として未検証**です。commit-msg が 4 回呼ばれた
   ので、その 4 件の sub-agent コストは `isSidechain=true` 行の `message.usage` から
   算出できるようになりました。**これを測るのが次の一手**です
3. 2% という数字は「ごく稀に使われる」ことを示すだけで、閾値を決める材料にはなりません

→ **item 4 は緩和を先行させず、まず 5 件の実コストを測る**ことを推奨します。
これは draft の案 C (A/B 測定) に近く、サンプルが 5 件でも「1 回あたり何 token か」は
出ます。

### item 5 (費用見出し) — 弱さが snapshot 2' で顕在化

レポートの Key findings 先頭:

```
- Est. cost: USD 5401.6135 (+3462.1007 vs prev weekly (2026-10-07))
- Opus cost share: 100% of model cost
```

pricing が概算である旨の注記は **L82 の Notes 節**にしかありません。一方 Key findings
は session 冒頭で Claude が要約提示する設計 (CLAUDE.md §9) なので、**$5,401 という
絶対額と +$3,462 という増加だけが目に入ります**。

これは draft が指摘した構造そのものです。README の `−80%` と同じ問題が、生成物側にも
出ています。**item 5 の案 B (cost 行に常時注記) の優先度は上がりました。**

### item 6 (pre-commit の除外) — 再確認完了、変化なし

`templates/.mailmap` のヒットは **4 件のまま**です。

```
proper@email.com / commit@email.com / t_tamaki@icloud.com / t.tamaki@example.com
```

draft の推奨 (値の許可リスト + 記入例の差し替え) はそのまま有効です。本項目は
snapshot に依存しないため、**いつ着手しても構いません**。

## 5. snapshot 3 の取得条件 — 起点は apply、snapshot 2' ではない

> 作業依頼では「snapshot 2' 取得から 7 日後 = 2026-10-23 以降」とされていましたが、
> **これは誤りです。**

snapshot 3 が測るのは**削減効果**です。しかし **PR #82 / #83 の削減版 rule は
まだ配布されていません。**

| | 配布中 (`~/.claude/`) | repo (削減後) |
|---|--:|--:|
| CLAUDE.md | 8,291 B | 3,763 B |
| rules 合計 | 31,380 B (6 ファイル) | 13,407 B (5 ファイル) |

`project-skill-recommend.md` も配布先にまだ存在します。

したがって条件は:

```
apply を実行する  →  その 7 日後以降に snapshot 3
```

今日 (10-16) apply すれば **10-23 以降**が有効です。apply が遅れればそのぶん後ろに
ずれます。**apply しないまま 10-23 に取っても snapshot 2' の再測定**になります。

## 6. 測定設計の修正提案 (本解析から新規)

本解析の最大の発見は「指標が全プロジェクト合算なので、`~/.claude/` への変更の効果を
分離できない」ことです。放置すると snapshot 3 も同じ理由で解釈不能になります。

### 提案: プロジェクト別の内訳を出す

`Get-InsightsScope` が読む JSONL には **`cwd` が入っています** (本解析で使用)。
meta 行に `Cwd` を加え、

- レポートにプロジェクト別の内訳表を出す
- `-ProjectFilter <path>` で 1 プロジェクトに絞って集計できる

ようにすれば、「本 kit セッションでの遵守率」を切り出して比較できます。

これは実装を伴うため提案に留めます。ただし **snapshot 3 の前に入れないと、
3 点比較そのものが成立しません**。優先度は item 4-6 より高いと考えます。

## 7. ロードマップ (実装着手判断まで)

| 順 | 作業 | 前提 | 判断材料 |
|---|---|---|---|
| 1 | **測定の project 別内訳** (§6) | なし | 本解析。snapshot 3 の前提 |
| 2 | **`Get-CommitSubject` の偽陽性修正** (§2) | なし | 14 件の偽陽性を実データで特定済 |
| 3 | item 6 (pre-commit 除外) | なし | `.mailmap` 4 件を再確認済 |
| 4 | **apply 実行** (削減版 rule の配布) | 1 / 2 が入っていると望ましい | — |
| 5 | item 5 (費用見出し) | なし | snapshot 2' で弱さが顕在化 |
| 6 | snapshot 3 取得 | 4 の 7 日後 | 削減効果 |
| 7 | item 4 (委譲緩和) | commit-msg 4 件の実コスト測定 | snapshot 3 + コスト実測 |

1 と 2 は**指標そのものの信頼性**に関わるため先行させるべきです。現状の数値は
「下がったら疑う」程度の精度しかなく、この状態で item 4 の緩和を判断すると、
測定の瑕疵を根拠に文面を変えることになります。

3 と 5 は snapshot に依存しないので、1 / 2 と並行して進められます。

## 8. 未解決の問い

1. `cwd` 別の内訳を出したとき、本 kit セッションの plan-first は 11 prompt しかない。
   有意な比較には何週間必要か (ノイズフロア ±2 pt は全体集計での値)
2. `Get-CommitSubject` の 49 件の未抽出 (37%) をどう扱うか。抽出不能を分母から外す
   現仕様は、抽出できた側に偏る可能性がある
3. snapshot 1 の window も当時の workload 構成に依存していた。1 自体を
   「配布前の基準」として使い続けてよいか

## 関連

- ADR-0015 §A (snapshot 表) / §E (指標の定義と限界)
- `docs/step-6-items/item-4-haiku-delegation-relaxation.md`
- `docs/step-6-items/item-5-cost-headline-fix.md`
- `docs/step-6-items/item-6-pre-commit-email-regex-exclusions.md`
- `docs/setup/snapshot-procedure.md` (取得手順と判定基準)
