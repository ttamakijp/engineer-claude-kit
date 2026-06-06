---
status: Accepted
date: 2026-06-07
deciders: [Tetsuya]
tags: [commands, checkpoint, resume, ux]
---

# ADR-0005: `/checkpoint` `/resume` slash commands

> **昇格メモ**: 本 ADR は Proposed → Accepted に昇格済み。確定設計に基づき
> `templates/commands/checkpoint.md` / `templates/commands/resume.md` を同一 PR
> (Group B) で実装し、README §2.1 を ✅ Phase 3 化・§4 ADR Index に本 ADR を追記した。
> 下記 "Implementation plan" の各項目は本 PR で実施済み (残課題は "Open questions" 参照)。

## Context

Bedrock 環境 + Claude Code CLI で長時間タスクを進める際、session 内の context
を別 session に持ち越せない。日跨ぎ / 端末切替時に user が「どこまで作業したか」を
再構築するコストが高い。

この問題を解消するため、session 状態を markdown に保存する `/checkpoint` と、
保存済み markdown を読み込んで context に復元する `/resume` の 2 つの slash
command を kit (engineer-claude-kit) の配布対象に追加する。これは Group B の
設計判断であり、本 ADR でその確定済み設計を文書化する。

## Decision

確定済みの設計判断は以下 4 軸 (Q1-Q4)。

### A. 保存場所 (Q1) — project / global 両対応

- project root (`.git/` 存在) で起動した場合 → `<project>/.claude/checkpoints/`
- project 外で起動した場合 → `~/.claude/checkpoints/`
- 検出ロジック: `git rev-parse --show-toplevel` が成功すれば project mode、
  失敗すれば global mode とする。

### B. 保存内容 (Q2) — Claude 自動生成

- `/checkpoint` を引数なし単独で実行した場合、Claude が現在の session 状態を
  自動で要約する。
- 要約は **small-fast model (Haiku 4.5)** で実行し、コストを最小化する
  (ADR-0004 の auto model routing 方針に整合)。
- user が引数を付けた場合 (`/checkpoint "<本文>"`) は、手動本文を優先する。

### C. 復元方法 (Q3) — 一覧表示後に選択

- `/resume` 実行で `.claude/checkpoints/` 内の最近 5 件を番号付きで提示する。
- user が番号を選ぶと、該当 markdown を読み込み context に注入する。
- `/resume <slug>` でファイル名 (slug) を直接指定する経路もサポートする。

### D. markdown スキーマ (Q4) — frontmatter + 6 セクション固定

```markdown
---
session_id: <Dispatch session ID or null>
created_at: <ISO 8601 with timezone>
project_path: <absolute path or null>
title: <short kebab-case slug>
tags: [...]
---

## 目的 (要約 1-3 行)

## 直近の作業内容 (3-5 行)

## 触ったファイル
- <path>
- <path>

## 決定事項 / 設計判断

## 次のアクション

## 関連 commit / branch / PR
```

## Alternatives

採用しなかった候補と理由を以下に併記する。

| 案 | 採用しなかった理由 |
|---|---|
| Q1 (a) `~/.claude/checkpoints/` only | project 横断視点はあるが、project 文脈に紐付かない (project 切替時に曖昧) |
| Q1 (b) `<project>/.claude/checkpoints/` only | global session (Dispatch / Cowork でない CLI 直起動) が保存できない |
| Q2 (a) 全手動 | 楽だが low-friction でない (毎回本文を考える負荷) |
| Q2 (c) ハイブリッド | 高品質だが Claude 草案を user が編集する UX が重い |
| Q3 (a) 最新自動 | 「最新以外を呼びたい」需要に対応できない |
| Q3 (b) 引数指定のみ | 履歴を覚えていないとファイル名が分からない |

## Open questions

review で議論する論点 (本 draft 時点では未確定)。

- **rotation**: checkpoint file の古いものを自動削除するか。件数上限 / 期間上限を
  設けるか。
- **機密情報フィルタ**: secret / token 等を検出して checkpoint から除外する rule
  の要否。
- **複数端末間共有**: private repo に commit するか、cloud sync か、OneDrive 経由か。
- **session_id の null 許容**: Dispatch / Cowork 環境では `session_id` メタデータが
  取得できるが、CLI 直起動では取得できない。null をどこまで許容するか。

## Implementation plan

本 ADR が Accepted になった後の別 PR で実装する。本 PR の scope 外。

1. `templates/commands/checkpoint.md` 新規
   - frontmatter: `description: セッション state を保存`,
     `allowed-tools: Bash, Read, Write, Grep`
   - body: 要約 prompt + Haiku 4.5 routing 指示 + 保存場所解決ロジック
     (PowerShell snippet) + markdown 書込
2. `templates/commands/resume.md` 新規
   - frontmatter: `description: 前回 state から再開`, `allowed-tools: Bash, Read`
   - body: 保存場所列挙 → 最近 5 件提示 → user 選択受付 → 内容を context 注入
3. `templates/skills/checkpoint-helper/SKILL.md` (任意) — `/checkpoint` の補助 skill
4. `apply-claude-kit.ps1` の拡張は不要 (既存の `templates/commands/` 配布ループで
   そのまま配布できる)
5. `tests/apply-claude-kit.tests.ps1` で `checkpoint.md` / `resume.md` の配置を確認
6. README §2.1 で `commands/checkpoint.md` `commands/resume.md` `state/` を
   ✅ Phase 3 化

## Refs

- ADR-0001 (kit clean-start design)
- ADR-0004 (auto model routing: Haiku for summarization)
