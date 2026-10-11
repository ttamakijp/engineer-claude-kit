# rule 遵守率 snapshot の取得手順

ADR-0015 の 4 点比較 (配布前 / ノイズ対照 / 配布後 / 削減後) を成立させるための運用手順。

## 専用スクリプトは不要

調査の結論として `scripts/take-snapshot.ps1` は**作りません**。snapshot 取得は既存の
1 コマンドで完結します。

```powershell
powershell -NoProfile -File scripts/usage-insights.ps1 -Window Weekly -WriteBaseline
```

このコマンドが行うこと:

1. `~/.claude/projects/**/*.jsonl` を直近 7 日ぶん走査 (`Get-InsightsScope -IncludeRuleMetrics`)
2. 論理ターンを `requestId` で復元し、3 指標を集計 (`Get-RuleMetrics`)
3. `~/.claude/insights/<date>-weekly.md` と `latest.md` にレポートを出力
4. `~/.claude/insights/rule-metrics-baseline.json` を比較対象として上書き
5. `~/.claude/insights/rule-metrics-baseline-<YYYY-MM-DD>.json` を archive として保存

5 が 4 点比較の肝です。単一ファイル上書きでは過去の snapshot が失われるため、
ADR-0015 Step 3 で archive を追加しました。同日の再実行はその日の archive を
置き換えるので、1 日 1 エントリに収まります。

## snapshot 2' の判定基準

**7 日 window が完全に apply 後に収まっていること。**

`~/.claude/.engineer-claude-kit-applied` の `applied_at` が rules の配布時刻です。
window はコマンド実行時刻から 7 日さかのぼるため、

```
取得時刻 - 7 日 >= applied_at
```

を満たすまで待ちます。これを満たさない時点で取得すると、配布前のセッションが
混入した「混在データ」になります。実例として snapshot 2 (2026-10-07 21:00 頃取得、
apply は同日 20:32) は meta 行の **86.5% が配布前**でした。

現在の配布時刻は `2026-10-07T20:32:15+09:00` なので、snapshot 2' の取得可能時刻は
**2026-10-14 20:32 JST 以降**です。

### window の内訳を自分で確認する

混在していないかは、dot-source して時刻で分割すれば確かめられます。

```powershell
. .\scripts\usage-insights.ps1
$applyUtc = [datetime]::Parse('2026-10-07T11:32:15Z')
$rows = Get-InsightsScope -WindowDays 7 -IncludeRuleMetrics
$meta = @($rows | Where-Object { $_.Role -eq 'meta' })
$pre  = @($meta | Where-Object { $_.Timestamp -lt $applyUtc }).Count
"配布前 $pre / 全体 $($meta.Count)"
```

`配布前` が 0 であれば clean な measurement です。

## 取得前の確認 (dry-run 相当)

`usage-insights.ps1` に `-DryRun` はありません。baseline を書かずに数値だけ見たい
場合は `-WriteBaseline` を外して実行します。レポートは生成されますが baseline と
archive は触りません。

```powershell
powershell -NoProfile -File scripts/usage-insights.ps1 -Window Weekly
```

既存 baseline を一切触らずに確認したいだけなら `-OutputDir` を一時ディレクトリに
向けます。

```powershell
powershell -NoProfile -File scripts/usage-insights.ps1 -Window Weekly -OutputDir $env:TEMP\snapshot-check
```

> `-DryRun` スイッチ自体の追加は提案として
> `docs/step-6-items/` に回しています (本番の baseline を守る明示的な意図表示に
> なるため)。実装は user の指示待ちです。

## lib の責務分担 (重複なしを確認済)

| ファイル | 公開関数 |
|---|---|
| `scripts/usage-insights.ps1` | `Get-ModelFamily` / `Import-Pricing` / `Get-InsightsScope` / `Get-UsageMetrics` / `Get-Median` / `Get-CostTrend` / `Write-InsightsReport` / `Invoke-UsageInsights` |
| `scripts/lib/rule-metrics.ps1` | `Get-CommitSubject` / `Get-RuleMetrics` / `Get-RuleRate` / `Get-RuleVerdict` / `Format-RuleMetricsSection` / `Read-RuleMetricsBaseline` / `Write-RuleMetricsBaseline` / `New-RuleMetricsRow` |
| `scripts/lib/insights-report.ps1` | `Format-InsightsReport` |

**17 関数すべて名前が一意で、機能の重複はありません。** 収集 (`usage-insights.ps1`)、
rule 指標 (`rule-metrics.ps1`)、描画 (`insights-report.ps1`) で責務が分かれています。
分割の理由は kit 自身の file-granularity 500 行上限です (ADR-0015)。

## 取得後にやること

1. `~/.claude/insights/rule-metrics-baseline-<date>.json` が生成されたことを確認
2. 数値を ADR-0015 §A の snapshot 表に追記する (ファイルより永続的で review 可能)
3. snapshot 2' の場合はここで初めて `apply-claude-kit.ps1 -Global` を実行し、
   PR #82 / #83 の削減版 rule を配布する
4. その 7 日後に snapshot 3 を取得する

## 関連

- ADR-0015 §A (snapshot の記録) / §E (指標の定義)
- ADR-0014 (usage insights の基盤)
- `templates/commands/insights.md` — `/insights --write-baseline`
