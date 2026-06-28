# Android 多言語対応の標準ルール

## 1. 基本原則

- デフォルト言語は常に **English**
- 対応言語は **ユーザーベース（ビジネス・実装規模）** に基づいて決定
- 「トルコ語も」という際限なき要望を避けるため、**Tier 制** で管理
- 配布担当者でも簡単に言語追加できる仕組みを用意

## 2. 言語選定ガイド（Tier 制）

### Tier 1: 必須言語
- English のみ
- すべてのプロジェクトで対応

### Tier 2: 推奨言語（デフォルト）
- プロジェクトのユーザーベース（主要市場・主開発者の地域）
- 例: PALM は日本語・簡体中文

### Tier 3: オプション言語
- 将来の拡張候補
- 実装量と市場価値を勘案して判断

### 言語選定の客観基準
- **経度**：UI メニューの並び順を地政学的にフェア化
  - 西から東へ (例: es → en → ja → zh-CN)
- **話者数**：参考情報（決定基準ではない）

## 3. デフォルト言語戦略

### 起動時の言語初期化

```
端末 Locale 取得
  ↓
対応言語にマップ可能？
  ├─ YES → その言語で初期化
  └─ NO → English にフォールバック
```

### UI メニュー表示順
1. creator_priority_language（開発者指定、最優先）
2. Tier 1, 2, 3 の言語（経度 ASC）

例（PALM）:
```
- 🇯🇵 日本語 ⭐ (creator priority)
- 🇬🇧 English (tier1)
- 🇨🇳 简体中文 (tier2)
```

## 4. UI 設計ガイドライン

### ❌ 避けるべき設計
- 言語設定が深い階層（Settings > General > Localization）
- 言語名すべて英語表記
- 長押しメニューなど hidden gesture に依存

### ✅ 推奨設計
- ホーム / メインメニューに言語切り替え**ボタンを配置**
- 言語ダイアログに国旗を表示（視覚的識別）
- シンプルなモーダル選択

## 5. 配布担当者向け機能

### 「アプリ内言語追加」の UI/UX

**ユースケース**
```
開発者が PALM APK をビルド
  ↓
配布担当者が「新しい言語を追加」機能で翻訳
  ↓
その状態で配布担当者が現地ユーザーに配布
```

**フロー**

1. 「新しい言語を追加」ボタンをタップ
2. 言語選択（フラットなリスト、Tier 表示なし）:
   ```
   - 🇬🇧 English
   - 🇯🇵 日本語
   - 🇨🇳 简体中文
   - 🇪🇸 Español
   - 🇷🇺 Русский
   - 🇹🇭 ภาษาไทย
   ```

3. 言語を選択（例: Español）
4. 英語の全テキストがコピーされる
5. 翻訳編集画面:
   - 検索機能で値をフィルタ
   - 値ごとに上書き可能
   - English の値は参考表示（読み取り専用）
   
   ```
   ┌──────────────────────────┐
   │ Español を編集           │
   │ 検索: [ __________ ]     │
   ├──────────────────────────┤
   │ Back                     │
   │  English: Back           │
   │  Español: [Atrás ___]    │
   │                          │
   │ Collecting sensor data   │
   │  English: Collecting...  │
   │  Español: [Recopilando..]│
   │                          │
   │ notification_title       │
   │  English: PAL for...     │
   │  Español: [PAL para...___]
   └──────────────────────────┘
   ```

6. [保存] → 言語が追加完了

### 言語コードの自動化
- ユーザーに言語コード入力させない
- 言語マッピング表から自動取得

## 6. AI 自動化（言語追加・削除）

### 前提: マスター言語リスト

engineer-claude-kit に `config/i18n-languages.yaml` を配置:

```yaml
languages_master:
  en:
    name: English
    name_native: English
    bcp47: en
    values_dir: (root)
    longitude: -74
    tier: 1
    
  ja:
    name: Japanese
    name_native: 日本語
    bcp47: ja
    values_dir: values-ja
    longitude: 139
    tier: 2
    
  zh-CN:
    name: Chinese (Simplified)
    name_native: 简体中文
    bcp47: zh-CN
    values_dir: values-zh-rCN
    longitude: 116
    tier: 2
    
  es:
    name: Spanish
    name_native: Español
    bcp47: es
    values_dir: values-es
    longitude: -3
    tier: 3
  
  ru:
    name: Russian
    name_native: Русский
    bcp47: ru
    values_dir: values-ru
    longitude: 37
    tier: 3
    
  th:
    name: Thai
    name_native: ภาษาไทย
    bcp47: th
    values_dir: values-th
    longitude: 101
    tier: 3
```

### AI が言語追加する方法

ユーザーが「Español を追加してください」と言ったら、AI は:

1. `~/.claude-kit/config/i18n-languages.yaml` から言語情報を取得
2. `.claude/i18n-config.yaml` に追加（Tier ごとにソート、経度で並べ替え）
3. `app/src/main/res/values-es/strings.xml` を生成（English から複製）
4. `regen_columns.py` を実行
5. git add, commit

実装:
```bash
python3 scripts/add-language.py add es
python3 regen_columns.py
git add .
git commit -m "feat(i18n): Add Spanish (es) language"
```

### AI が言語削除する方法

ユーザーが「Español を削除してください」と言ったら、AI は:

1. `.claude/i18n-config.yaml` から削除
2. `app/src/main/res/values-es/` ディレクトリを削除
3. `regen_columns.py` を実行
4. git add, commit

実装:
```bash
python3 scripts/remove-language.py remove es
python3 regen_columns.py
git add .
git commit -m "feat(i18n): Remove Spanish (es) language"
```

## 7. 実装チェックリスト

- [ ] `.claude/i18n-config.yaml` を作成（対応言語・Tier 定義）
- [ ] `app/src/main/res/values-xx/` ディレクトリ作成・strings.xml 配置
- [ ] `regen_columns.py` で `string_columns.json` 生成
- [ ] `Application.onCreate()` で端末 Locale 追従初期化
- [ ] 言語メニューをホーム / 設定トップレベルに配置
- [ ] 「言語追加」機能を `StringOverridesActivity` に実装
- [ ] 非対応言語 → English フォールバックをテスト
- [ ] 再起動後に言語設定が記憶されることをテスト
- [ ] CI で `regen_columns.py` 自動実行を組み込み

## 8. PALM での実装例

`.claude/i18n-config.yaml`:
```yaml
i18n:
  creator_priority_language: ja
  creator_mandatory_languages:
    - ja
    - en
  default_runtime_language: en
  languages:
    tier1:
      - id: en
        name: English
        longitude: -74
    tier2:
      - id: ja
        name: 日本語
        longitude: 139
      - id: zh-CN
        name: 简体中文
        longitude: 116
    tier3: []
```

実装ファイル:
- `app/src/main/res/values/strings.xml` (English)
- `app/src/main/res/values-ja/strings.xml` (日本語)
- `app/src/main/res/values-zh-rCN/strings.xml` (簡体中文)
