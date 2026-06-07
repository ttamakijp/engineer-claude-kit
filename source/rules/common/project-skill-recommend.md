---
id: project-skill-recommend
title: Project type 検出と skill 推薦 (Group F)
description: Project に入ったとき、type を検出して global skill ライブラリから関連 skill を推薦する
audience: [claude]
priority: medium
applyTo:
  default: "**"
tags: [project-detection, skill-recommendation, hospitality]
---

# 要件

ユーザが project に入って Claude session を始めたとき、project type を検出し、`config/recommended-skills.yaml` から関連 skill を推薦する。user が承認したら `/install-skill <name>` で自動 install。

## 動作

### 初回判定

session の初回ターンで以下を確認:

1. `<project>/.claude/.skill-recommendations-dismissed` marker file が存在するか
   - **存在** → 既に推薦済 (or user 拒否済)、本 rule は silent
   - **不在** → 初回、以下に進む

2. project root を `git rev-parse --show-toplevel` で取得
   - 失敗 (project 外) → rule 不発火、silent

### Project type 検出

`~/.claude/config/recommended-skills.yaml` (またはコピー元の `<kit>/config/recommended-skills.yaml`) を読込:

各 project type の `detect` リストにある file pattern を project root で Glob:

```bash
ls gradlew 2>/dev/null               # android
ls package.json 2>/dev/null          # web-node
ls requirements.txt pyproject.toml 2>/dev/null   # python
```

複数 type が hit する場合 (例: web-node + python の hybrid) は **全 type を recommend**。

### 推薦

検出した project type の `recommend` リストを取得。空 list なら何もしない。

それぞれの skill について:
- `<project>/.claude/skills/<name>/` が既に存在 → 既 install、推薦しない
- `~/.claude/skills/<name>/` が存在 → 推薦する

### 推薦メッセージ

応答冒頭に追加:

```
このプロジェクトは <project type> (例: Android プロジェクト) のようです。
以下の skill (技能) を install することを推奨します:

- `android-build` — Android のビルド・ADB 操作を支援

install する場合: `/install-skill android-build` を実行してください。
推薦を止める場合: 「推薦不要」と回答 → marker を保存し以降は silent
```

### user 応答処理

- user が `/install-skill <name>` を実行 → install 完了 (skill-installer が処理)
- user が「推薦不要」「dismiss」と回答 → `<project>/.claude/.skill-recommendations-dismissed` に書き込み、以降の session で silent
- user が何も言わずに別話題に移った → 次の session で再度推薦 (押し付けない、1 session 1 回)

## Do

- 初回のみ推薦、押し付けない
- skill 既 install 済はスキップ
- 複数 type を寛容に扱う (hybrid project 対応)
- `recommend: []` (空) の project type は silent
- marker file 保存で「もう聞かないで」を尊重

## Don't

- 毎ターン推薦を繰り返さない (1 session 1 回)
- skill 存在確認なしで推薦しない (`~/.claude/skills/<name>/` が無ければ推薦不可)
- project root 外で発火しない
- user 拒否後に再質問しない

## 根拠

- ホスピタリティ機能 (hospitality = おもてなし): user が skill の存在を覚えなくていい
- 「コマンド意識ゼロ」の体験を実現
- global = library、project = active set という mental model を補強

## 例外

- 開発中・実験中の project (git repo でない) → 検出スキップ
- recommend が全て既 install → silent
