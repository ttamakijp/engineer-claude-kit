# ADR-0003: Bootstrap design + 設定値の抽象化 SSoT 化

**ステータス**: Proposed (2026-06-08 Update: §B 配布元 URL 解決方針を現状実装に合わせて修正 / §C に encoding helper rule を追記 / 2026-06-08 Update P8: §C に PS 5.1 互換 hard rule を追加)
**日付**: 2026-06-05 (Update: 2026-06-08)
**Phase**: 1 → 2 (foundation → bootstrap implementation 設計)
**関連**: ADR-0001 (clean start design) / ADR-0002 (ADR セット取捨選択方針) / ADR-0008 (privilege-aware bootstrap)

> **2026-06-08 Update (P5)**: 当初 §B で `config/distribution.yaml` に `url_default` (ハードコードされた配布元 URL の最終 fallback) を持たせる設計だったが、`bootstrap.ps1` はこれを参照せず、clone 済み作業ツリーの `git remote get-url origin` から配布元 URL を導出する実装になっている。実装が無い設定を残すと混乱の元になるため **`url_default` フィールドを削除** し、配布元 URL 解決の優先順位を「環境変数 > `-GitUrl` 引数 > `git remote` 導出」に修正する。配布先別の clone URL (GitHub / Azure DevOps `_git` / self-hosted) は kit 内に埋め込まず、README で generic な `<repository-url>` 表記 + 配布先別注釈で示す方針とする。本 Update は Superseded ではなく、現状実装への整合 (追記修正) である。下記 §B / §A 詳細フェーズの該当箇所に Update 注記を付す。

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
1. clone 元 URL を解決: 環境変数 `ENGINEER_CLAUDE_KIT_GIT_URL` > 引数 `-GitUrl` > clone 済み作業ツリーの `git remote get-url origin` から導出 (2026-06-08 Update: 当初記載の「既定値 `https://dev.azure.com/<DEFAULT_ORG>/<DEFAULT_PROJ>/_git/engineer-claude-kit`」は実装されておらず削除。ハードコードされた fallback は持たない)
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
# Bedrock model registry (Phase 1 実測値、実環境での Bedrock 1h cache 実測検証 §3.1/§8.1 出典)
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

`config/distribution.yaml` の例 (2026-06-08 Update: 未参照だった `url_default` を削除):

```yaml
# 配布元リポジトリ URL メタデータ (環境変数 override 可能)
# clone URL は git remote から導出するため、ハードコードされた url_default は持たない
distribution:
  primary:
    url_env: ENGINEER_CLAUDE_KIT_GIT_URL
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

**ファイル encoding hard rule (2026-06-08 追記, P6)**:

スクリプト本体の ASCII only 規約に加え、スクリプトが**生成・書込み・読込みするファイル** (`.md` / `.json` / `.yaml`) は **UTF-8 (no BOM)** を強制する:

- PS スクリプト内の書込みは必ず `scripts/lib/encoding-helper.ps1` の `Write-Utf8NoBom` 経由とする
- 読込みも同 helper の `Read-Utf8NoBom` 経由とする
  - PS 5.1 の `Get-Content` 既定 encoding はシステム ANSI codepage (日本語 Windows = CP932) で、UTF-8 ソースを誤デコードして mojibake 化する。これを書込み側で正しく UTF-8 保存すると二重エンコード化けが確定する (実害: デプロイ済 `~/.claude/CLAUDE.md` / `docs/adr/0007-*.md`)
- 直接 `Out-File` / `Set-Content -Encoding UTF8` / `[System.IO.File]::WriteAllText` / encoding 指定なしの `Get-Content -Raw` を使ってはならない
  - PS 5.1 の `-Encoding UTF8` は **BOM 付き UTF-8** を出力し (`EF BB BF`)、frontmatter `---` の前に BOM が混入して parse 失敗・git binary marker 警告を招く。この設計上の trap を構造的に防ぐため
- 例外: log / 一時ファイルでユーザ visible でないもの、および ASCII のみの flat config の行単位読込みは制約外
- 自動検出 (PSScriptAnalyzer custom rule) は「未解決の問い」6 を参照

**PS 5.1 互換 hard rule (2026-06-08 追記, P8)**:

スクリプト本体 (`scripts/**/*.ps1`, `tests/**/*.tests.ps1`) は **Windows PowerShell 5.1 互換を必須** とする。Windows 既定で同梱されるのは Windows PowerShell 5.1 であり、pwsh (PowerShell 7+) 未 install 環境を排除しないため:

- 以下の **PowerShell 7+ 専用構文を禁止**:
  - null-conditional `?.` / null-coalescing `??` / null-coalescing 代入 `??=`
  - ternary `<cond> ? <a> : <b>`
  - PS 7+ 専用パラメータ (例: `Invoke-WebRequest -SkipHeaderValidation`)
  - PS 7+ 専用 cmdlet
  - 置換指針: `?.` → `if ($x) { $x.foo }`、`??` → 明示的な `if (-not $x) { $default }`、ternary → `if`/`else`
- `[Type]::new(...)` constructor 構文は `New-Object` を優先する (一部 PS 5.1 でも `::new()` は動くが、analyzer profile / 可読性の統一のため `New-Object` に揃える。privilege-check.ps1 の `New-Object Security.Principal.WindowsPrincipal(...)` が範例)
- doc / 例で `pwsh -File ...` を使う場合は **`powershell -File ...` でも動く** ことを注記する、または「PS 5.1 / pwsh どちらでも可」を明記する。pwsh 推奨理由 (出力 encoding が既定 UTF-8 で文字化け事故が減る / クロスプラットフォーム動作) は 1 行添える
- **自動検出は導入済**: `PSScriptAnalyzerSettings.psd1` が `PSUseCompatibleSyntax` (`TargetVersions = 5.1`) + `PSUseCompatibleCommands` (PS 5.1 profile) を `IncludeRules` で有効化しており、`scripts/lint.ps1 -Strict` および CI (PS 5.1 + PS 7 matrix) で PS 7+ 構文を exit 1 で検出する。これにより本 hard rule は規約と機械検査の両面で担保される
- 理由: Windows 既定の Windows PowerShell 5.1 で動作することを保証し、pwsh 未 install 環境を排除しない

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

1. `apply-claude-kit.ps1` の **再 apply** 時の挙動 (overwrite / merge / skip の選択)。再 apply 時の `--dry-run` パターンを踏襲するか
2. ADO 認証フローの fallback として GitHub mirror も clone 候補に含めるか (社内→社外 mirror のフェイルオーバ)
3. `config/*.yaml` の schema validation (`scripts/validate-config.ps1`) を Phase 2 / Phase 3 のどちらで導入するか
4. ASCII only 規約の **自動検出** を pre-commit hook で行うか、CI でのみ行うか
5. コスト最適化スクリプト (Sonnet 自動委譲 logic) を Phase 2 で実装するか、再設計するか
6. (2026-06-08 追記, P6) ファイル encoding hard rule の **自動検出**: `Out-File` / `Set-Content -Encoding UTF8` / 生 `[System.IO.File]::WriteAllText` / encoding 指定なし `Get-Content -Raw` の直接使用を PSScriptAnalyzer custom rule で warn 検出するか。P6 時点では規約のみ整備し、自動検出 rule は別 Issue に切り出して見送り (helper 自体は suppress 対象)

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
- ADR-0002 (ADR セット取捨選択方針) §B 変形採用カテゴリ (bootstrap, Bedrock model ID, apply orchestration)
- 配布元 URL は `ENGINEER_CLAUDE_KIT_GIT_URL` 環境変数 override パターンで解決 (§B)
- apply orchestration は apply-claude-kit.ps1 として実装 (§A/§B)
- agents + settings の generate / 配布は apply-claude-kit.ps1 が担当 (§B)
- model ID 出典: 実環境での Bedrock 1h cache 実測検証 §3.1 / §8.1
- 将来 Phase の見通しは本 ADR Phase 2/3 と整合
