# Settings.json Setup Guide

このガイドは engineer-claude-kit (以下 kit) を導入したあと、`~/.claude/settings.json` を user 自身で設定する手順を示します。

## 背景: hands-off ポリシー

kit は `~/.claude/settings.json` を**無確認で**生成・上書きしません (ADR-0007)。理由:

- Bedrock 接続設定や推奨 model ID は動的 (AWS region、cache 仕様、新 model release で変わる)
- settings.json は user environment config の領域 (個人 preference や機密を含む)
- CLAUDE.md / rules / agents / skills (kit が ship する部品) とは責務の質が違う

## 対話的セットアップ wizard (opt-in、ADR-0010)

手動コピーの摩擦を減らすため、`bootstrap.ps1` 末尾と `apply-claude-kit.ps1 -Global` 末尾で**対話的 wizard** が起動します。これは hands-off ポリシーの**明示承認例外**であり、以下を厳守します:

- **項目ごとに Y/N 確認** (default = Y、Enter で追加、明示的に N / s で skip)
- **欠落 key のみ deep merge** — 既存の `theme` / `env` 等の値は決して上書きしない
- **変更前に backup** (`settings.json.bak-<timestamp>`)
- **非対話なら自動 skip** — `-NonInteractive` / `$env:CI` / 非対話コンソールでは何もしない (CI / scripted 経路は不変)

対象 key:

| key | 内容 |
|---|---|
| `statusLine` | 現在の model 名 + context 使用率を**色分け表示** (PowerShell ネイティブ、jq 不要。`docs/setup/statusline-powershell.example.json` 参照) |
| `env.ANTHROPIC_SMALL_FAST_MODEL` | Haiku 委譲を有効化 (ADR-0004)。Bedrock / Anthropic API 直で形式を出し分け |

### statusLine の context % 色分け (ADR-0012)

deploy される statusLine は context 使用率に応じて ANSI escape で色を変え、視覚的に `/compact` を促します:

| context % | 色 | ANSI code | 推奨アクション |
|---|---|---|---|
| `< 75%` | 緑 | `32` | 通常運用 |
| `75-90%` | 黄 | `33` | 区切りの良いタイミングで `/compact` |
| `>= 90%` | 赤 | `31` | 即座に `/compact` (auto-compact 95% を回避) |

背景: Claude Code には `/compact` の真の auto-trigger が無く (hooks は slash command を発火できず、
Claude 自身は context % をリアルタイム不可視)、auto-compact は内部 ~95% でのみ動作し summary loss
リスクがある。色分けで満杯前に user が能動的に compact できるようにする半自動化です (ADR-0012)。

統計ロジックは inline (`statusLine.command` の中) ではなく、wizard が deploy する
`~/.claude/statusline.ps1` に置かれます。`statusLine.command` は
`powershell -NoProfile -File "<...>/statusline.ps1"` の形でこのスクリプトを参照するだけです
(ADR-0012 の 2026-06-09 amendment)。threshold を変えたい場合は `~/.claude/statusline.ps1` 内の
`90` / `75` を編集してください。ANSI escape の prefix は `[char]27` (PS 5.1 互換) で記述しています。
Windows Terminal は ANSI 対応、legacy cmd.exe console は非対応 (Claude Code は Windows Terminal 推奨)。

> **なぜ inline `-Command` でなく `-File` か (-File 採用理由)**: Windows で Git Bash が入っていると
> Claude Code は statusLine command を Git Bash 経由で実行する。inline
> `powershell -Command "...$_..."` は PowerShell が読む前に bash が `$input` / `$_` 等の `$` トークンを
> 展開してコマンドを破壊し、statusline が**無音で空表示 (blank)** になる。`-File <path>` は `$` トークンを
> 持たないため bash 経由でも壊れない。既に inline 版を設定済みの場合は、
> `statusLine.command` を上記 `-File` 形に書き換えてください (wizard は既存 `statusLine` を上書きしない)。

### wizard を skip したい場合

```powershell
# bootstrap 全体で wizard を起動しない
& "$env:USERPROFILE\.claude-kit\scripts\bootstrap.ps1" -NoSettingsWizard

# 非対話で強制 skip (CI 等。$env:CI でも自動 skip される)
powershell -NoProfile -File "$env:USERPROFILE\.claude-kit\scripts\apply-claude-kit.ps1" -Global -NonInteractive
```

wizard を使わず手動で設定したい場合は、以下の環境別手順をそのまま使えます。

## 環境別の選択

| 環境 | 設定例ファイル |
|---|---|
| AWS Bedrock | docs/setup/settings-bedrock.example.json |
| Anthropic API 直 | docs/setup/settings-anthropic.example.json |

どちらか 1 つを `~/.claude/settings.json` にコピーして使います。

## 手順 (Bedrock 環境)

```powershell
# 例 (kit が ~/.claude-kit/ にある想定)
Copy-Item ~/.claude-kit/docs/setup/settings-bedrock.example.json ~/.claude/settings.json
```

その後:

1. 必要に応じて `AWS_REGION` を実環境に合わせて編集
2. AWS credentials を別途設定 (`aws configure` 等)
3. Bedrock model が region で利用可能か確認

## 手順 (Anthropic API 直)

```powershell
Copy-Item ~/.claude-kit/docs/setup/settings-anthropic.example.json ~/.claude/settings.json
```

その後:

1. `ANTHROPIC_API_KEY` を環境変数 or `~/.claude/.env` で別途設定
2. https://console.anthropic.com/ で API key を取得

## 既存 settings.json がある場合

**上書き前に backup を推奨**:

```powershell
$backup = "$env:USERPROFILE\.claude\settings.json.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item "$env:USERPROFILE\.claude\settings.json" $backup
Write-Host "Backup: $backup"
```

既存の `theme` や `autoUpdatesChannel` 等は、設定例にマージして手動保持してください。

## トラブルシュート

| 症状 | 原因 | 対処 |
|---|---|---|
| `Could not load credentials from any providers` | AWS credentials が設定されていない or Bedrock 専用キーが Anthropic 環境で残っている | Bedrock なら `aws configure`、Anthropic なら `CLAUDE_CODE_USE_BEDROCK` 等を削除 |
| model ID 不一致 (404 や parse エラー) | backend と model ID 形式が不一致 (Bedrock 形式 vs Anthropic 形式) | 該当 backend の example を再度コピー |
| 起動後 model 選択がデフォルトに戻る | settings.json が JSON として不正 | `Test-Json` 等で検証、構文エラー修正 |

## Refs

- ADR-0007: docs/adr/0007-hands-off-settings.md
- ADR-0010: docs/adr/0010-interactive-settings-wizard.md
- ADR-0012: docs/adr/0012-context-awareness-convention.md (statusLine 色分け)
- Claude Code 公式 docs: https://docs.claude.com/en/docs/build-with-claude/