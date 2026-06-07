---
status: Proposed
date: 2026-06-07
deciders: [Tetsuya]
tags: [settings, backend, hands-off, responsibility-separation]
---

# ADR (draft): Hands-off settings.json policy

> Note: This is a draft. Formal ID assignment, file rename, and README section 4 ADR Index update will happen at Accepted promotion in a separate PR.

## Context

実機検証 (2026-06-07) で以下の重大問題が判明:

- 現状 templates/settings.json は Bedrock 専用キーをハードコード (CLAUDE_CODE_USE_BEDROCK=1, AWS_REGION, ENABLE_PROMPT_CACHING_1H_BEDROCK=1, AWS_MAX_ATTEMPTS=2, Bedrock 形式 model ID)
- Anthropic API 直環境に apply すると、Claude Code が次回起動時に Bedrock 接続を試み、AWS credentials が無いため Could not load credentials from any providers エラーで起動不能
- user の既存 settings.json (例: theme, autoUpdatesChannel) も上書きで破壊される

加えて以下の本質的問題:

- Bedrock 接続設定や推奨 model ID は動的: AWS region、cache 仕様、新 model release で変わる
- settings.json は user environment config の領域: 個人 preference (theme) や機密 (API key) を含む
- これは CLAUDE.md / rules / agents / skills / commands (kit が ship する Claude Code 部品) とは責務の質が違う

## Decision

kit は ~/.claude/settings.json を生成・上書きしない (hands-off)

### 1. templates/settings.json を削除

apply 時の settings.json 配布ロジックを完全に除去。

### 2. 代わりに docs/setup/ に設定例を配置

- docs/setup/settings-bedrock.example.json: Bedrock 環境向け設定例 (Sonnet 4.5 + Haiku + 1h cache)
- docs/setup/settings-anthropic.example.json: Anthropic API 直向け設定例 (Sonnet 4.5 + Haiku)
- docs/setup/settings-setup.md: 選び方ガイド + 適用手順

user が手動で該当 example を ~/.claude/settings.json にコピー + 必要に応じて編集する。

### 3. apply-claude-kit.ps1 で hint メッセージ

apply 完了時に "settings.json は user 自身が設定してください。設定例は docs/setup/ を参照" と表示。既存 settings.json があるかどうかに関わらず、user に促すだけで触らない。

### 4. config/models.yaml の役割

- model ID は設定例の中で参照される定数として保持
- apply.ps1 から settings.json への参照は削除
- 将来 cost-observe-bedrock.ps1 等で参照する場合に残す

### 5. README / docs / Appendix A の更新

- §2.1 settings.json 行を削除
- §5 model strategy に kit は settings.json を提供しないを明記
- bootstrap-installation.md Appendix A の手順から settings.json 自動配布を削除、手動セットアップを追加

## Alternatives

| 案 | 採用しなかった理由 |
|---|---|
| 検出 + 動的生成 (旧 ADR-0007 案) | 検出ロジックに穴、merge バグ、既存設定破壊、信頼リスク。実機検証で実害発生 |
| Multiple template files | 結局選択 logic が必要、kit 領域外の責務 |
| User prompt during apply (interactive) | apply は非対話前提 (CI 互換)、対話混入 NG |
| Hybrid (model ID のみ書く) | model ID 形式が backend で違うので検出は必要、中途半端 |
| Skip-on-existing | 初回 install で Bedrock 強制になり不公平 |
| 空 {} fallback | 荒い workaround |

## Open questions

- 設定例の format: 両 backend で 1h cache (Bedrock 用) を強調して書くか、最小限に留めるか
- scripts/validate-settings.ps1 のような検証 helper を提供するか (model ID と CLAUDE_CODE_USE_BEDROCK の整合チェック等)
- bootstrap.ps1 で apply 後に「設定例を見る?」と聞く UI を入れるか (基本的に対話排除方針なので入れない方針か)
- docs/setup/ を templates/ 配下に移して apply で参考配置するか (user が直接コピーしやすい)

## Implementation plan

(Accepted 昇格後の別 PR で実施)

1. templates/settings.json を削除
2. scripts/apply-claude-kit.ps1 から settings.json 配布ロジック削除 + hint メッセージ追加
3. docs/setup/settings-bedrock.example.json 新規 (Bedrock 用設定)
4. docs/setup/settings-anthropic.example.json 新規 (Anthropic 用設定)
5. docs/setup/settings-setup.md 新規 (選び方 + 手順 + 注意点)
6. tests/apply-claude-kit.tests.ps1 から settings.json 関連 test を削除、hint メッセージの test を追加
7. README §2.1 (settings.json 行削除) / §5 (hands-off ポリシー明記) / §4 (ADR-0007 追加)
8. docs/manual-verification/bootstrap-installation.md Appendix A 更新
9. ADR-0007 を Proposed → Accepted、rename 0007-hands-off-settings.md

## Refs

- 直接の動機: 2026-06-07 実機検証で Could not load credentials from any providers エラー
- ADR-0001 (kit clean-start design): settings.json を最小構成として作った経緯、再評価
- ADR-0004 (auto model routing): model 選択は kit 領域だが、env への書込は user 領域
- 棄却した旧 ADR-0007 案 (検出 + 動的生成): 設計判断の経緯記録