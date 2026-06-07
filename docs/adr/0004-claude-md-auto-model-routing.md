# ADR-0004: CLAUDE.md による Haiku / Sonnet 4.5 自動使い分け

**ステータス**: Proposed
**日付**: 2026-06-05
**Phase**: 2 (runtime routing 設計)
**関連**: ADR-0001 (モデル戦略) / ADR-0003 (config/models.yaml SSoT)

## コンテキスト

ADR-0001 §G で main=Sonnet 4.5 / small fast=Haiku 4.5 を確定し、ADR-0003 §A/§B で `config/models.yaml` の役割→ID マッピング + `apply-claude-kit.ps1` による generate 経路を確定した。残課題は **「main の Sonnet 4.5 が、軽作業を自動的に Haiku 4.5 に委譲する」runtime ルーティングロジック** の確定である。

ADR-0001 §G-2 の予告および「CLAUDE.md による Haiku/Sonnet 4.5 自動使い分け」要望を本 ADR で具体化する。

## 決定

### A. ルーティング階層 (2 層構造)

```
[User Prompt]
   |
   v
[Main Agent: Sonnet 4.5]  ← context 全部見える、判定する
   |
   +-- 軽作業 → [Sub-Agent: Haiku 4.5]
   |              (commit-msg / lint-helper / log-summary 等)
   |
   +-- 重作業 → Sonnet 4.5 自身が処理
                (review / architect / debug / refactor)
```

main は全 context を持つが、sub-agent は task 単位の最小 context で動く。Haiku sub-agent は呼び出しごとに「使い捨て」で context を持たない。

### B. Sub-Agent 定義 5 種

`~/.claude/agents/` 配下に以下 5 ファイルを配置 (Phase 2 で実装):

| ファイル | モデル | 用途 | 想定 input |
|---|---|---|---|
| `commit-msg.md` | Haiku 4.5 | コミットメッセージ生成 | git diff + 修正の意図 1 行 |
| `lint-helper.md` | Haiku 4.5 | typo / フォーマット / 軽微 refactor | 対象ファイルパス + 指摘範囲 |
| `log-summary.md` | Haiku 4.5 | ビルド/テストログの要約 + エラー抽出 | log 全文 |
| `review.md` | Sonnet 4.5 | コードレビュー (設計判断含む) | PR diff + 関連設計文書 |
| `architect.md` | Sonnet 4.5 | 設計判断・ADR draft 起票 | 課題 + 制約 + 既存設計 |
| `debug-analyze.md` | Sonnet 4.5 | 因果推論・根本原因分析 | エラー + 再現手順 + コンテキスト |

各 sub-agent 定義ファイルの frontmatter 例 (Haiku 委譲):

```yaml
---
name: commit-msg
description: |
  Conventional Commits 形式でコミットメッセージを生成する。
  Haiku 4.5 で軽量に処理し、Sonnet main の context を消費しない。
model: haiku
tools: [Read, Bash]
---

# 役割
- git diff と修正意図から Conventional Commits 形式の commit message を生成
- type: feat/fix/docs/refactor/test/chore のいずれかを判定
- scope は影響範囲を kebab-case で 1 単語、なければ省略
- subject は 50 文字以内、命令形
- body は why を中心に 1-3 行

# 制約
- 既存の commit-convention rule (.claude/rules/commit-convention.md) を必ず参照
- 不明な場合は ask せず、main へ「不明」と返す
```

注: `model: haiku` の値は `config/models.yaml` の `role-of: small-fast` でリゾルブされる想定 (ADR-0003 §B と整合)。

### C. ルーティング判定ロジック (CLAUDE.md)

`~/.claude/CLAUDE.md` の冒頭に以下を組み込む:

```markdown
## モデル使い分けルール (自動判定)

あなた (main agent) は Sonnet 4.5 で動作する。各ユーザ要求に対し、以下の判定で
Haiku sub-agent への委譲を検討する。

### Haiku 委譲する作業 (軽作業)
- コミットメッセージ生成 (Conventional Commits) → `commit-msg` sub-agent
- 既存ファイルの軽微な編集 (typo 修正、フォーマット調整、import 整理) → `lint-helper`
- ログ/エラー要約 (build log, test output, ANR trace 等の要約) → `log-summary`
- 単純な事実質問 (factual / lookup、定数値の確認、ファイル存在チェック)

### Sonnet 4.5 で自分が処理する作業 (重作業)
- 設計判断 / ADR 起票 → `architect` sub-agent または自分で
- バグ調査 / 根本原因分析 → `debug-analyze` sub-agent または自分で
- コードレビュー → `review` sub-agent
- 複数ファイル横断の修正
- 因果推論を伴う議論

### 判定基準 (グレーゾーン)
- 「読み取り中心、出力が短い、論理分岐が少ない」→ Haiku 委譲
- 「複数ファイル横断 / 因果推論 / 設計判断」→ Sonnet 4.5
- 不明な場合は **Sonnet 4.5 を優先** (品質 > コスト)

### 委譲時の責任分界
- Haiku が「不明」と返した場合、Sonnet 4.5 自身が再処理
- Haiku の出力品質が疑わしい場合 (出力短すぎ・指示無視) も Sonnet 4.5 が引き取り
- 重要判断 (commit / push / branch 操作) は必ず Sonnet 4.5 自身が実行
```

### D. `config/models.yaml` との連携

ADR-0003 §B で確定した role mapping を sub-agent 定義から参照する仕組み:

- `apply-claude-kit.ps1 -Global` 実行時に `config/models.yaml` を読み込み
- 各 sub-agent 定義 (`~/.claude/agents/*.md`) の frontmatter `model:` を `config/models.yaml` の role 別 ID にリゾルブして書き込む
- model 更新時は `config/models.yaml` だけ編集 → 再 apply で sub-agent 定義も同期される

### E. 観測指標 (Phase 3 で測定)

本ルーティングの効果を以下で測定 (engineer-claude-kit Phase 3 cost observation で):

- Haiku 委譲回数 / 全 turn 数 (= 委譲率)
- Haiku 委譲 turn の token cost / Sonnet 4.5 turn の token cost
- 委譲した turn での品質低下発生率 (Sonnet 引き取り回数)

期待値: 全 turn の 30-50% が Haiku 委譲、cost 削減効果は cost-optimization (sub-agent 委譲) の知見を参考に input 単価で 1/4 程度。実測値は Phase 3 で確定。

## 検討した代替案

### 代替案 1: main を Haiku、重作業のみ Sonnet 4.5 sub-agent 呼出
- メリット: 基本 cost が低い
- デメリット: 実測検証で Haiku の指示遵守率・判定精度が未測定。main の判定ミスはシステム全体の品質を下げる。ADR-0001 §G の結論 (Sonnet 4.5 main) を破ることになる

### 代替案 2: モデル切り替えを CLAUDE.md ではなく settings.json で固定 (静的設定)
- メリット: 判定不要、シンプル
- デメリット: 作業ごとの動的ルーティングが効かない。ユーザが手動でモデル切替する手間が必要。要件「初心者は意識せず動く」と矛盾

### 代替案 3: sub-agent を作らず、main 内で個別 Bash 呼出で軽作業
- メリット: 構造単純
- デメリット: main の context を消費し続け、長セッションで圧迫。委譲先の「使い捨て context」の利点を捨てる

## 未解決の問い

1. **Haiku の指示遵守率**: CLAUDE.md ルールを main (Sonnet 4.5) が確実に発火させるか、Phase 3 で実機検証必要
2. **委譲オーバーヘッド**: sub-agent 呼出 1 回の context 構築 cost と Haiku 単価のトレードオフ点を測定要
3. **判定基準のグレーゾーン**: 「軽 vs 重」の自動判定で誤判定したケースのリカバリ方法 (Sonnet 引き取り) の発火条件
4. **agents 配布ロジックの実装範囲**: agents 定義の generate ロジックを既存の apply 設計から流用するか、新規に書くか (ADR-0002 では apply-deploys-agents-and-settings を変形採用カテゴリ B にしている)
5. **Haiku 1h cache の確認**: ADR-0001 §G の未解決 #5 と同じ。Haiku 4.5 の 1h cache サポート確認次第、Haiku を main 化する選択肢も復活する

## 結果

### 利点

- main 1 + sub 5 の 2 層構造で **作業ごと最適なモデル** が選ばれる
- 軽作業を Haiku 委譲することで token cost を input 単価で 1/4 程度に圧縮 (期待値、実測は Phase 3)
- sub-agent が使い捨て context のため main の context window 圧迫を回避、長セッションに耐える
- CLAUDE.md の判定ルールが「設計知見」として ADR にも記録され、ユーザ・AI 両方が同じ前提で動ける
- `config/models.yaml` を介して間接参照のため、model 更新時の追従が ADR 編集不要

### 欠点

- sub-agent 呼出オーバーヘッド (context 構築 cost) があるため、極軽作業では委譲しない方が安い可能性
- 判定の誤りで Haiku が雑な結果を返すと、Sonnet 4.5 が引き取り直しで二重コストになる
- sub-agent 5 種の **品質確認** が Phase 3 で必要 (初期は経験則ベース)
- Haiku の指示遵守率が低い場合、CLAUDE.md ルールが無力化される (ADR-0001 §G の未解決 #5 と同じリスク)

## 参照

- ADR-0001 (clean start design) §G モデル戦略 / §G-2 抽象化方針注記
- ADR-0002 (ADR セット取捨選択方針) §B apply-deploys-agents-and-settings 変形採用
- ADR-0003 (bootstrap + 抽象化) §A bootstrap フロー / §B `config/models.yaml` SSoT
- cost-optimization (sub-agent 委譲パターン) を本 ADR の Haiku 委譲設計の先例として参照
- apply-deploys-agents-and-settings は apply-claude-kit.ps1 の agents 配布として実装 (§B)
- Haiku 4.5 1h cache 未測定の根拠は実環境での Bedrock 1h cache 実測検証 §3.1 / §8.1
