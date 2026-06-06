---
name: leak-check
description: |
  PII / credentials / API keys を検出する簡易セキュリティチェック skill。
  pre-commit 想定 + ad-hoc 確認の両用。
---

# leak-check

対象ファイル群を scan して以下を検出する:

- 個人情報 (メールアドレス、電話番号、住所、氏名)
- credentials (API key, token, password の literal)
- 機密ファイル名 (`.env*` / `*.keystore` / `local.properties`)
- 絶対パス (`C:\Users\<個人名>`)

## 起動条件

ユーザが以下のいずれかを依頼したとき:
- 「セキュリティチェック」「leak 確認」「PII 検出」
- commit / push の直前確認
- 「これコミットしていい?」

## 実行手順

1. 対象範囲を確定:
   - default: `git diff HEAD` の対象ファイル
   - 全体: `git ls-files` (明示指定された場合のみ)
2. 各ファイルに対し以下の検出を実行:
   - **PII regex**:
     - メール: `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}`
     - 電話 (日本): `0[789]0-?\d{4}-?\d{4}`、`\+81[789]0\d{4}\d{4}`
     - 電話 (米): `\+?1?[-.]?\(?\d{3}\)?[-.]?\d{3}[-.]?\d{4}`
     - 郵便番号 (日本): `〒?\d{3}-\d{4}`
   - **credentials regex**:
     - AWS: `AKIA[0-9A-Z]{16}` / `aws_secret_access_key\s*=\s*[A-Za-z0-9/+=]{40}`
     - Bedrock: `anthropic-bedrock-api-key`
     - GitHub: `ghp_[A-Za-z0-9]{36,}` / `gho_[A-Za-z0-9]{36,}`
     - Generic: `api[_-]?key\s*[:=]\s*['""][^'""]+['""]`
3. 検出結果を以下のフォーマットで報告:

```
## leak-check 結果
- 対象: <N> ファイル
- 検出: <M> 件

### CRITICAL (block-merge 推奨)
- [file:line] <type>: <抜粋>

### WARN (要確認)
- [file:line] <type>: <抜粋>
```

4. 検出ゼロの場合は「✓ leak なし」と報告

## 制約

- 検出は **正規表現ベースの簡易実装**。誤検知 / 見逃しの可能性あり (本格的には `gitleaks` 推奨)
- 検出した値そのものをログ / ファイルに残さない (再露出リスク)
- block-merge の最終判定はユーザに委ねる (skill は判定材料を提示するのみ)
- 既存 security-mobile rule (`~/.claude/rules/security-mobile.md`) を必ず参照
