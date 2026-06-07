---
description: Global skill を project にインストール (~/.claude/skills/<name>/ → <project>/.claude/skills/<name>/)
allowed-tools: Bash, Read, Write, Glob
argument-hint: "<skill-name> (例: android-build, web-test, python-test)"
---

# /install-skill

Global skill ライブラリ (`~/.claude/skills/`) から指定 skill を現在の project に コピーする。

## 動作

1. `$ARGUMENTS` から skill name を取得 (必須、空ならエラー)
2. **skill-installer skill を起動** (上記の手順を実行)
3. 結果を user に報告

## 使用例

```
/install-skill android-build
/install-skill web-test
/install-skill python-test
```

## エラー時

- 引数なし → 「使い方: `/install-skill <skill-name>`」を表示
- skill 不在 → 利用可能な skill 一覧を表示
- project root 不明 → 「git repo 内で実行してください」と促す

## Refs

- skill-installer skill
- project-skill-recommend rule (自動推薦)
