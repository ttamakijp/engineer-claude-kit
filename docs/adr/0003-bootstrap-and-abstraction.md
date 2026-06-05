# ADR-0003: Bootstrap design + 設定値の抽象化 SSoT 化

**ステータス**: Proposed
**日付**: 2026-06-05
**Phase**: 1 → 2 (foundation → bootstrap implementation 設計)
**関連**: ADR-0001 (clean start design) / ADR-0002 (ADR portage triage)

## コンテキスト

ADR-0001 §G-2 で「将来 (ADR-0003 で確定予定) は間接参照を導入し、本 ADR の値は Phase 1 時点のスナップショットとして扱う」と予告した。本 ADR で以下 3 点を確定する:

1. **bootstrap フロー**: ADO の `_git` repo を git clone し `~/.claude/` および `<project>/` を配置する `bootstrap.ps1` の設計
2. **設定値の SSoT 化**: model ID / 配布元 URL / 環境固有値の間接参照を `config/*.yaml` + 環境変数 override で実現
3. **PowerShell スクリプトの ASCII only 規約**: git commit 後の BOM 剥離による文字化け事故を構造的に排除

加えて、ADR-0001 §H で「ADO 固定」を決定した制約と、ADO の clone URL 形式 (`https://dev.azure.com/<org>/<proj>/_git/<repo>`) を実装の前提として明示する。

## 決定

### A. bootstrap フロー (`bootstrap.ps1`)

```
[user] PowerShell 起動
   |
   v
[bootstrap.ps1] (clone 元 URL を環境変数 or 引数から解決)
   |
   v
[git clone ADO _git -> $env:USERPROFILE\.claude-kit\ ]
   |
   v
[apply-claude-kit.ps1 -- global] (= ~/.claude 配布)
   |
   v
[(任意) apply-claude-kit.ps1 -Project <path>] (= <project>/.claude 配布)
```

詳細フェーズ:
1. clone 元 URL を解決: 環境変数 `ENGINEER_CLAUDE_KIT_GIT_URL` > 引数 `-GitUrl` > 既定値 `https://dev.azure.com/<DEFAULT_ORG>/<DEFAULT_PROJ>/_git/engineer-claude-kit`
2. `$env:USERPROFILE\.claude-kit\` に shallow clone (`--depth=1`)
3. apply-claude-kit.ps1 -Global を起動 → `~/.claude/CLAUDE.md` / `settings.json` / `agents/` / `skills/` / `commands/` を配置
4. ユーザに「現在いる project dir に apply するか?」を尋ねる選択肢を出し、Yes なら apply-claude-kit.ps1 -Project $(pwd) を実行 (任意)

### B. 設定値の SSoT (`config/*.yaml`)

3 つの SSoT ファイルを `engineer-claude-kit` リポ内に持つ:

```
config/
├── models.yaml        # Bedrock model ID + role mapping
├── distribution.yaml  # 配布元リポジトリ URL (環境変数 override 可能)
└── env-defaults.yaml  # AWS region / profile / cache flag 既定値
```

`config/models.yaml` の例:

```yaml
# Bedrock model registry (Phase 1 実測値、t-tamaki-todo §3.1/§8.1 出典)
models:
  main:
    id: us.anthropic.claude-sonnet-4-5-20250929-v1:0
    family: sonnet-4-5
    cache_1h_supported: true
  small-fast:
    id: us.anthropic.claude-haiku-4-5-20251001-v1:0
    family: haiku-4-5
    cache_1h_supported: false  # TBD: Phase 3 で測定予定
  architect:
    role-of: main
  review:
    role-of: main
  commit-helper:
    role-of: small-fast
  lint-helper:
    role-of: small-fast
```

`config/distribution.yaml` の例:

```yaml
# 配布元リポジトリ URL (環境変数 override 可能)
distribution:
  primary:
    url_env: ENGINEER_CLAUDE_KIT_GIT_URL
    url_default: https://dev.azure.com/PLACEHOLDER_ORG/PLACEHOLDER_PROJ/_git/engineer-claude-kit
    host: ado
  mirrors:
    - url: https://github.com/ttamakijp/engineer-claude-kit
      host: github
      role: development
```

`apply-claude-kit.ps1` がこれらを Read → `~/.claude/settings.json` (model 直書き) と `bootstrap.ps1` 内の clone コマンドを generate する。

### C. PowerShell スクリプトの ASCII only 規約

すべての `.ps1` ファイルは ASCII 文字のみで記述する。理由:
- git commit すると UTF-8 BOM が剥落し、PowerShell が日本語混入時に文字化けで実行に失敗
- BOM 付き UTF-8 を強制する仕組みは git 管理下では不可能

実装規則:
- 関数名 / 変数名 / Write-Host 引数 / コメントを英語のみ
- エラーメッセージ・ログ出力も英語
- 日本語はドキュメント (`.md`) と config (`.yaml` で UTF-8 BOM なし保存可能なフィールド) に限定
- CI で `Get-ChildItem -Recurse -Include *.ps1 | Select-String -Pattern '[^\x00-\x7F]'` で違反を検出 (Phase 2 後半で導入)

### D. ADO の `_git` URL 形式

bootstrap.ps1 の clone は ADO の repo URL 形式 (`https://dev.azure.com/<org>/<proj>/_git/<repo>`) を前提とする。認証は以下優先順:

1. `$env:AZURE_DEVOPS_PAT` が設定済 → URL に embed
2. `git credential manager` の Windows Credential Store (Azure CLI の `az login` 連携で自動)
3. 未設定なら git が対話的に PAT を要求

### E. ADR-0001 §H (host = ADO 固定) との整合

ADR-0001 §H で「ADO 固定」を決定したが、現在 engineer-claude-kit は GitHub canonical で開発中。これは `config/distribution.yaml` の `mirrors[].role: development` で許容され、business deployment 時には `primary.url_env` 経由で ADO repo を canonical に指定する想定。

つまり同一 kit を 2 場所に配置可能: ADO (canonical) + GitHub (development mirror)。

## 検討した代替案

### 代替案 1: model ID / URL を直書きのまま運用
- メリット: 抽象化レイヤなし、シンプル
- デメリット: ADR-0001 §G-2 で予告したとおり model 更新 / repo 移行で broken

### 代替案 2: `config/*.yaml` ではなく環境変数のみで管理
- メリット: 1 階層のため依存少
- デメリット: 環境変数の network of defaults を把握するのが難しく、初心者には不向き

→ `config/*.yaml` + 環境変数 override の二段構成 (本 ADR 決定) を採用

## 未解決の問い

1. `apply-claude-kit.ps1` の **再 apply** 時の挙動 (overwrite / merge / skip の選択)。dev-templates の `apply-to-project.ps1 --dry-run` パターンを踏襲するか
2. ADO 認証フローの fallback として GitHub mirror も clone 候補に含めるか (社内→社外 mirror のフェイルオーバ)
3. `config/*.yaml` の schema validation (`scripts/validate-config.ps1`) を Phase 2 / Phase 3 のどちらで導入するか
4. ASCII only 規約の **自動検出** を pre-commit hook で行うか、CI でのみ行うか
5. dev-templates の `apply-cost-optimization.ps1` の中身 (Sonnet 自動委譲 logic) を Phase 2 で移植するか、再設計するか

## 結果

### 利点

- model ID / 配布元 URL のハードコーディング撤廃で **耐用年数** が伸びる
- 配布元 URL を `_git` の ADO 形式に固定しつつ環境変数 override で柔軟性確保
- ASCII only 縛りで **PowerShell 文字化け事故** を構造的に排除 (再発防止)
- ADO + Bedrock + Windows という業務環境前提を明示化、初心者の認知負荷を下げる
- ADR-0001 §G-2 の予告を本 ADR で具体化し、ADR トレーサビリティを確保

### 欠点

- `config/*.yaml` parser の実装が必要 (PowerShell ConvertFrom-Yaml モジュール、または独自 YAML パーサ)
- 抽象化レイヤ追加でデバッグが 1 段深くなる (config を読み忘れて直書きを編集する事故が起きうる)
- ASCII only 縛りでスクリプト内エラーメッセージが英語のみになり、業務環境の初心者には英語表示への抵抗感がある可能性

## 参照

- ADR-0001 (clean start design) §G モデル戦略 / §G-2 抽象化方針注記
- ADR-0002 (ADR portage triage) §B 変形移植カテゴリ (0040 bootstrap, 0044 Bedrock model ID, 0007 apply orchestration)
- dev-templates ADR-0040: `DEV_TEMPLATES_GIT_URL` 環境変数 override パターン
- dev-templates ADR-0007: apply-to-project orchestration (apply-claude-kit.ps1 の参考実装)
- dev-templates ADR-0042: apply-deploys-agents-and-settings (gen + 配布の参考)
- t-tamaki-todo `docs/2026-06-04-bedrock-1h-cache-investigation-complete.md` §3.1 / §8.1 (model ID 出典)
- t-tamaki-todo `docs/cost-timeline.md` (将来 Phase の見通し、本 ADR Phase 2/3 と整合)
