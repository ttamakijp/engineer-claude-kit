---
name: usage-insights
description: |
  Claude Code の usage transcript を解析し、model 効率 / cache 効率 / token 浪費 /
  stuck パターン / Haiku 委譲率 / cost trend を insights として提示する skill。
  「usage insights」「効率分析」「コスト分析」「claude 使い方」等で起動。
---

# usage-insights

`~/.claude/projects/*.jsonl` (Claude Code transcript) を解析し、日常使いでは気づき
にくい非効率 (Opus 多用 / Haiku 委譲漏れ / cache cold miss / token 浪費 / stuck
session) を Markdown レポートにまとめる。`/insights` slash command と同一機能の
自然言語入口 (skill = 文脈検出入口、command = 明示実行)。ADR-0010 の責務分離に整合。

## 起動条件

ユーザが以下のいずれかを依頼・言及したとき:

- 「usage insights」「効率分析」「コスト分析」「claude の使い方を見たい」
- 「Opus 使いすぎ?」「Haiku に委譲できてる?」「cache 効率は?」「token 無駄?」
- 直近の session が stuck / 非効率だった振り返り

## 実行手順

1. Kit の script 位置を確認: `$env:USERPROFILE\.claude-kit\scripts\usage-insights.ps1`
2. 解析を実行 (既定 = 週次):
   - `pwsh <script> -Window Weekly`
   - pwsh 不在なら `powershell -NoProfile -File <script> -Window Weekly`
   - 日次が欲しい場合は `-Window Daily`
3. 出力された `~/.claude/insights/latest.md` を read
4. 冒頭の **Key findings** (3-5 行) を要約してユーザに提示し、必要なら全文の要点を補足
   - レポートは **技術メトリクス + 人間語併記** の二層構造。各 finding の直後に
     blockquote (`>`) で平易な対人類比が付く (例: Opus 偏重 →「簡単な作業は別の人に
     振ると速くて安い」)。ユーザ提示時は **数値 (事実) と blockquote (意味) の両方**
     を読み上げ、技術値だけ・人間語だけに偏らせない
5. ユーザが最適化に関心を示したら、レポートを踏まえた具体策 (model 振り分け / cache
   維持 / Haiku 委譲 / 短 turn の集約) を対話的に提案

## 出力の読み方

- **Est. cost**: `scripts/pricing.psd1` の概算 (web 確認待ち、**相対比較用**)
- **Haiku delegation**: 低いほど委譲余地あり (軽作業を Haiku へ)
- **Cache cold-read share**: 高いほど cache miss が多い (turn 間隔の空きすぎ)
- **Token-waste score**: 高出力 turn の割合 (議論偏重の目安、heuristic)
- **Stuck candidates**: median + 3 sigma を超える turn 間 gap
- **blockquote (`>`)**: 各 finding の人間語併記。技術値の置換ではなく補足
  (日本語原文は `scripts/lib/plain-language-hints.json`、ASCII-only の script からは
  `Read-Utf8NoBom` 経由で読む。ADR-0014)

## Rule firing metrics (ADR-0015)

CLAUDE.md / rule が要求する行動が実際に起きたかの近似指標。削減の可否を
**baseline との差分**で判断するための計測で、絶対値は参考値として読む。

- **plan-first**: ユーザ prompt 直後の論理ターンで、最初の tool 呼出より前に
  text block があるか (CLAUDE.md §2「実装前に 1 行の修正方針」)
- **haiku-delegation**: `git commit` 呼出と大きな tool 出力に対し
  `commit-msg` / `lint-helper` / `log-summary` へ委譲したか (CLAUDE.md §3.1)
- **commit-convention**: commit subject が Conventional Commits 形式か
- `-WriteBaseline` で `~/.claude/insights/rule-metrics-baseline.json` に保存。
  以降のレポートは各値に baseline からの差分 (pt) を併記する
- **「not exercised」は削除根拠にならない** (該当イベントが無かっただけ)

論理ターンは transcript の `requestId` で復元する。assistant message は
content block ごとに 1 行として記録されるため、行単位で数えるとターン数が
約 1.8 倍に膨らむ。

## 制約

- pricing は概算。billing 照合には使わない (相対 insight 専用)
- 解析対象は `~/.claude/projects/` のみ (Dispatch transcript は scope 外)
- 書込先は `~/.claude/insights/` のみ。外部送信なし
- 自動生成は scheduled-task (daily / weekly) が担う。skill は on-demand 入口

## Refs

- ADR-0014 (usage insights)
- ADR-0015 (rule firing metrics / 指示面の削減)
- ADR-0010 (skill / command 責務分離)
- ADR-0012 (statusLine context awareness、補完的 visualization)
