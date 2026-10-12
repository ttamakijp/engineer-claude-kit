---
id: security-mobile
audience: [claude]
paths:
  - "**/*.{kt,kts,java,swift,m,mm}"
  - "**/*.gradle"
  - "**/AndroidManifest.xml"
  - "**/Info.plist"
  - "**/*.pro"
  - "**/Podfile"
  - "**/libs.versions.toml"
---

# Mobile security

対応表と根拠、リポジトリ段階の PII 検出は `docs/rules/security-mobile-reference.md`
を必要時に読むこと (本文には検証可能な Do / Don't だけを置く)。

## API キー・シークレット管理

- API キー / OAuth client secret / エンドポイント URL は `local.properties` または環境変数経由でビルド時に注入する
- `local.properties` / `*.keystore` / `.env*` を `.gitignore` で確実に除外する
- release build では `BuildConfig` フィールドにのみ展開し、ソースに残さない
- 誤コミット発覚時は **即座にシークレットをローテーション** し、`git filter-repo` 等で履歴から削除する

**Don't**

- API キー / シークレットをソースコードへハードコードしない
- 機密値をログ出力 / Crashlytics レポートに含めない
- `.env*` / `**/secrets/**` / `local.properties` / `*.keystore` を Claude に直接読ませない

## データ暗号化

- 認証情報 / トークン / 機密 PII は `EncryptedSharedPreferences`（Jetpack Security）で保存する
- SQLite で機密データを扱う場合は SQLCipher を採用する
- 機密ファイルは `EncryptedFile` を使用する
- 暗号化キーは Android Keystore System で保護する

**Don't**

- 暗号化キーをアプリコード / 平文 SharedPreferences に保存しない
- AES-128-ECB 等の脆弱モードを使用しない

## 通信・プライバシー保護

- 全通信は HTTPS（TLS 1.2 以上）
- `android:usesCleartextTraffic="false"` をデフォルトとし、例外は Network Security Config で明示する
- 証明書ピニングが必要な API は `network_security_config.xml` で設定する
- サードパーティ SDK の送信データを把握し、不要な情報収集 SDK を導入しない
- バックグラウンド送信は最小限に留め、ユーザに開示する

## パーミッション設計

- `AndroidManifest.xml` に必要最小限のパーミッションのみ宣言する
- 危険なパーミッション（CAMERA / LOCATION / CONTACTS 等）は使用直前にリクエストし、理由を UI で説明する
- 拒否時の代替フローを必ず実装する
- `ACCESS_FINE_LOCATION` より `ACCESS_COARSE_LOCATION` で足りる場合は後者を使用する
- Android 12+ の概算位置情報オプションに対応する

## ProGuard / 難読化

- release build で ProGuard / R8 を **有効化** する（`minifyEnabled true`、`shrinkResources true`）
- サードパーティ SDK 提供の ProGuard ルールを必ず適用する
- リフレクション使用クラスは `-keep` で保護する
- 難読化マッピング `mapping.txt` をリリースごとに保存・管理する

## デバッグ情報の管理

- `Log.d()` / `Log.v()` 等のデバッグログを release build から除外する
- `BuildConfig.DEBUG` フラグ、または Timber 等のライブラリで release 時無効化を徹底する
- スタックトレース・内部エラーメッセージをユーザ向け UI に表示しない
- デバッグ用 UI（シークレットメニュー等）は release で非表示にする

## ログの取り扱い

- PII（メール / 電話番号 / 氏名 / 位置情報）をログに出力しない
- ユーザ ID はハッシュ化してログに使う
- Firebase Crashlytics に機密カスタムキーを設定しない
- ログ保存期間を定め、不要ログを定期削除する
- external storage 保存時は Android 10+ のスコープドストレージに対応する

## ユーザ認証・セッション管理

- OAuth 2.0 / OpenID Connect は **PKCE フロー**（Authorization Code + PKCE）を使う
- アクセストークンは `EncryptedSharedPreferences`、リフレッシュトークンは Android Keystore で保護する
- セッションタイムアウトを実装し、長期非アクティブセッションを無効化する
- 生体認証は `BiometricPrompt` + Keystore 連携で行う
- ディープリンク経由の OAuth コールバック URL を厳密に検証し、リダイレクトインジェクションを防ぐ
- ログアウト時はトークンをサーバ側でも無効化し、ローカル認証情報を確実に消去する

## プライバシー・GDPR

- 個人情報収集前にユーザの明示的同意を取得する
- 収集データの種類・目的・保存期間をプライバシーポリシーに明記する
- データ削除要求（忘れられる権利）に対応するアーキテクチャを設計する
- Google Play Data Safety フォームと実際の収集内容を一致させる
- 未成年者向けアプリは COPPA + GDPR 児童条項を遵守する

## supply chain hygiene

- 依存ライブラリは公式リポジトリ / 公式 SDK のみを使う
- 依存追加前にライセンス（OSS license）・メンテナンス状況・最終リリース日を確認する
- `Gradle Version Catalog`（`libs.versions.toml`）等で依存バージョンを集中管理する
- 依存のセキュリティアドバイザリ（GitHub Dependabot / Snyk / OSV）を有効化する
- 重大脆弱性検知時は **24 時間以内** に patch / 代替へ切り替える

**Don't**

- 出所不明な GitHub gist / personal fork を依存に追加しない
- バージョン pinning なしの `+` / `latest.release` 指定を使わない
- 公式リポジトリ以外（jitpack の personal repo 等）を anchor として使い続けない

## インシデント・障害対応

- クラッシュ・セキュリティ異常を Firebase Crashlytics 等で即座に検知できる体制を整える
- 脆弱性発見時は **即座に修正リリース** を準備し、影響範囲をユーザへ通知する
- 認証情報漏洩疑いがある場合は即時ローテーション + 影響ユーザへパスワードリセットを促す
- 障害対応後は再発防止策をドキュメントに記録する

## 例外

- debug build のみで動作する HTTP サーバ等は `BuildConfig.DEBUG` ガード下で平文 SharedPreferences 可（信頼ローカル LAN 限定）
- 暗号化対象外: 公開コンテンツのみを扱う read-only キャッシュ
