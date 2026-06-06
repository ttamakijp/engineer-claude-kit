# engineer-claude-kit

職場 (AWS Bedrock + Azure DevOps + Windows) で Claude Code を使い始めるエンジニア向け、ワンコマンド bootstrap キット。dev-templates v3.5 のノウハウを継承しつつ、initial setup の認知負荷を最小化することを設計目標とする。

> 設計詳細は [docs/adr/](docs/adr/) を参照。本 README は配置 (deployment) と利用方法 (usage) に絞る。

## 1. 完成形の配置構成

bootstrap 実行後、以下の 2 層構造で配置される。

### 1.1 グローバル (`~/.claude/`)

全プロジェクトで共通する Claude Code 設定。bootstrap.ps1 が配置する。

```
~/.claude/
|-- CLAUDE.md                 # 全プロジェクト共通指示 (Haiku/Sonnet 4.5 自動使い分け含む)
|-- settings.json             # Bedrock 接続 + model 設定 (config/models.yaml から generate)
|-- agents/                   # sub-agent 定義 (ADR-0004)
|   |-- commit-msg.md         # Haiku 委譲: コミットメッセージ生成
|   |-- lint-helper.md        # Haiku 委譲: typo / フォーマット / 軽微 refactor
|   |-- log-summary.md        # Haiku 委譲: build / test ログ要約
|   |-- review.md             # Sonnet 4.5: コードレビュー (設計判断含む)
|   |-- architect.md          # Sonnet 4.5: 設計判断・ADR 起票
|   `-- debug-analyze.md      # Sonnet 4.5: 因果推論・根本原因分析
|-- skills/                   # 共通 skill (全プロジェクトで利用可能)
|   |-- apply-claude-kit/     # プロジェクトへ kit を配布する skill
|   |-- leak-check/           # PII / credentials 検出 (5 層防御 / ADR は Phase 4 起票予定)
|   |-- commit-helper/        # Conventional Commits 補助
|   `-- propose-adr/          # ADR draft 起票 (architect sub-agent 連携)
|-- commands/                 # slash commands
|   |-- apply.md              # /apply <project-path>
|   |-- checkpoint.md         # /checkpoint セッション state 保存
|   `-- resume.md             # /resume state からの再開
`-- state/                    # checkpoint state (.gitignore)
```

### 1.2 プロジェクト (`<project>/`)

apply-claude-kit によって個別プロジェクトに配置されるファイル群。

```
<project>/
|-- CLAUDE.md                 # プロジェクト固有指示 (技術スタック / ビルドコマンド)
|-- .claude/
|   |-- rules/                # source/rules/ から build した Claude rules (ADR-0003)
|   |   `-- <rule-id>.md
|   |-- skills/               # プロジェクト固有 skill (android-build / web-test 等)
|   |-- agents/               # プロジェクト固有 sub-agent
|   `-- state/                # プロジェクト固有 state (.gitignore)
|-- .git/hooks/
|   |-- pre-commit            # leak 検出 hook
|   `-- pre-push              # host allowlist + backup ref 拒否
|-- .gitignore                # .claude/state/ / *.keystore / local.properties / .env*
|-- .gitleaks.toml            # gitleaks 設定
|-- .mailmap                  # identity normalization
|-- .engineer-claude-kit-applied  # 適用 marker JSON (apply 履歴 / version)
`-- azure-pipelines.yml       # ADO CI (quality gates / leak scan)
```

### 1.3 SSoT (kit 内部、配布元)

engineer-claude-kit リポ内の single source of truth (ADR-0003):

```
engineer-claude-kit/
|-- config/
|   |-- models.yaml           # Bedrock model ID + role mapping
|   |-- distribution.yaml     # 配布元リポジトリ URL (env override 可能)
|   |-- env-defaults.yaml     # AWS region / profile / cache flag 既定値
|   `-- cost-budget.yaml      # Bedrock コスト予算しきい値 (Phase 3.2)
|-- source/
|   `-- rules/                # Claude rules の single source (multi-AI 出力なし、Claude 専用)
|-- templates/                # ~/.claude へ配布する素材 (apply-claude-kit が参照)
|   |-- CLAUDE.md             # 共通 CLAUDE.md 素材
|   |-- agents/               # commit-msg / lint-helper / log-summary / review / architect / debug-analyze
|   `-- skills/               # commit-helper / leak-check / propose-adr (Phase 3.1)
|-- scripts/
|   |-- bootstrap.ps1         # ADO clone + ~/.claude 配布 (entry point)
|   |-- apply-claude-kit.ps1  # ~/.claude or <project>/.claude へ配布する内部 script
|   |-- build-rules.ps1       # source/rules/ -> .claude/rules/ build
|   `-- cost-observe-bedrock.ps1  # AWS Cost Explorer から Bedrock コスト report 生成 (Phase 3.2)
|-- tests/                    # Pester テスト (PowerShell 5.1 / Pester 3.4 互換)
|-- docs/
|   |-- adr/                  # Architecture Decision Records
|   `-- manual-verification/  # 手動検証手順
|       |-- bootstrap-installation.md  # bootstrap chain 動作検証 (Windows / MAX)
|       `-- scenario-comparison.md     # kit 効果測定 (5 軸比較)
`-- README.md                 # 本ファイル
```

## 2. ファイル機能表 (Phase status 付き)

凡例: ✅ 実装済 / ⏳ 計画 (未着手)。Phase 1 (foundation) + Phase 3.1 (共通 skills) + Phase 3.2 (Bedrock cost 観測) が実装済 (Pester テスト群は PS 5.1 / Pester 3.4 互換、手動検証ドキュメントも整備済)、Phase 2 系 (bootstrap / apply / model 配布) と Phase 4 系 (ADO CI 等) は計画段階。

### 2.1 グローバル側 `~/.claude/`

| 配置 | 機能 | Phase |
|---|---|---|
| `CLAUDE.md` | 全プロジェクト共通の指示、Haiku/Sonnet 4.5 自動使い分けルール (ADR-0004) | ⏳ Phase 2 |
| `settings.json` | Bedrock 接続 + model 設定 (`config/models.yaml` から generate) | ⏳ Phase 2 |
| `agents/commit-msg.md` | コミットメッセージ生成 (Haiku 委譲) | ⏳ Phase 2 |
| `agents/lint-helper.md` | 軽微修正 (Haiku 委譲) | ⏳ Phase 2 |
| `agents/log-summary.md` | ビルド/テストログ要約 (Haiku 委譲) | ⏳ Phase 2 |
| `agents/review.md` | コードレビュー (Sonnet 4.5) | ⏳ Phase 2 |
| `agents/architect.md` | 設計判断・ADR 起票 (Sonnet 4.5) | ⏳ Phase 2 |
| `agents/debug-analyze.md` | 因果推論・根本原因分析 (Sonnet 4.5) | ⏳ Phase 2 |
| `skills/apply-claude-kit/` | プロジェクトへ kit を配布する skill | ⏳ Phase 2 |
| `skills/commit-helper/` | Conventional Commits 補助 (Haiku 委譲) | ✅ Phase 3.1 |
| `skills/leak-check/` | PII / credentials / 機密ファイル 検出 | ✅ Phase 3.1 |
| `skills/propose-adr/` | ADR draft 起票 (architect sub-agent 連携) | ✅ Phase 3.1 |
| `commands/apply.md` | `/apply` slash command | ⏳ Phase 2 |
| `commands/checkpoint.md` | `/checkpoint` セッション state 保存 | ⏳ Phase 3 |
| `commands/resume.md` | `/resume` state からの再開 | ⏳ Phase 3 |
| `state/` | checkpoint state (.gitignore) | ⏳ Phase 3 |

### 2.2 プロジェクト側 `<project>/`

| 配置 | 機能 | Phase |
|---|---|---|
| `CLAUDE.md` | プロジェクト固有指示 (技術スタック / ビルドコマンド) | ⏳ Phase 2 |
| `.claude/rules/<rule-id>.md` | `source/rules/` から build された Claude rules | ⏳ Phase 2 |
| `.claude/skills/` | プロジェクト固有 skill (android-build / web-test 等) | ⏳ Phase 3 |
| `.claude/agents/` | プロジェクト固有 sub-agent | ⏳ Phase 3 |
| `.claude/state/` | プロジェクト固有 state (.gitignore) | ⏳ Phase 3 |
| `.git/hooks/pre-commit` | leak 検出 hook | ⏳ Phase 3 |
| `.git/hooks/pre-push` | host allowlist + backup ref 拒否 hook | ⏳ Phase 3 |
| `.gitignore` | `.claude/state/` / `*.keystore` / `local.properties` / `.env*` | ⏳ Phase 3 |
| `.gitleaks.toml` | gitleaks 設定 | ⏳ Phase 3 |
| `.mailmap` | identity normalization | ⏳ Phase 3 |
| `.engineer-claude-kit-applied` | 適用 marker JSON | ⏳ Phase 2 |
| `azure-pipelines.yml` | ADO CI (quality gates / leak scan) | ⏳ Phase 4 |

### 2.3 SSoT (kit 内部)

| 配置 | 機能 | Phase |
|---|---|---|
| `config/models.yaml` | Bedrock model ID + role mapping (Sonnet 4.5 / Haiku 4.5) | ⏳ Phase 2 |
| `config/distribution.yaml` | 配布元 URL (env `ENGINEER_CLAUDE_KIT_GIT_URL` override 可能) | ⏳ Phase 2 |
| `config/env-defaults.yaml` | AWS region / profile / cache flag 既定値 | ⏳ Phase 2 |
| `source/rules/` | Claude rules の single source (multi-AI 出力なし) | ⏳ Phase 2 |
| `scripts/bootstrap.ps1` | ADO clone + `~/.claude` 配布 (entry point) | ⏳ Phase 2 |
| `scripts/apply-claude-kit.ps1` | 配布実装 | ⏳ Phase 2 |
| `scripts/build-rules.ps1` | `source/rules/` -> `.claude/rules/` build | ⏳ Phase 2 |
| `scripts/cost-observe-bedrock.ps1` | AWS Cost Explorer から Bedrock コストを取得し markdown report 生成 | ✅ Phase 3.2 |
| `config/cost-budget.yaml` | Bedrock コスト予算しきい値 | ✅ Phase 3.2 |
| `reports/bedrock-cost-<date>.md` | weekly cost report (auto-generated, gitignored) | ✅ Phase 3.2 |
| `templates/` | `~/.claude` 配布素材 (CLAUDE.md / agents / skills) | ✅ Phase 3.1 (skills) / ⏳ Phase 2 (agents) |
| `tests/*.tests.ps1` | Pester 単体テスト (bootstrap / apply / build-rules / cost-observe、PS 5.1 + Pester 3.4 互換) | ✅ |
| `docs/manual-verification/` | kit 効果測定の手動検証手順 (scenario-comparison: 5 軸比較) | ✅ |
| `docs/manual-verification/bootstrap-installation.md` | bootstrap chain 動作検証手順 (Windows / Claude MAX 環境対応) | ✅ |
| `docs/adr/` | Architecture Decision Records (現状 0001-0004) | ✅ Phase 1 |
| `README.md` (本ファイル) | プロジェクト概要 + 配置構成 + Quick start | ✅ Phase 1 |
| `LICENSE` / `.gitignore` | リポ初期セット | ✅ Phase 1 |

## 3. Quick Start (Phase 2 完成後の想定)

### 3.1 ADO repo から bootstrap (推奨、業務環境)

```powershell
# 1 行で clone + bootstrap (Phase 2.2 で実装予定)
# 配布元 URL は git clone 時点で .git/config に保存されるため、別途環境変数の手動設定は不要
git clone https://dev.azure.com/<your-org>/<your-proj>/_git/engineer-claude-kit `
  "$env:USERPROFILE\.claude-kit"
& "$env:USERPROFILE\.claude-kit\scripts\bootstrap.ps1"
```

`bootstrap.ps1` は以下を順に実行する:

1. clone した repo の `git remote get-url origin` から配布元 URL を取得 → ユーザ環境変数 `ENGINEER_CLAUDE_KIT_GIT_URL` に永続保存 (以降の自動更新の起点)
2. `~/.claude/CLAUDE.md` / `settings.json` / `agents/` / `skills/` / `commands/` を配置
3. (任意) 現在の cwd が git repo なら、その project にも `.claude/` を配置するか提案 (yes なら `apply-claude-kit.ps1 -Project (Get-Location)` を内部呼出)

### 3.2 新規プロジェクトでの利用

bootstrap 完了後、任意のプロジェクトディレクトリで `claude` 起動時に skill / agent が自動で利用可能。

プロジェクト個別の `.claude/` 配置を行うには:

```powershell
cd <your-project>
& "$env:USERPROFILE\.claude-kit\scripts\apply-claude-kit.ps1" -Project (Get-Location)
```

## 4. 設計判断 (ADR Index)

| ADR | テーマ | ステータス |
|---|---|---|
| [ADR-0001](docs/adr/0001-clean-start-design.md) | clean start 設計 (モデル戦略 / persona / host / OS) | Proposed |
| [ADR-0002](docs/adr/0002-adr-portage-from-dev-templates.md) | dev-templates ADR 移植精査 (A/B/C/D 分類) | Proposed |
| [ADR-0003](docs/adr/0003-bootstrap-and-abstraction.md) | bootstrap design + `config/*.yaml` SSoT | Proposed |
| [ADR-0004](docs/adr/0004-claude-md-auto-model-routing.md) | CLAUDE.md による Haiku/Sonnet 4.5 自動使い分け | Proposed |

## 5. モデル戦略 (要約)

- main agent: **Sonnet 4.5** (`us.anthropic.claude-sonnet-4-5-20250929-v1:0`)
- small fast model: **Haiku 4.5** (`us.anthropic.claude-haiku-4-5-20251001-v1:0`)
- Bedrock 経由: `ENABLE_PROMPT_CACHING_1H_BEDROCK=1` + `AWS_MAX_ATTEMPTS=2`
- 軽作業 (commit-msg / lint / log-summary) は Haiku sub-agent に自動委譲
- model ID は `config/models.yaml` SSoT、`apply-claude-kit.ps1` が `~/.claude/settings.json` を generate
- コスト観測: `scripts/cost-observe-bedrock.ps1` が AWS Cost Explorer から weekly report を生成、`config/cost-budget.yaml` のしきい値で予算監視 (Phase 3.2)

根拠: [t-tamaki-todo Phase 1 検証](https://github.com/ttamakijp/t-tamaki-todo) (cost 54% 削減実証)

## 6. 制約・前提

- **OS**: Windows 10/11 (PowerShell 5.1 以上)
- **Claude Code**: Bedrock 経由で動作 (AWS 認証情報設定済み前提)
- **配布**: Azure DevOps repo の `_git` 形式 URL (canonical)
- **AI**: Claude のみ (Copilot/Cursor/Cline 出力は非対応、ADR-0001 §D)
- **Persona**: engineer 固定 (multi-persona なし、ADR-0001 §E)
- **PowerShell スクリプト**: ASCII only (UTF-8 BOM 剥落による文字化け回避、ADR-0003 §C)

## 7. ライセンス

[MIT](LICENSE)

## 8. 関連リポジトリ

- [ttamakijp/dev-templates](https://github.com/ttamakijp/dev-templates): 継承元 (multi-AI / multi-persona platform)
- [ttamakijp/t-tamaki-todo](https://github.com/ttamakijp/t-tamaki-todo): Bedrock TTL / cost 検証 (本キットのモデル戦略の実証根拠)
