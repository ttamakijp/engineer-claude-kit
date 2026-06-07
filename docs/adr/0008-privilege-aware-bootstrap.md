---
status: Accepted
date: 2026-06-08
deciders: [Tetsuya]
tags: [bootstrap, security, privilege, fail-fast, windows]
---

# ADR-0008: Bootstrap スクリプトは非管理者権限での実行を強制する (Administrator 検出で fail-fast)

> 本 ADR は P5 PR で起票され、同 PR で実装まで含めて Accepted とする。

## Context

engineer-claude-kit の entry スクリプト (`bootstrap.ps1` / `install-deps.ps1` / `apply-claude-kit.ps1`) はすべて **ユーザ権限**で完結する設計である:

- 書込み先は `$env:USERPROFILE\.claude\` 配下のみ
- PowerShell module install (PSScriptAnalyzer / Pester) は `-Scope CurrentUser` 強制
- system パス (`C:\Program Files`, `HKLM:`) は一切触らない

一方で、Windows ユーザは「インストール系スクリプト = 管理者権限で実行」という習慣から、これらを **管理者 PowerShell (Run as Administrator)** で起動しがちである。その場合に実害が出る:

- 管理者権限で `$env:USERPROFILE\.claude\` 配下を新規作成すると、生成されたディレクトリ/ファイルの owner が **Administrators** になる
- 以降、通常ユーザ権限で `claude` を起動したり再 apply したりすると、`~/.claude/` への書込みが **permission denied** になり、原因が分かりにくい事故になる
- 一度発生すると owner の付け替え (takeown / icacls) が必要で、初心者には復旧が困難

つまり「管理者で実行できてしまう」こと自体がフットガンであり、構造的に防ぎたい。これは ADR-0007 (settings.json hands-off) と同じく「kit は user 環境を壊さない」という方針の延長線上にある。

## Decision

entry スクリプトの冒頭で **elevation を検出し、管理者権限で起動されていたら即座に中止する (fail-fast)**。

### 1. 共通 helper `scripts/lib/privilege-check.ps1`

`Assert-NonElevated` 関数を提供する:

- `[Security.Principal.WindowsIdentity]::GetCurrent()` + `WindowsPrincipal.IsInRole(Administrator)` で管理者判定
- 管理者でなければ即 return (no-op)
- 管理者なら、理由と対処を表示して `exit 2`
- escape hatch として `-AllowElevated` switch を持ち、指定時は警告のみ出して続行
- **非 Windows PowerShell (Linux/macOS)** では WindowsIdentity API が `PlatformNotSupportedException` を投げるため、`$IsWindows` を間接 probe して非 Windows なら no-op (PS 5.1 には `$IsWindows` automatic variable が無いため `Get-Variable -Name IsWindows -ErrorAction SilentlyContinue` で判定し、変数が無ければ Windows PowerShell = Windows とみなす)
- 判定不能時 (例外) は user をブロックせず警告のみで続行
- ADR-0003 §C の ASCII only 規約に従い、メッセージは英語で記述

### 2. 適用範囲

| script | Assert-NonElevated | 理由 |
|---|---|---|
| `scripts/bootstrap.ps1` | あり | エントリポイント |
| `scripts/install-deps.ps1` | あり | profile / module install が elevation で不整合になる |
| `scripts/apply-claude-kit.ps1` | あり | bootstrap 経由でなく直接呼ばれることもある |
| `scripts/lint.ps1` / `scripts/build-rules.ps1` | なし | 開発専用、ユーザ環境を変更しない |

各 entry スクリプトには `[switch]$AllowElevated` を param block に追加し、`. (Join-Path (Join-Path $PSScriptRoot 'lib') 'privilege-check.ps1'); Assert-NonElevated -AllowElevated:$AllowElevated` で起動チェックする。`bootstrap.ps1` が内部で `apply-claude-kit.ps1` を呼ぶ際は `-AllowElevated` を伝播させる。

### 3. CI / テストとの整合

GitHub Actions の windows-latest runner は **elevated で動作**するため、既存の Pester テスト (bootstrap / apply / install-deps を直接起動) はそのままだと fail-fast で `exit 2` し落ちる。テスト側のスクリプト起動に `-AllowElevated` を付与して回避する。これは fail-fast 設計の自然な帰結 (自動化環境では escape hatch を使う) であり、設計の妥当性を損なわない。

## Alternatives considered

| 案 | 内容 | 採否 |
|---|---|---|
| **案 α (採用)** | fail-fast。管理者検出で `exit 2`、escape hatch = `-AllowElevated` | 採用。誤実行を確実に止めつつ、正当なユースケースには逃げ道を残す |
| 案 β | warn-continue。警告だけ出して続行 | 否決。最も起きやすい「気付かず管理者実行」を止められず、owner 事故が防げない |
| 案 γ | silent (検出するが何も表示せず続行) | 否決。user が問題に気付く機会すら奪い、デバッグ困難な事故を誘発する |
| 案 δ | 自動で非管理者プロセスを再起動 (de-elevate) | 否決。Windows での確実な de-elevation は複雑 (explorer 経由 / runas /trustlevel 等) で移植性・可読性が低く、初心者向け kit の設計目標に反する |

## Consequences

### 利点

- `~/.claude/` の owner permission 事故を構造的に防止
- 「ユーザ権限で動く」という設計意図がスクリプト挙動として明示される
- escape hatch (`-AllowElevated`) により、どうしても管理者実行が必要な特殊環境にも対応可能
- 非 Windows / 判定不能ケースで no-op のため、macOS / Linux PowerShell でも壊れない

### 欠点

- 管理者 PowerShell を常用している user には初回 `exit 2` が驚きになりうる (メッセージで対処を明示して緩和)
- CI / テストが escape hatch (`-AllowElevated`) に依存する (ADR で明文化して許容)

## Refs

- P5 PR (本 ADR の実装を含む)
- ADR-0003 (bootstrap design + ASCII only 規約 §C): helper も ASCII only で記述
- ADR-0007 (settings.json hands-off policy): 「kit は user 環境を壊さない」方針の一貫性
- 事故メカニズム: 管理者実行 → `~/.claude/` owner = Administrators → 通常ユーザ実行で permission denied
