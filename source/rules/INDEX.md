# Rules Index (Lazy Load)

毎ターン load は本ファイルのみ。詳細は Claude が必要時に Read で fetch する。

## Common Rules

| Rule | Path | Summary |
|------|------|---------|
| **commit-convention** | `common/commit-convention.md` | Conventional Commits + squash + delete-branch strategy |
| **security-mobile** | `common/security-mobile.md` | OWASP Mobile Top 10、API キー管理、PII 検出、supply chain hygiene |
| **file-granularity** | `common/file-granularity.md` | 1 file 300 行目安、500 行上限で責務分離 |
| **project-skill-recommend** | `common/project-skill-recommend.md` | Project type 自動検出、skill 自動推薦 |
| **work-end-reminder** | `common/work-end-reminder.md` | 終業リマインダ、marker file による初回質問 1 回化 |
| **bilingual-notation** | `common/bilingual-notation.md` | 英語混じり時の日本語併記（初出時のみ） |

## Android Rules

| Rule | Path | Summary |
|------|------|---------|
| **android-build-troubleshooting** | `android/build-troubleshooting.md` | Android build troubleshooting guide |

---

## 使用方法

Claude が以下の状況で各ルールを参照します：

- **commit-convention**: コミットメッセージ生成、PR 説明作成時
- **security-mobile**: 認証・暗号化・パーミッション実装時（Android）
- **file-granularity**: ファイルサイズ超過チェック

詳細は各 markdown ファイルを参照してください。
