# engineer-claude-kit bootstrap 動作検証手順書

**関連**: Phase 1 (config + build-rules), Phase 2 (templates + apply + bootstrap), Phase 3.1 (common skills), Phase 3.2 (cost-observe)

本書は Phase 1-3 で実装した bootstrap chain を Windows 環境で検証する手順を定める。Claude MAX 20x 契約環境 (AWS Bedrock アクセスなし) でも実施可能な範囲を明示する。

## 必要環境

| # | 必須 | 用途 | MAX 環境で必要か |
|---|---|---|---|
| 1 | Windows PC (PowerShell 5.1 or 7.x) | bootstrap.ps1 実行 | OK |
| 2 | git (GitHub アクセス) | 本リポ clone | OK |
| 3 | インターネット接続 | git + 実 Claude セッション (V5 adapted) | OK |
| 4 | Claude Code CLI 本体 | V5 で実セッションテスト時 | COND MAX 契約で利用可 |
| 5 | AWS Bedrock credentials (`aws configure` 済) | V5 / V6 の本来想定 | NG Bedrock SKIP |
| 6 | 任意の git project dir (空でも可) | -Project mode の対象 | OK |

**推奨**: 既存の `~/.claude/` を汚さないため **clean Windows 環境** (VM / 別 PC / 退避済 backup) での実施を推奨。

## 事前準備

### A. 既存 `~/.claude/` のバックアップ (clean 環境でない場合)

```powershell
# 既存ファイルを保護
if (Test-Path "$env:USERPROFILE\.claude") {
    Copy-Item -Recurse "$env:USERPROFILE\.claude" "$env:USERPROFILE\.claude.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Write-Host "Backed up existing ~/.claude/"
}
```

### B. リポを clone

```powershell
cd $env:USERPROFILE
git clone https://github.com/ttamakijp/engineer-claude-kit.git .claude-kit
cd .claude-kit
```

(ADO 形式テストの場合は `git clone https://dev.azure.com/<org>/<proj>/_git/engineer-claude-kit ".claude-kit"`、ただし本検証では GitHub mirror で代替可)

## 検証項目 V1-V6

### V1: build-rules.ps1 の単独動作 (env-agnostic)

**目的**: `source/rules/` から `dist/.claude/rules/` への build が正常に完了するか

```powershell
cd $env:USERPROFILE\.claude-kit
pwsh -NoProfile -File scripts/build-rules.ps1 -DryRun
pwsh -NoProfile -File scripts/build-rules.ps1
```

**期待結果**:
- `dist/.claude/rules/commit-convention.md`
- `dist/.claude/rules/file-granularity.md`
- `dist/.claude/rules/security-mobile.md`

-> 3 ファイル生成、内容に `audience: [claude]` frontmatter を含むこと

**MAX 環境**: OK 実施可

### V2: apply-claude-kit.ps1 の -DryRun 動作 (env-agnostic)

**目的**: ファイル配置のシミュレーションが正常に走るか

```powershell
pwsh -NoProfile -File scripts/apply-claude-kit.ps1 -Global -DryRun
```

**期待結果**:
- 7 ファイル (CLAUDE.md + agents 6 種) + 3 skill = 計 10 ファイルのプレビュー
- 出力に `[dry-run]` プレフィックス
- 実ファイル書き込みなし

**MAX 環境**: OK 実施可

### V3: apply-claude-kit.ps1 の実 -Project mode 配置 (env-agnostic)

**目的**: mock project dir に実際に配置できるか、placeholder substitution が成功するか

```powershell
$mockDir = Join-Path $env:TEMP "eck-verification-$(Get-Date -Format yyyyMMddHHmmss)"
New-Item -ItemType Directory -Force -Path $mockDir | Out-Null
pwsh -NoProfile -File scripts/apply-claude-kit.ps1 -Project $mockDir
```

**期待結果**:
- `$mockDir/CLAUDE.md`
- `$mockDir/.claude/agents/{commit-msg,lint-helper,log-summary,review,architect,debug-analyze}.md` (6 種)
- `$mockDir/.claude/skills/{commit-helper,leak-check,propose-adr}/SKILL.md` (3 種)
- `$mockDir/.engineer-claude-kit-applied` (JSON marker)

**placeholder 検証**:

```powershell
Get-Content (Join-Path $mockDir ".claude" "agents" "commit-msg.md") | Select-String -Pattern "model:"
# 期待: model: "us.anthropic.claude-haiku-4-5-20251001-v1:0"

Get-ChildItem $mockDir -Recurse -Include *.md | Select-String -Pattern '\{\{role:'
# 期待: 出力空 (全 placeholder が substitution されている)
```

**MAX 環境**: OK 実施可。**注意**: substitution された model ID は Bedrock 形式のため、このままでは MAX で動作しない (V5 で adaptation する)。

### V4: bootstrap.ps1 の DryRun 動作 (env-agnostic)

**目的**: bootstrap が clone 検出 + apply-claude-kit invoke の経路を正しく辿るか

```powershell
pwsh -NoProfile -File scripts/bootstrap.ps1 -DryRun -SkipProjectPrompt
```

**期待結果**:
- `[ok] kit structure validated`
- `[url] derived from git remote: <URL>` (= GitHub URL が取得される)
- `[dry-run] would set user env ENGINEER_CLAUDE_KIT_GIT_URL = <URL>`
- `apply-claude-kit.ps1 -Global -DryRun` が internal で呼び出される
- 計 10 ファイルの dry-run プレビューが出力
- `Bootstrap complete.`

**user 環境変数の永続化されないことを確認**:

```powershell
[Environment]::GetEnvironmentVariable("ENGINEER_CLAUDE_KIT_GIT_URL", "User")
# 期待: $null または既存値のまま (DryRun のため新規設定なし)
```

**MAX 環境**: OK 実施可

### V5: 実 Claude Code セッションでの動作テスト (MAX adaptation)

**目的**: 配置された `~/.claude/` (or mock dir) で実際に Claude が動作するか

#### V5a: Bedrock 想定での試行 (Bedrock credentials 不在 -> 失敗想定)

```powershell
cd $mockDir
claude  # or claude code
```

**期待結果 (Bedrock 想定のまま)**:
- `~/.claude/settings.json` に Bedrock model ID が書かれているため、Claude Code が Bedrock 接続を試行 -> 認証失敗 / model not found エラー

**MAX 環境**: NG 失敗想定 (正常な反応)

#### V5b: Anthropic API 形式に adapt して試行

`settings.json` 内の model ID を一時置換:

```powershell
$settingsPath = Join-Path $env:USERPROFILE ".claude" "settings.json"
$content = Get-Content -Raw $settingsPath
$content = $content -replace 'us\.anthropic\.claude-sonnet-4-5-20250929-v1:0', 'claude-sonnet-4-5-20250929'
$content = $content -replace 'us\.anthropic\.claude-haiku-4-5-20251001-v1:0', 'claude-haiku-4-5-20251001'
Set-Content -Path $settingsPath -Value $content -Encoding UTF8 -NoNewline

# agents 内の model ID も同様
Get-ChildItem (Join-Path $env:USERPROFILE ".claude" "agents") -Filter "*.md" | ForEach-Object {
    $c = Get-Content -Raw $_.FullName
    $c = $c -replace 'us\.anthropic\.claude-sonnet-4-5-20250929-v1:0', 'claude-sonnet-4-5-20250929'
    $c = $c -replace 'us\.anthropic\.claude-haiku-4-5-20251001-v1:0', 'claude-haiku-4-5-20251001'
    Set-Content -Path $_.FullName -Value $c -Encoding UTF8 -NoNewline
}
```

```powershell
cd $mockDir
claude
```

**期待結果**:
- Claude MAX 経由で Sonnet 4.5 / Haiku 4.5 が応答
- CLAUDE.md のルーティング指示が認識される (「コミットメッセージ作って」で commit-msg sub-agent が呼ばれる等)
- agents の各 sub-agent が機能する

**MAX 環境**: WARN 実施可だが、**Anthropic API 形式での Claude Code 動作は要実機検証**。MAX 契約での API access の仕様によって挙動が変わる可能性あり

**注意**: V5b で書き換えた settings.json / agents は、Bedrock 環境で再 apply する際に元に戻る (apply-claude-kit.ps1 が再 substitution するため)。テスト後の手動 revert は不要。

### V6: cost-observe-bedrock.ps1 (Bedrock 専用、MAX 環境 SKIP)

**目的**: AWS Cost Explorer 経由で Bedrock コストを取得

```powershell
pwsh -NoProfile -File scripts/cost-observe-bedrock.ps1 -DryRun
```

**期待結果 (Bedrock 環境想定)**:
- `aws ce get-cost-and-usage` コマンドが組み立てられる
- 実行されず (DryRun のため)

**MAX 環境**: NG **SKIP** (AWS CLI 不在 + Bedrock アクセスなしのため、本検証の範囲外)

dry-run まで動作確認するだけでも以下が確認可能:
- スクリプトが ASCII only で書かれている
- 引数パースが正常に動く
- AWS CLI 不在時の warning メッセージが適切

## 検証結果記録

各 V1-V6 の結果を本書の末尾に追記する形式:

```
## 実施結果

### 実施日: YYYY-MM-DD
### 実施環境: Windows 11 + Claude MAX 20x

#### V1 (build-rules.ps1)
- [PASS/FAIL]: 詳細...
- 生成ファイル数: 3

#### V2 (apply-claude-kit -DryRun)
- [PASS/FAIL]: 詳細...

(以下 V3-V6 同様)

### 全体判定
- MAX 環境で実施可能な範囲 (V1-V4 + V5b) は [全て PASS / 部分 FAIL: <内容>]
- Bedrock 専用 (V5a + V6) は SKIP
- 次のアクション: <Phase 4 着手 / 不具合修正 / etc>
```

## 注意事項

- V3 で配置された mock dir は検証完了後に削除推奨: `Remove-Item -Recurse -Force $mockDir`
- V5b で `~/.claude/` を直接書き換える場合は、事前準備 A のバックアップを必ず実施
- 本検証は **本番運用前の Phase 1-3 健全性確認**。MAX 環境で完走できれば、Phase 4 の追加実装着手判断 OK
- Bedrock 環境での完全動作は別途 (実 Bedrock 環境利用可能になった時) 検証する

## 関連

- ADR-0001 (clean start design) §G モデル戦略
- ADR-0003 (bootstrap design) §A bootstrap フロー
- ADR-0004 (auto model routing) §B sub-agent 定義
- README §6 制約 (Windows + PowerShell ASCII only)
