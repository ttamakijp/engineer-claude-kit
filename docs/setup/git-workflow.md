# Git workflow リファレンス

PR フロー / TDD サイクル / Stacked PR / コミットメッセージ例。

> この文書は `~/.claude/rules/commit-convention.md` から分離した**読み物**です
> (ADR-0015 §B-2)。rule 本文には要件と Do / Don't だけを残し、手順と例はここに置いて
> います。Claude は必要なときにこのファイルを `Read` すれば足ります。
> `@import` では繋いでいません — import したファイルも launch 時にロードされるため、
> context 削減の効果がゼロになります (ADR-0015 事実 3)。

## PR フロー: 設計先行 → draft PR パターン

1. `docs/design/<feature>.md` または `docs/adr/NNNN-*.md` に設計提案を commit (実装なし)
2. draft PR を作成し、設計レビューを受ける
3. 設計承認後、同ブランチで実装をコミット
4. 実装完了で PR を ready for review に切り替える
5. コードレビュー → squash マージ → delete-branch

設計先行 draft PR は実装後の手戻りを激減させ、レビュアーが文脈を持った状態で
コードレビューできる状態を作ります。

## TDD サイクル

1. テストを書く (**RED**: 失敗を確認)
2. 最小実装で通す (**GREEN**: テスト通過を確認)
3. ビルド確認 (コンパイルエラー・lint エラーがないこと)
4. コミット
5. push → CI 通過を確認

- RED を確認せずに実装しない (最初から通る = テストが機能していない)
- GREEN にしてからリファクタリング。リファクタ後に再度 GREEN を確認してからコミット

## Stacked PR の落とし穴と回避

依存関係のある PR を積む場合 (PR-A → PR-B → PR-C):

- 前 PR をマージ + branch 削除すると後続 PR が **自動クローズされる** (GitHub 仕様)
- 対処: 自動クローズされた後続 PR は新規 PR で再作成する。元 PR はクローズのまま
- ベストプラクティス: 各 PR は main から独立ブランチを切り、依存変更は `git rebase` で
  取り込む
- 依存チェーンは最大 2 段。3 段以上になる場合はフェーズ設計を見直す

```bash
# 後続ブランチを main ベースに切り直す
git checkout main && git pull
git checkout -b feat/next-feature
git cherry-pick <commits-from-prev-feature>
```

## コミットメッセージ例

```
feat(auth): OAuth 2.0 PKCE フローを追加

リフレッシュトークンを Android Keystore に保存し、長期セッションのセキュリティを向上。
アクセストークンは EncryptedSharedPreferences に格納。

Refs: a1b2c3d4
```

```
fix(network): TLS handshake 失敗時の再試行回数を 1 回に制限

無限再試行で発生していたバッテリードレインを回避。
5xx 系のみ再試行し、4xx は即時失敗。

Refs: e5f6g7h8
```

## footer の `Refs:` に何を書くか

**commit SHA (7-12 文字 short) / ADR-NNNN / tag (`vX.Y.Z`)** を使います。

`#NN` は GitHub-native の counter で、リポジトリ再作成や org 移行で壊れるため本体参照
には使いません。`Refs:` を SHA / ADR / tag に揃えておけば、リポジトリ削除・再作成・
org 移行のいずれを経ても参照が壊れません。

GitHub の `Closes #N` / `Fixes #N` / `Resolves #N` auto-close keyword は GitHub-native
機能なので例外として併用可です (リポ再作成で auto-close 効果が失われる点は許容)。

> この参照スタイル (durable-references) は engineer-claude-kit では未採番です
> (TBD, Phase 1 で整備予定)。

## 根拠

- Conventional Commits は changelog 自動生成と semantic versioning 判定の前提
- squash + delete-branch は履歴を線形に保ち、`git bisect` を機械的に走らせやすくする

## 関連

- `~/.claude/rules/commit-convention.md` — 要件と Do / Don't (常時ロードされる本文)
- `CONTRIBUTING.md` — 本リポジトリの hard rules とテスト手順
- ADR-0015 — 指示面の削減と、この分離の方針
