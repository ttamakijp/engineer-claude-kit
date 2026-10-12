---
id: commit-convention
audience: [claude]
# paths なし = 無条件ロード。commit / PR 操作は扱うファイル種別に依存しないため。
---

# Commit and PR convention

## 要件

- コミットメッセージは Conventional Commits + 日本語本文で記述する
- 全変更は feature/fix ブランチ → PR 経由でマージする（main/master への直接 push 禁止）
- 1 Phase = 1 PR を原則とし、レビュー・ロールバック単位を小さく保つ
- マージ方式は **squash + delete-branch** を標準とし、squash message は `PR_TITLE` +
  `PR_BODY` を使う (GitHub default の `(#NN)` 自動付与は無効化)

## Conventional Commits フォーマット

```
<type>(<scope>): <subject>

<body — 日本語可、why を中心に>

<footer — BREAKING CHANGE / Refs / Co-Authored-By>
```

- **type**: `feat` 新機能 / `fix` バグ修正 / `docs` 文書のみ / `refactor` 機能変更なし /
  `test` テスト / `chore` 雑務 / `perf` 性能 / `style` 見た目のみ / `ci` CI 設定
- **scope**: 影響範囲を kebab-case 1 単語 (例 `auth`, `network`)。不要なら省略可
- **subject**: 50 文字以下、命令形、ピリオドなし。日本語可

## Do

- 1 commit = 1 論理変更。複数論点を 1 commit に混ぜない
- commit body には **why**（理由・トレードオフ）を書く。what は diff で十分
- PR には「変更概要 / 動機 / テスト方法 / スクリーンショット（UI 変更時）」を含める
- 設計判断を伴う変更は ADR を先行 draft PR として出し、LGTM 後に同ブランチで実装を追記する
- squash マージ時の commit message を整形し、Conventional Commits 形式に揃える
- マージ後はブランチを delete する（GitHub `--delete-branch` または UI のチェック）

## Don't

- `git push --force` を共有ブランチ（main / 他人のレビュー中ブランチ）に対して使わない
- main/master 直接 push をしない
- 「あとで修正」「WIP」commit を squash せずにマージしない
- 後続 PR の base を前の PR ブランチに設定しない（前 PR が delete-branch されると後続 PR が自動クローズされる）
- 依存チェーンを 3 段以上にしない（最大 2 段、それ以上はフェーズ設計を見直す）

## 例外

- ホットフィックスでは type を `fix` 固定、scope を `urgent` とし、ADR 不要
- リバートコミットは `revert: <reverted commit message>` 形式で自動生成された文面をそのまま使ってよい
- GitHub UI 上の `Closes #N` / `Fixes #N` / `Resolves #N` auto-close keyword は GitHub-native 機能のため `#NN` 記法を使う (リポ再作成で auto-close 効果は失われる点は許容)

## 関連

PR フロー / TDD サイクル / Stacked PR の回避 / コミットメッセージ例 / `Refs:` の
書き方は `docs/setup/git-workflow.md` を必要時に読むこと。
