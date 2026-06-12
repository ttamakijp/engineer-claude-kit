---
status: Accepted
date: 2026-06-08
deciders: [Tetsuya]
tags: [settings, wizard, opt-in, deep-merge, ux, hands-off]
---

# ADR-0010: Interactive settings wizard for opt-in deep merge

> 本 ADR は P11 PR で起票され、同 PR で実装まで含めて Accepted とする。

## Context

ADR-0007 で `~/.claude/settings.json` の hands-off ポリシーを採用した (kit は明示承認なく settings.json を生成・上書きしない)。これは Bedrock 専用キーのハードコードや既存設定破壊といった実害を踏まえた正しい判断だった。

一方で、初期セットアップで user が `statusLine` や `ANTHROPIC_SMALL_FAST_MODEL` を docs/setup/ の example から手動コピー + 編集する UX 摩擦は大きい。特に Haiku 委譲 (ADR-0004) を有効化する `ANTHROPIC_SMALL_FAST_MODEL` は backend (Bedrock / Anthropic API 直) で形式が異なり、手動設定の敷居が高い。

ADR-0007 の根本理念は「**明示承認なく書き換えない**」であって「一切触らない」ではない。明示的な Y/N 承認を経た opt-in な merge であれば、hands-off の理念と整合する。

## Decision

`scripts/setup-wizard.ps1` を新規追加し、`bootstrap.ps1` 末尾と `apply-claude-kit.ps1 -Global` 末尾 (ADR-0007 hint 表示後) で呼び出す。

- **インタラクティブ確認必須**: 項目ごとに Y/N で個別承認。default は項目ごとに異なる — statusLine と Bedrock 検出時の model 追加は **default = Y** (Enter で追加)、backend 選択 (非 Bedrock 時の `[1/2/s]`) は **default = s (Skip)** (G6j 以降、後述)。
- **deep merge のみ**: 既存 keys は決して上書きしない。欠落 keys のみ追加する (`Merge-Hashtable` の semantic)。ネストした hashtable は再帰 merge し、欠落したネスト key のみ補う。
- **backup 必須**: 変更前に `settings.json.bak-<timestamp>` を作成する。
- **非対話モード skip**: `-NonInteractive` / `$env:CI` / `[Environment]::UserInteractive = false` のいずれかで skip。これにより従来の非対話 (CI / scripted) 挙動は不変。
- **opt-out 可**: `-NoSettingsWizard` switch で完全 skip。
- **DryRun skip**: `-DryRun` は変更を伴わないプレビューなので wizard も skip する。
- **二重起動の回避**: `bootstrap.ps1` は内部の `apply -Global` 呼出に `-NoSettingsWizard` を渡し、wizard は bootstrap 末尾で 1 回だけ実行する。直接 `apply-claude-kit.ps1 -Global` を叩いた場合は apply 側で 1 回実行される。
- **encoding 厳守**: P6 / ADR-0003 §C 準拠 (UTF-8 no BOM、encoding-helper 経由)、ASCII only、PS 5.1 互換 (`-AsHashtable` 不使用、PSCustomObject -> Hashtable は自前の再帰変換)。
- **model ID 形式**: Bedrock は `us.anthropic.claude-haiku-4-5-20251001-v1:0`、Anthropic API 直は `claude-haiku-4-5-20251001`。`$env:CLAUDE_CODE_USE_BEDROCK=1` を検出して default を出し分ける。

### ANTHROPIC_SMALL_FAST_MODEL の default は Skip (G6j)

backend 選択 (Bedrock / Anthropic API / Skip) のうち、**default は Skip**。理由:

- Enter 押下で Bedrock を勝手に書き込むと、Bedrock 環境を持たない user が AWS credential エラー等で困る
- ADR-0007 hands-off と ADR-0010 wizard の「明示 opt-in」原則に整合
- user が意識的に backend を選んだ時だけ書き込まれる方が hands-off 精神に近い
- 後で wizard を再実行すれば opt-in 可能 (損失なし)

### non-interactive context の auto-skip (G6k)

apply-claude-kit.ps1 が **background process として呼ばれる** (Claude Code の
slash command 経由、CI、subprocess) ケースを auto-detect し wizard を自動 skip。

- 検出: `[Console]::IsInputRedirected` または `-not [Environment]::UserInteractive`
- 動作: hint 表示のみ、settings 変更なし
- 明示 opt-out: 従来通り `-NoSettingsWizard` も動作

これにより `/apply` 等で詰まらず、対話 terminal でのみ wizard を起動。

実装上、`Test-IsInteractive` の判定シグナル (`Test-CiEnvironment` /
`Test-HostUserInteractive` / `Test-StdinRedirected`) を個別関数に分離し、
静的プロパティ `[Console]::IsInputRedirected` を Pester v3.4 で mock 可能にした。

## Alternatives considered

| 案 | 内容 | 採否 |
|---|---|---|
| 自動上書き | 検出して無確認で書込 | 否決。ADR-0007 と衝突、実機で実害発生済 |
| 完全手動 (現状維持) | docs/setup/ からの手動コピーのみ | 否決。UX 摩擦が大きく、user 要望で改善対象に |
| 非対話 init コマンド (`-InitSettings` 等) | scripted setup 向けの非対話書込 | 保留。scripted setup 用に将来別途検討の余地あり。wizard と併用可だが本 ADR の scope 外 (Open questions 参照) |

## Consequences

### 利点

- 初回 install 直後に statusLine / Haiku 委譲を最小操作 (Enter 連打) で有効化でき、UX 摩擦が大幅に減る。
- deep merge + 既存 key 不可侵 + backup により、ADR-0007 が懸念した既存設定破壊リスクを構造的に排除。
- 非対話・DryRun・opt-out の三重 skip で、CI / scripted 経路の既存挙動は完全に不変。

### 欠点 / 留意

- 対話 prompt が増えるため、初回 install の手順がわずかに長くなる (ただし Enter / N で即時 skip 可能)。
- wizard の対話部分は Pester で直接検証しにくいため、テストは純粋 helper (deep merge / round-trip) と非対話 skip guard に限定する。

## Refs

- ADR-0007 (settings.json hands-off policy): 本 ADR はその例外を明文化する更新を伴う
- ADR-0004 (auto model routing): `ANTHROPIC_SMALL_FAST_MODEL` による Haiku 委譲
- ADR-0003 §C (encoding & PS 5.1 compatibility / ASCII only)
- P6 / ADR-0003 §C: UTF-8 (no BOM) helper 経由書込

## Open questions

- `-InitSettings` のような非対話 init 経路を別途提供するか (scripted setup 用)。本 ADR では scope 外とし、需要が出れば別 Issue / ADR で検討する。
- 追加候補となる settings キー (permissions / hooks 等) を wizard の対象に含めるか。現状は statusLine / ANTHROPIC_SMALL_FAST_MODEL の 2 項目に限定する。
