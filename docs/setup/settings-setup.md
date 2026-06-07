# Settings.json Setup Guide

このガイドは engineer-claude-kit (以下 kit) を導入したあと、`~/.claude/settings.json` を user 自身で設定する手順を示します。

## 背景: hands-off ポリシー

kit は `~/.claude/settings.json` を生成・上書きしません (ADR-0007)。理由:

- Bedrock 接続設定や推奨 model ID は動的 (AWS region、cache 仕様、新 model release で変わる)
- settings.json は user environment config の領域 (個人 preference や機密を含む)
- CLAUDE.md / rules / agents / skills (kit が ship する部品) とは責務の質が違う

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
- Claude Code 公式 docs: https://docs.claude.com/en/docs/build-with-claude/