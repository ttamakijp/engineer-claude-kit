# ADR-0001: engineer-claude-kit clean start 設計

**ステータス**: Proposed
**日付**: 2026-06-05
**Phase**: 1 (foundation)

## コンテキスト

dev-templates (https://github.com/ttamakijp/dev-templates) は v3.5 まで進化し、
22+ ADR と 5 層防御を持つ multi-AI / multi-persona platform に成熟した。一方、
以下の状況に対しては機能過多で初心者導入が難しい:

- 配布先: 職場 (AWS Bedrock 経由の Claude / Azure DevOps repo / Windows 環境)
- ユーザ: Claude 初心者多数、意識せず動くことが要件
- 不要要素: multi-AI 出力 / multi-persona / Dispatch / scheduled-tasks / GitHub 専用 CI / Dependabot

clean start として `engineer-claude-kit` を新設し、dev-templates のノウハウ
(Layer 1 骨格、ADR 蓄積) は **設計知見として継承**するが、コード資産は
**新規実装** する。

### 前提: モデル戦略の根拠 (t-tamaki-todo TTL 検証)

t-tamaki-todo Phase 1 実測 (2026-06-04、Bedrock + 三菱電機 Cloud Proxy SSL
inspection) の核心発見:

- **Sonnet 4.5 は Bedrock 1h prompt cache 対応、Sonnet 4.6 は非対応** (4.6 は
  flag 設定下も `eph_1h=0` で 5m TTL に fallback)
- コスト主因は **cache miss × retry storm (Cloud Proxy SSL inspection)**、
  1 ユーザ **$150 / 3 日** を測定
- `ENABLE_PROMPT_CACHING_1H_BEDROCK=1` (1h cache flag) + `AWS_MAX_ATTEMPTS=2`
  (retry 抑制) + Sonnet 4.5 で **$50/日 → 約 $23 (54% 削減・保守見積)**
- **Haiku 4.5 を main にする定量根拠は未測定 (TBD) のため採用しない**

ゆえに本キットは実測済みの Sonnet 4.5 を main agent に固定し、Haiku 4.5 を
SMALL_FAST_MODEL として補助に置く。

参照: https://github.com/ttamakijp/t-tamaki-todo

## 決定

### A. リポジトリ名: `engineer-claude-kit`

- 「engineer 向けの Claude キット」を業務環境で他人に見せた時の自己説明性が最高
- ADO 上で公開、英数小文字 + hyphen 命名規約

### B. 配布方式: ADO + git clone + bootstrap.ps1 (β 方式)

- `git clone https://dev.azure.com/<org>/<proj>/_git/engineer-claude-kit "$env:USERPROFILE\.claude-kit"` 後に `bootstrap.ps1` を起動
- 認証は Azure CLI の git credential helper 任せ (Windows なら Azure Login 連携で自動化可能)
- 代替案として MSI (γ) があるが、初期 Phase 1 では git clone で十分

### C. プロジェクト自動有効化: ハイブリッド (iii 方式)

- 共通 skill (commit-msg / review / lint helper 等) は `~/.claude/skills/` に **global 配置** (初心者は意識不要)
- プロジェクト固有 skill (android-build / web-test 等) は `apply-claude-kit.ps1` で `<project>/.claude/skills/` に **per-project 配布**
- 新規プロジェクトディレクトリで `claude` 起動時に CWD 検知し、`apply-claude-kit` 未実行なら 1 回だけ提案する (SessionStart hook or `~/.claude/CLAUDE.md` の検知ルール、詳細は ADR-0002 で別途決定)

### D. AI 前提: Claude のみ

- `source/rules/` の build は `.claude/rules/` 出力のみ (Copilot / Cursor / Cline 削除)
- `scripts/build-rules.py` も出力先 1 つで簡素化

### E. Persona: engineer 固定

- multi-persona 機能 (manufacturing 系 sub-persona 15 種など) は **全削除**
- 文体規約は engineer 向け 1 セット (日本語 + 結論優先 + 差分のみ)

### F. Dispatch / scheduled-tasks: 全削除

- 業務環境では Dispatch (Cowork) を使わない前提
- 関連: `scheduled-tasks/` ディレクトリ、cleanup-watch skill、auto-memory-size-check 等を全て削除

### G. モデル戦略 (Bedrock 経由、t-tamaki-todo 実測準拠)

- `ANTHROPIC_MODEL = Sonnet 4.5` (main agent、Bedrock 1h prompt cache 対応を実測済み)
- `ANTHROPIC_SMALL_FAST_MODEL = Haiku 4.5` (Claude Code 内部処理)
- 環境変数: `ENABLE_PROMPT_CACHING_1H_BEDROCK=1`、`AWS_MAX_ATTEMPTS=2`、
  `CLAUDE_CODE_USE_BEDROCK=1`、`AWS_REGION`、`AWS_PROFILE`
- **Sonnet 4.6 / Opus 系: 採用しない** (Sonnet 4.6 は Bedrock 1h cache 非対応で
  TTL 5min 短期化、cache miss コストが嵩む。t-tamaki-todo 実証根拠)

`~/.claude/settings.json` の env 例:

```json
"env": {
  "CLAUDE_CODE_USE_BEDROCK": "1",
  "AWS_REGION": "us-east-1",
  "AWS_PROFILE": "<your-profile>",
  "ANTHROPIC_MODEL": "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
  "ANTHROPIC_SMALL_FAST_MODEL": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
  "ENABLE_PROMPT_CACHING_1H_BEDROCK": "1",
  "AWS_MAX_ATTEMPTS": "2"
}
```

注: Bedrock 有効化フラグの env key は Claude Code 実装上 `CLAUDE_CODE_USE_BEDROCK`
(文章中で `ANTHROPIC_BEDROCK` と呼ぶことがあるが、settings.json に書くキー名は
`CLAUDE_CODE_USE_BEDROCK`)。`ENABLE_PROMPT_CACHING_1H_BEDROCK=1` は client 側
opt-in で、対応モデル (Sonnet 4.5) とセットで初めて 1h bucket が効く。
`AWS_MAX_ATTEMPTS=2` は Cloud Proxy 起因の boto3 retry storm を緩和 (10 → 2 回)。

**注記** (2026-06-05): 上記 model ID は Bedrock 実測値 (t-tamaki-todo Phase 1 検証
`docs/2026-06-04-bedrock-1h-cache-investigation-complete.md` §3.1 / §8.1) に
基づく。Anthropic API 形式 (`claude-sonnet-4-5-XXX`) ではなく Bedrock 形式
(`us.anthropic.claude-sonnet-4-5-XXX-v1:0`) を採用。Haiku 4.5 の `-v1:0` suffix も
同検証で確認済み。将来モデル更新時は本 ADR ではなく `config/models.yaml`
(ADR-0003 で確定予定) を SSoT として更新する設計とし、本 §G の値はその初期値の
根拠記録として残す。

### G-2. CLAUDE.md による Haiku / Sonnet 4.5 自動使い分け

main = Sonnet 4.5、small fast = Haiku 4.5 の 2 段構成だけでは「全作業が main で
動いてしまう」リスクがある。Claude 自身に作業の複雑度を判定させ、軽作業は
Haiku に明示的に委譲する指示を `~/.claude/CLAUDE.md` (engineer-claude-kit の
配布テンプレ) に組み込む。

具体的指示 (CLAUDE.md 内):

- **Haiku 4.5 を使う作業**:
  - コミットメッセージ生成
  - ログ要約 / エラー要約
  - 既存ファイルの軽微な編集 (typo 修正、フォーマット調整)
  - 雛形コード生成 (boilerplate)
  - 単純な質問への回答 (factual / lookup)

- **Sonnet 4.5 (main) を使う作業**:
  - 設計判断 / ADR 起票
  - 複雑なリファクタリング
  - バグ調査 / 根本原因分析
  - コードレビュー
  - 複数ファイル横断の修正

- **判定基準** (Claude 自身が判断):
  - 「読み取り中心、出力が短い、論理分岐が少ない」→ Haiku
  - 「複数ファイル横断 / 因果推論 / 設計判断」→ Sonnet 4.5
  - 不明な場合は Sonnet 4.5 を優先 (品質 > コスト)

実装: sub-agent 定義 (`~/.claude/agents/<task>.md`) で軽作業エージェントを
Haiku 4.5 に固定。CLAUDE.md は「軽作業は Haiku エージェントに委譲せよ」と
記載することで、main (Sonnet 4.5) が自動的にタスク振り分けを行う。

具体的な sub-agent / 委譲指示の詳細は ADR-0002 (Phase 2 実装、bootstrap 設計)
で確定する。

### 注記: 抽象化方針 (将来移行)

本 ADR §G では Bedrock model ID をリテラル (`us.anthropic.claude-sonnet-4-5-20250929-v1:0` 等) で記載しているが、これは Phase 1 時点での実測値の明示であり、**長期運用での SSoT (single source of truth) ではない**。

将来 (ADR-0003 で確定予定) は以下の間接参照を導入し、本 ADR の値はあくまで「Phase 1 時点のスナップショット」として扱う:

| 抽象化対象 | SSoT (将来) | 経由 |
|---|---|---|
| Bedrock model ID (Sonnet 4.5 / Haiku 4.5) | `config/models.yaml` | `apply-claude-kit.ps1` が generate する `~/.claude/settings.json` |
| 配布元リポジトリ URL (ADO `_git` 形式) | 環境変数 `ENGINEER_CLAUDE_KIT_GIT_URL` または `config/distribution.yaml` | `bootstrap.ps1` の clone URL |
| その他環境固有値 (AWS region / profile 等) | 環境変数 | 同上 |

**理由**:
- model ID: AWS Bedrock 側で新 model release ごとに ID 接尾辞 (`YYYYMMDD-v1:0`) が変わる
- 配布元 URL: 組織移行・リポ rename・OSS mirror 等で URL は変化しうる。本 ADR (§B の `https://dev.azure.com/<org>/<proj>/_git/...`) にハードコードすると追従不可能になる
- 環境変数経由なら ADR / コード両方を変更せずに override 可能

dev-templates ADR-0040 の `DEV_TEMPLATES_GIT_URL` 環境変数 override と同じパターンを、本キットでは `ENGINEER_CLAUDE_KIT_GIT_URL` として導入する。

**出典 (Phase 1 実測値の根拠)**: t-tamaki-todo `docs/2026-06-04-bedrock-1h-cache-investigation-complete.md` §3.1 / §8.1 (Sonnet 4.5 / Haiku 4.5 の Bedrock model ID 実測)

**派生 ADR**: 本注記の具体化は ADR-0003 (bootstrap design + モデル抽象化) で行う。

### H. host: ADO 固定 (GitHub 専用機能削除)

- Dependabot 削除 (ADO 非対応)
- GitHub Actions workflow 削除、代わりに `azure-pipelines.yml` を採用 (Phase 2 で実装)
- `.git-host-allowlist` は ADO のみ allow

### I. OS: Windows 主軸 (PowerShell only、Phase 1)

- `.ps1` スクリプトのみ作成、`.sh` は Phase 3 以降の cross-platform 拡張時
- `bootstrap.ps1` / `apply-claude-kit.ps1` / `build-rules.ps1` の 3 つが core
- **PowerShell スクリプトは ASCII only で書く**。理由: git に commit すると
  UTF-8 BOM が剥落し、日本語混入時に PowerShell 実行が文字化けで壊れるため。
  Write-Host / コメント / 変数名・関数名・エラーメッセージ・ログ出力すべて
  英語のみ。日本語は markdown ドキュメント (`.md`) に限定する

## 検討した代替案

### 代替案 1: dev-templates v4 として既存リポを fork / 派生

- メリット: ADR 蓄積を直接継承、CI 流用
- デメリット: 機能過多が初心者に重い、git 履歴に不要 ADR が永久残存

### 代替案 2: dev-templates 内に `--profile minimal` を追加

- メリット: 単一リポでメンテ
- デメリット: profile 増加で内部複雑度悪化、配布も既存複雑な flow に乗る

### 代替案 3: Haiku 4.5 を main agent にする

- メリット: base 単価が安く、軽作業中心なら初期コスト最低
- デメリット: Haiku 4.5 の Bedrock 1h cache 対応は t-tamaki-todo Phase 1 で
  **未測定**、応答品質 (設計判断 / 因果推論) への影響も不明
- → 実証根拠がないため不採用。Sonnet 4.5 main + Haiku 委譲 (§G-2) で軽作業
  コストを抑える方が確実

→ clean start (本 ADR の決定) の方が学習コスト低 / メンテ単純 / 用途明確

## 未解決の問い

1. ADO 配布の認証フロー詳細 (Azure CLI git credential helper + PAT fallback の優先順)
2. SessionStart hook で CWD 検知する方式の Claude Code 公式サポート状況 (hook API 仕様確認必要)
3. `~/.claude/CLAUDE.md` の検知ルールが main (Sonnet 4.5) で確実に発火するか (指示遵守率)
4. Bedrock 経由での Sonnet 4.5 / Haiku 4.5 model id 解決 (Bedrock-specific model name mapping)
5. **Haiku 4.5 の Bedrock 1h cache サポート状況は未測定**。将来 main 候補にする場合は engineer-claude-kit Phase 3 以降で別途検証必要 (SMALL_FAST_MODEL 自動切替時にも 1 分 probe で要確認)
6. **CLAUDE.md の「軽作業は Haiku に委譲」指示を main (Sonnet 4.5) から確実に発火させられるか** 実機検証必要 (§G-2、Haiku への振り分け遵守率)
7. dev-templates から **どの ADR を移植**, **どの ADR を破棄** するかの精査リスト (別途 ADR-0002 で決定)
8. `cloud-build-wrapper` を継承するか (OneDrive 業務利用が職場で多いか要確認)
9. Cloud Proxy hang の完全根治 (VPC Endpoint for Bedrock の IT 申請要否)

## 結果

### 利点

- 初心者にとって意識不要 (1 コマンドで `~/.claude` + プロジェクトが動く状態)
- 機能過多を排除し context window / 学習コスト両方を圧縮
- ADO + Bedrock + Windows という業務環境前提を最初から固定設計、host 判定の複雑度なし
- モデル戦略 (Sonnet 4.5 main + 1h cache flag + retry 抑制) で TTL 失効 × retry storm の二重コストを回避、$50/日 → 約 $23 の削減を実測根拠で見込める
- CLAUDE.md による Haiku 委譲 (§G-2) で軽作業を安価モデルに振り分け、品質を保ちつつコストを追加圧縮
- dev-templates の Layer 1 骨格 (5 層防御の思想、ADR 文化) は設計知見として継承

### 欠点

- dev-templates と engineer-claude-kit の 2 リポ並行メンテ (cross-pollination が必要)
- ADR 蓄積を新リポでゼロから書き直すコスト (重要 ADR の移植判断が次の課題)
- 1h cache write は 5m write の 1.6 倍高単価のため、5m 跨ぎが少ない短時間 workload では単発コストが増える可能性 (workload に 5m 跨ぎが多いほど累積メリットが上回る)
- ADO 専用 host のため社外 OSS 化が困難 (GitHub fork も別途必要)
- Cloud Proxy hang は本構成で緩和されるが完全除去ではない (根治は VPC Endpoint 待ち)
- §G-2 の Haiku 委譲は main の指示遵守率に依存し、振り分けが効かないと全作業が Sonnet 4.5 で走る (未解決の問い #6)

## 参照

- [dev-templates v3.5 (継承元)](https://github.com/ttamakijp/dev-templates)
- [t-tamaki-todo (TTL 検証)](https://github.com/ttamakijp/t-tamaki-todo) — `docs/2026-06-04-bedrock-1h-cache-investigation-complete.md` / `docs/2026-06-04-workplace-phase1-results.md`
- dev-templates ADR-0025 (multi-persona、本 ADR で破棄)
- dev-templates ADR-0040 (PR-κ1 bootstrap-apply、本 ADR の β 方式の参考実装)
- dev-templates ADR-0044 (Bedrock 環境検出 + model ID 自動解決、本 ADR §G の前提技術)
