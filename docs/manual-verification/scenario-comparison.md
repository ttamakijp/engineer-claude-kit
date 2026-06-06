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

### 結果記録テンプレ (5 軸)

5 軸 = 使用モデル / 解答内容 / コスト / 応答時間 / tool 利用。計測手順は本書「計測方法と環境差分」を参照。

### シナリオ A 結果
- 実施日: YYYY-MM-DD
- 環境: <Windows 11 + Claude MAX 20x | Windows 11 + Bedrock>
- 全体観察: 期待通り default 動作。kit の影響なし

#### T1 (コミットメッセージ生成)
- 使用モデル (main agent): <Sonnet 4.5 / Haiku 4.5 / other>
- sub-agent 起動: <yes (どの agent) / no>
- tool 利用: <Read, Edit, Bash, Task, etc. の回数>
- 応答時間: <X 秒>
- 解答 (full text):

  ```
  <Claude の応答をそのまま貼る>
  ```

- 品質評価: <Conventional Commits 形式? Y/N、scope 適切? Y/N、subject 50 文字以下? Y/N>
- input token: <N>
- output token: <M>
- 概算コスト: <$X> (環境別単価で計算、後述「コスト計算式」参照)

#### T2 (セキュリティチェック)
(T1 と同じ書式)

#### T3 (ADR 起票)
(T1 と同じ書式)

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

### 結果記録テンプレ (5 軸)

書式はシナリオ A と同一 (使用モデル / 解答 full text / token / コスト / 応答時間 / tool 利用)。シナリオ B 固有の補足を 全体観察 に記録。

### シナリオ B 結果
- 実施日: YYYY-MM-DD
- 環境: <Windows 11 + Claude MAX 20x | Windows 11 + Bedrock>
- 全体観察: グローバル kit のみ適用。Haiku 委譲 / sub-agent / skill 発火を A と比較
- シナリオ固有の補足: グローバル CLAUDE.md のルーティング指示が読み込まれたか (モデル質問で確認)

#### T1 (コミットメッセージ生成)
- 使用モデル (main agent): <Sonnet 4.5 / Haiku 4.5 / other>
- sub-agent 起動: <yes (どの agent) / no>  ※ commit-msg sub-agent 発火が核心
- tool 利用: <Read, Edit, Bash, Task, etc. の回数>
- 応答時間: <X 秒>
- 解答 (full text):

  ```
  <Claude の応答をそのまま貼る>
  ```

- 品質評価: <Conventional Commits 形式? Y/N、scope 適切? Y/N、subject 50 文字以下? Y/N>
- input token: <N>
- output token: <M>
- 概算コスト: <$X> (環境別単価で計算、後述「コスト計算式」参照)

#### T2 (セキュリティチェック)
(T1 と同じ書式。leak-check skill 発火を観察)

#### T3 (ADR 起票)
(T1 と同じ書式。propose-adr skill + architect sub-agent 発火を観察)

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

### 結果記録テンプレ (5 軸)

書式はシナリオ A と同一 (使用モデル / 解答 full text / token / コスト / 応答時間 / tool 利用)。シナリオ C 固有の補足を 全体観察 に記録。

### シナリオ C 結果
- 実施日: YYYY-MM-DD
- 環境: <Windows 11 + Claude MAX 20x | Windows 11 + Bedrock>
- 全体観察: プロジェクト kit のみ適用。グローバル指示不在のため Sonnet 4.5 default で動作するか
- シナリオ固有の補足: skill / sub-agent がプロジェクトスコープで認識されるか、Haiku 委譲が起きないか

#### T1 (コミットメッセージ生成)
- 使用モデル (main agent): <Sonnet 4.5 / Haiku 4.5 / other>
- sub-agent 起動: <yes (どの agent) / no>  ※ プロジェクト定義の commit-msg を参照
- tool 利用: <Read, Edit, Bash, Task, etc. の回数>
- 応答時間: <X 秒>
- 解答 (full text):

  ```
  <Claude の応答をそのまま貼る>
  ```

- 品質評価: <Conventional Commits 形式? Y/N、scope 適切? Y/N、subject 50 文字以下? Y/N>
- input token: <N>
- output token: <M>
- 概算コスト: <$X> (環境別単価で計算、後述「コスト計算式」参照)

#### T2 (セキュリティチェック)
(T1 と同じ書式。プロジェクト定義 leak-check skill 発火を観察)

#### T3 (ADR 起票)
(T1 と同じ書式。プロジェクト定義 propose-adr skill 発火を観察)

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

### 結果記録テンプレ (5 軸)

書式はシナリオ A と同一 (使用モデル / 解答 full text / token / コスト / 応答時間 / tool 利用)。シナリオ D 固有の補足を 全体観察 に記録。

### シナリオ D 結果
- 実施日: YYYY-MM-DD
- 環境: <Windows 11 + Claude MAX 20x | Windows 11 + Bedrock>
- 全体観察: グローバル + プロジェクト両方適用。階層 merge が成立するか (kit の最終形)
- シナリオ固有の補足: 同名 skill / agent の優先順位 (グローバル vs プロジェクト)、rule の追加 vs 上書き、model override

#### T1 (コミットメッセージ生成)
- 使用モデル (main agent): <Sonnet 4.5 / Haiku 4.5 / other>
- sub-agent 起動: <yes (どの agent) / no>  ※ どちらの階層の commit-msg が発火したか明記
- tool 利用: <Read, Edit, Bash, Task, etc. の回数>
- 応答時間: <X 秒>
- 解答 (full text):

  ```
  <Claude の応答をそのまま貼る>
  ```

- 品質評価: <Conventional Commits 形式? Y/N、scope 適切? Y/N、subject 50 文字以下? Y/N>
- input token: <N>
- output token: <M>
- 概算コスト: <$X> (環境別単価で計算、後述「コスト計算式」参照)

#### T2 (セキュリティチェック)
(T1 と同じ書式。階層 merge 時の leak-check 発火元を観察)

#### T3 (ADR 起票)
(T1 と同じ書式。階層 merge 時の propose-adr / architect 発火元を観察)

## `/clear` と session 再起動の使い分け

検証品質を保つため、シナリオ間および同一シナリオ内のテスト試行間で適切に context をリセットすること。

### 推奨タイミング

| タイミング | アクション | 理由 |
|---|---|---|
| シナリオ A → B 切替時 | **session 再起動必須** (`/quit` → 設定変更 → `claude` 再起動) | 設定ファイル新規読込のため |
| シナリオ B → C 切替時 | 同上 | 同 |
| シナリオ C → D 切替時 | 同上 | 同 |
| 同一シナリオ内 T1 → T2 → T3 | `/clear` で OK | 設定不変、context 汚染防止のみ |

### `/clear` の限界

- 会話履歴は消えるが、**設定ファイル (`~/.claude/CLAUDE.md` / `agents/*.md` / `skills/`) は再読み込みされない可能性**
- シナリオ間で `apply-claude-kit.ps1` で設定を変更した場合は **必ず session 再起動**

### 追加観察項目 (検証時に確認推奨)

「`/clear` 後と session 再起動後で同じ挙動か」をシナリオ B / D で観察:

- もし `/clear` だけで設定変更が反映 → 検証手順を簡略化可
- もし反映されない → 本番運用でも user に「設定変更後は session 再起動が必要」と明示する必要あり

具体的な observation 方法:

```powershell
# シナリオ B 完了後、設定を変更
# (例: ~/.claude/CLAUDE.md の応答スタイル指示を変更)
notepad "$env:USERPROFILE\.claude\CLAUDE.md"

# 方法 1: /clear のみ
# Claude session 内で /clear → 同じ session で再質問
# → 応答スタイル変更が反映されているか確認

# 方法 2: session 再起動
# /quit → claude → 再質問
# → 応答スタイル変更が確実に反映される
```

この観察結果は本書末尾の「結果記録」セクションに追記する (項目: "/clear vs 再起動の差")。

## 結果比較表 (実施後に記入)

| 項目 | A | B | C | D |
|---|---|---|---|---|
| CLAUDE.md 認識 | | | | |
| commit-msg sub-agent 発火 | | | | |
| leak-check skill 発火 | | | | |
| propose-adr skill 発火 | | | | |
| Haiku 委譲動作 | | | | |
| Sonnet 4.5 利用率 (推定 %) | | | | |
| Haiku 4.5 利用率 (推定 %) | | | | |
| 平均応答時間 (T1-T3 mean) | | | | |
| 総 input token (T1+T2+T3) | | | | |
| 総 output token (T1+T2+T3) | | | | |
| 推定総コスト (USD) | | | | |
| tool 呼出総数 (T1+T2+T3) | | | | |
| プロジェクト切替時の引き継ぎ | | | | |
| 階層 merge 動作 | n/a | n/a | n/a | |
| /clear vs session 再起動の差 | n/a | | n/a | |

## 計測方法と環境差分

5 軸 (使用モデル / 解答内容 / コスト / 応答時間 / tool 利用) の計測手順と、MAX 環境 / Bedrock 環境での差分。

### 1. 使用モデルの特定

Claude session 内で以下を質問:

```
あなたは今どのモデルで動作していますか?
sub-agent (Task tool) を呼び出した場合、その sub-agent はどのモデルで動作しますか?
```

応答内に `Sonnet 4.5` / `Haiku 4.5` が含まれるかを記録。

### 2. 解答内容

T1-T3 の Claude 応答を **そのまま貼り付け**。要約しない (シナリオ間の差を見逃さないため)。

### 3. コスト計算式

#### MAX 環境 (Claude MAX 20x)

- MAX は **flat-rate (定額)** のため per-session コストは直接算出不可
- 代替: token 数を測定し、Bedrock 環境での **理論コスト** を計算
- 計算式:

  ```
  Sonnet 4.5 cost (USD) = (input_tokens * 0.003 / 1000) + (output_tokens * 0.015 / 1000)
  Haiku 4.5 cost (USD)  = (input_tokens * 0.00080 / 1000) + (output_tokens * 0.004 / 1000)
  ```

  ※ 単価は近似値。最新は [Anthropic Pricing](https://www.anthropic.com/pricing) で確認

#### Bedrock 環境

- AWS Cost Explorer で per-token billing を直接観察
- Phase 3.2 で実装した `scripts/cost-observe-bedrock.ps1` で daily report 生成
- session 単位の細かいコストは Cost Explorer の Cost Allocation Tag (もし設定済なら) で集計

#### token 数の取得方法

- Claude Code の `/status` コマンド (もし表示されれば、最新 turn の token 数)
- もし `/status` で token が表示されない場合は、応答文字数で近似:
  - 概算: 1 token ≈ 4 文字 (英語) / 1 token ≈ 1 文字 (日本語) の混合で `total_chars / 2.5` 程度
- 厳密には Anthropic Console (MAX 環境) または AWS Bedrock model invocation log で確認

### 4. 応答時間

- 手動計測: stopwatch / 時計
- プログラマブル計測 (PowerShell):

  ```powershell
  Measure-Command {
      # claude のプロンプト入力時間は除外、Claude 応答開始から完了までを記録するのが理想
      # ただし claude CLI は対話形式のため Measure-Command で直接測定困難
      # 推奨: 質問送信時刻と回答完了時刻を手動記録、差分を秒数で記載
  }
  ```

- ストップウォッチで「Enter 押下 → 応答完了」までを計測する方が現実的

### 5. tool 利用

Claude Code は通常、応答内で「○○ tool を使います」と明示する。応答テキストから:

- `Read`, `Edit`, `Bash`, `Write`, `Task`, `Glob`, `Grep` 等の名前を抽出
- 各 tool の呼出回数を記録 (例: `Read: 3, Edit: 1, Bash: 2, Task: 1`)

sub-agent (Task tool) の呼出は特に重要 (ADR-0004 のルーティング検証の核心)。

### MAX vs Bedrock の計測差分まとめ

| 項目 | MAX | Bedrock |
|---|---|---|
| 使用モデル | 質問で確認 | 質問で確認 |
| 解答内容 | full text 記録 | full text 記録 |
| token 数 | `/status` or 文字数推定 | `/status` or Bedrock log で精確 |
| コスト | 理論値 (単価 × token) | 実費 (Cost Explorer) |
| 応答時間 | 手動計測 | 手動計測 |
| tool 利用 | 応答テキストから抽出 | 応答テキストから抽出 |

MAX 環境では「コストの絶対値」より「シナリオ間の token 数比較 (Haiku 委譲が起きたか)」が中心になる。

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
