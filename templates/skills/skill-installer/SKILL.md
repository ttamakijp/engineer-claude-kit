---
name: skill-installer
description: |
  Global skill を project にコピーする helper skill。
  /install-skill コマンドや project-skill-recommend rule から呼び出される。
---

# skill-installer

`~/.claude/skills/<name>/` を `<project>/.claude/skills/<name>/` にコピーし、metadata を記録する helper。

## 起動条件

- `/install-skill <name>` slash command から
- project-skill-recommend rule が user 承認後に内部呼出

## 動作

1. **入力**: skill name (例: `android-build`)
2. **source 解決**: `~/.claude/skills/<name>/` (Windows: `$env:USERPROFILE\.claude\skills\<name>\`)
3. **dest 解決**: project root + `.claude/skills/<name>/`
   - project root = `git rev-parse --show-toplevel` で取得
4. **存在確認**:
   - source が無い → エラー報告: 「Skill not found in global: <name>」
   - dest が既存 → user に確認: 「既に存在します。上書きしますか?」
5. **コピー**:
   - source dir を dest に再帰コピー (Copy-Item -Recurse)
   - SKILL.md と添付ファイル全て
6. **metadata 記録**:
   - dest dir に `.metadata.json` 書き込み:
     ```json
     {
       "copied_from": "global",
       "source_path": "<source absolute path>",
       "copied_at": "<ISO 8601>",
       "kit_version": "<git short hash>"
     }
     ```
7. **報告**:
   - 成功: 「✅ Skill installed: <dest path>」
   - 失敗: エラー詳細

## 制約

- project root が検出不能 (git repo 外) → エラー報告して中断
- 既存 .metadata.json は上書き OK (再 install を許容)
- file permission や ownership は環境依存、best-effort
