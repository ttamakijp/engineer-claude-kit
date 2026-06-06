# engineer-claude-kit シナリオ比較実験手順書

**関連**: `docs/manual-verification/bootstrap-installation.md` (機械的動作検証)、ADR-0001 (clean start), ADR-0003 (bootstrap), ADR-0004 (auto model routing)

本書は engineer-claude-kit の **実効果** を測定するため、グローバル / プロジェクト適用の有無で 4 シナリオ (A-D) を比較する。

## 必要環境

- Windows PC (PowerShell 5.1 or 7.x)
- git
- Claude Code CLI 本体
- AWS Bedrock credentials または Claude MAX 20x 契約 (V5 相当の adaptation 必要)
- engineer-claude-kit リポ clone 済 (`~/.claude-kit`)

**推奨**: clean Windows 環境 (VM / 別 PC) で実施。既存の `~/.claude/` を汚さない。

## シナリオ一覧

| ID | グローバル `~/.claude/` | プロジェクト `<proj>/.claude/` | 観察ポイント |
|---|---|---|---|
| A | なし | なし | ベースライン (Claude default 動作) |
| B | あり (kit 配置済) | なし | グローバル設定のみ効くか |
| C | なし | あり (kit -Project) | プロジェクト設定のみ効くか |
| D | あり | あり | 両方が共存・継承するか |

## 事前準備

### 既存環境のバックアップ

```powershell
# 既存 ~/.claude/ をバックアップ
if (Test-Path "$env:USERPROFILE\.claude") {
    $backupName = "$env:USERPROFILE\.claude.backup-pre-scenario-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -Recurse "$env:USERPROFILE\.claude" $backupName
    Write-Host "Backed up: $backupName"
}
```

### 共通テスト用 project dir を準備

各シナリオで同じ project dir を使い回し、シナリオ間で `.claude/` のみ on/off する。

```powershell
$projectDir = Join-Path $env:USERPROFILE "engineer-claude-kit-scenario-test"
if (Test-Path $projectDir) { Remove-Item -Recurse -Force $projectDir }
New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
cd $projectDir
git init
# 適当な README を作成しておく (テストプロンプトで使用)
"# Scenario Test Project" | Out-File -FilePath "README.md" -Encoding UTF8 -NoNewline
git add README.md
git commit -m "initial commit"
```

### 共通テストプロンプト 3 種

各シナリオで以下 3 つの同じ指示を与え、応答の差を観察する:

**T1**: 「このプロジェクトの README に簡単な説明を 3 行追加してコミットメッセージを生成してください」
- 観察: commit-msg sub-agent が呼ばれるか / Conventional Commits 形式になるか

**T2**: 「セキュリティチェックしてください」
- 観察: leak-check skill が認識されるか / 検出ロジックが動くか

**T3**: 「ADR の起票を手伝ってください」
- 観察: propose-adr skill が認識されるか / architect sub-agent が呼ばれるか

## シナリオ A: ベースライン (両方なし)

### Setup

```powershell
# グローバルとプロジェクト両方を空にする
Remove-Item -Recurse -Force "$env:USERPROFILE\.claude" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$projectDir\.claude" -ErrorAction SilentlyContinue
Remove-Item -Force "$projectDir\CLAUDE.md" -ErrorAction SilentlyContinue

cd $projectDir
```

### 実行

```powershell
claude   # or claude code
```

T1 / T2 / T3 を順に試す。

### 観察ポイント

- Claude は default 設定 (engineer-claude-kit の指示なし) で応答
- commit-msg / leak-check / propose-adr は **認識されない** (skill 不在)
- 応答が一般的・標準的な Claude default

### 結果記録テンプレ

```
### シナリオ A 結果
- 実施日: YYYY-MM-DD
- T1 応答 (要約): ...
- T2 応答 (要約): ...
- T3 応答 (要約): ...
- 観察: 期待通り default 動作。kit の影響なし
```

## シナリオ B: グローバルのみ

### Setup

```powershell
# プロジェクト側は空のまま、グローバルだけ配置
Remove-Item -Recurse -Force "$projectDir\.claude" -ErrorAction SilentlyContinue
Remove-Item -Force "$projectDir\CLAUDE.md" -ErrorAction SilentlyContinue

cd $env:USERPROFILE\.claude-kit
powershell -NoProfile -File scripts/apply-claude-kit.ps1 -Global
cd $projectDir
```

### 実行

```powershell
claude
```

T1 / T2 / T3 を順に試す。

### 観察ポイント

- グローバルの CLAUDE.md (Haiku/Sonnet 4.5 ルーティング指示) が読み込まれるか確認
  - 確認方法: Claude に「あなたは今どのモデルで動作していますか?」と質問
- T1: `commit-msg` sub-agent が **Task tool 経由** で呼ばれるか
- T2: グローバル skill `leak-check` が認識されるか
- T3: グローバル skill `propose-adr` + `architect` sub-agent が呼ばれるか

### 期待される差 (vs シナリオ A)

| | A (なし) | B (グローバルのみ) |
|---|---|---|
| 軽作業の Haiku 委譲 | なし | あり |
| sub-agent (commit-msg 等) 認識 | なし | あり |
| skill (leak-check, propose-adr) 認識 | なし | あり |
| プロジェクト固有 rule | なし | なし (variant) |

### 結果記録テンプレ

(シナリオ A と同様の形式)

## シナリオ C: プロジェクトのみ

### Setup

```powershell
# グローバルを空にする (B から戻す場合は backup から復元 or 削除)
Remove-Item -Recurse -Force "$env:USERPROFILE\.claude" -ErrorAction SilentlyContinue

# プロジェクトに配置
cd $env:USERPROFILE\.claude-kit
powershell -NoProfile -File scripts/apply-claude-kit.ps1 -Project $projectDir
cd $projectDir
```

### 実行

```powershell
claude
```

T1 / T2 / T3 を順に試す。

### 観察ポイント

- プロジェクト `CLAUDE.md` + `.claude/agents/` + `.claude/skills/` が認識されるか
- グローバル指示 (Haiku 委譲ルール 等) は **不在** のため、Sonnet 4.5 default で動作するか
- T1-T3: skill / sub-agent が **プロジェクトスコープで** 認識されるか確認

### 期待される差 (vs シナリオ B)

| | B (グローバルのみ) | C (プロジェクトのみ) |
|---|---|---|
| ルーティング指示 (Haiku 委譲) | グローバルから読込 | なし (Sonnet で全処理) |
| sub-agent | グローバル定義 | プロジェクト定義 |
| skill | グローバル定義 | プロジェクト定義 |
| プロジェクト切替時の継承 | 引き継がれる | プロジェクト出ると消える |

## シナリオ D: 両方 (グローバル + プロジェクト)

### Setup

```powershell
# 両方配置
cd $env:USERPROFILE\.claude-kit
powershell -NoProfile -File scripts/apply-claude-kit.ps1 -Global
powershell -NoProfile -File scripts/apply-claude-kit.ps1 -Project $projectDir
cd $projectDir
```

### 実行

```powershell
claude
```

T1 / T2 / T3 を順に試す。

### 観察ポイント

- グローバル CLAUDE.md + プロジェクト CLAUDE.md の両方が読み込まれるか
- 重複した skill / agent はどう扱われるか (グローバル優先? プロジェクト優先?)
- 同じ skill (例: commit-helper) がグローバルとプロジェクトの両方にある場合、どちらが発火するか

### 期待される差 (vs シナリオ B / C)

| | B | C | D |
|---|---|---|---|
| グローバル指示 | あり | なし | あり |
| プロジェクト指示 | なし | あり | あり |
| skill / agent 階層 | グローバルのみ | プロジェクトのみ | 両方 (階層 merge) |

### 観察すべき詳細

- グローバル / プロジェクトで同じ skill が定義されている場合、どちらが優先か (実機検証)
- プロジェクト固有 `rule` (`.claude/rules/*.md`) が **追加** されるか **上書き** されるか
- agent 定義の `model:` が プロジェクト側で override 可能か

## 結果比較表 (実施後に記入)

| 項目 | A | B | C | D |
|---|---|---|---|---|
| CLAUDE.md 認識 | | | | |
| commit-msg sub-agent 発火 | | | | |
| leak-check skill 発火 | | | | |
| propose-adr skill 発火 | | | | |
| Haiku 委譲動作 | | | | |
| プロジェクト切替時の引き継ぎ | | | | |
| 階層 merge 動作 | n/a | n/a | n/a | |

## クリーンアップ

```powershell
# シナリオ実験後、test project と適用を元に戻す
Remove-Item -Recurse -Force "$env:USERPROFILE\.claude" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$projectDir" -ErrorAction SilentlyContinue

# バックアップから復元 (シナリオ実験で削除した既存 ~/.claude/)
$backupGlob = Join-Path $env:USERPROFILE ".claude.backup-pre-scenario-*"
$latestBackup = Get-ChildItem -Path $backupGlob -Directory | Sort-Object Name -Descending | Select-Object -First 1
if ($latestBackup) {
    Move-Item $latestBackup.FullName "$env:USERPROFILE\.claude"
    Write-Host "Restored from: $($latestBackup.FullName)"
}
```

## MAX 環境での実施上の注意

- 各シナリオで `apply-claude-kit.ps1` が配置する `settings.json` / `agents/*.md` の model ID は **Bedrock 形式** (`us.anthropic.claude-...`)
- MAX 環境で実 Claude セッションテストするには、`docs/manual-verification/bootstrap-installation.md` の V5b に記載した model ID adaptation (Anthropic API 形式への一時置換) を各シナリオ Setup の最後に実施する
- adaptation スクリプト:

```powershell
# シナリオ B / D の Setup 後に実行
$settingsPath = Join-Path $env:USERPROFILE ".claude" "settings.json"
if (Test-Path $settingsPath) {
    $content = Get-Content -Raw $settingsPath
    $content = $content -replace 'us\.anthropic\.claude-sonnet-4-5-20250929-v1:0', 'claude-sonnet-4-5-20250929'
    $content = $content -replace 'us\.anthropic\.claude-haiku-4-5-20251001-v1:0', 'claude-haiku-4-5-20251001'
    Set-Content -Path $settingsPath -Value $content -Encoding UTF8 -NoNewline
}

# agents 内の model ID も adaptation
Get-ChildItem (Join-Path $env:USERPROFILE ".claude" "agents") -Filter "*.md" -ErrorAction SilentlyContinue | ForEach-Object {
    $c = Get-Content -Raw $_.FullName
    $c = $c -replace 'us\.anthropic\.claude-sonnet-4-5-20250929-v1:0', 'claude-sonnet-4-5-20250929'
    $c = $c -replace 'us\.anthropic\.claude-haiku-4-5-20251001-v1:0', 'claude-haiku-4-5-20251001'
    Set-Content -Path $_.FullName -Value $c -Encoding UTF8 -NoNewline
}

# シナリオ C / D のプロジェクト側 agents も同様
$projectAgentsDir = Join-Path $projectDir ".claude" "agents"
if (Test-Path $projectAgentsDir) {
    Get-ChildItem $projectAgentsDir -Filter "*.md" | ForEach-Object {
        $c = Get-Content -Raw $_.FullName
        $c = $c -replace 'us\.anthropic\.claude-sonnet-4-5-20250929-v1:0', 'claude-sonnet-4-5-20250929'
        $c = $c -replace 'us\.anthropic\.claude-haiku-4-5-20251001-v1:0', 'claude-haiku-4-5-20251001'
        Set-Content -Path $_.FullName -Value $c -Encoding UTF8 -NoNewline
    }
}
```

## 期待される全体結論 (実験前の仮説)

- **A → B**: グローバル kit 適用で「軽作業の Haiku 委譲」が起動 (cost 削減)、skill が利用可能になる (UX 向上)
- **B → C**: プロジェクト個別設定で技術スタック固有の指示が効く (今は同じ template だが、将来プロジェクト固有 CLAUDE.md を持つようになる)
- **C → D**: 階層 merge で「業務全体の指示」+「プロジェクト固有」が両立、これが kit の最終形

仮説と乖離があれば、ADR-0001/0003/0004 の前提見直し → 次 Phase の implementation に反映

## 関連

- ADR-0001 §G (モデル戦略)
- ADR-0003 §A bootstrap フロー / §B config SSoT
- ADR-0004 §A 2 層ルーティング / §B sub-agent 6 種
- `docs/manual-verification/bootstrap-installation.md` (機械的動作検証、V1-V6)
