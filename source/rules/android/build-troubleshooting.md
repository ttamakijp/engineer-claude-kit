# Android Build Troubleshooting Guide

## 概要

PALM アプリ（Android）のビルドおよび実装時に発生した代表的なトラブルと解決策を記録します。

---

## 1. Gradle キャッシュ問題

### 症状
- コード修正を加えたにもかかわらず、ビルド後の APK に修正が反映されない
- 同じエラーがデバイスで繰り返される

### 原因
- gradle の dexBuilder キャッシュが古いバイトコードを保持している
- 出力ディレクトリがシンボリックリンク化しており、キャッシュが混在している

### 解決方法

1. **dexBuilder キャッシュをクリア**
```bash
rm -rf app/build/intermediates/dexBuilder
```

2. **出力ディレクトリ全体を削除**
```bash
rm -rf /c/Temp/PALM/app  # または build.gradle.kts で指定されたカスタム出力先
```

3. **gradle デーモンを停止**
```bash
./gradlew --stop
```

4. **完全クリーン + ビルド**
```bash
./gradlew clean assembleDebug --no-daemon
```

### ベストプラクティス
- build.gradle.kts でカスタム出力ディレクトリを設定する場合、OneDrive との file lock 競合を回避するため、**`C:\Temp\` など OneDrive 外に配置**する
- gradle キャッシュをクリアする際は、gradle デーモンを明示的に停止してから実行する

---

## 2. WifiP2pConfig SSID フォーマット制約

### 症状
```
java.lang.IllegalArgumentException: network name must starts with the prefix DIRECT-xy.
```

### 原因
- Android の `WifiP2pConfig.Builder.setNetworkName()` は Wi-Fi Direct グループ名に対して **厳密な `DIRECT-xy` フォーマット** を要求する
- SSID が `DIRECT-PALM_XXXX` のように 4 文字以上の suffix を持つと例外が発生する

### 解決方法

**オプション 1: 通常のモバイルホットスポット一本化（推奨）**
- Wi-Fi Direct グループ作成を削除
- `DataFilesActivity` の通常ホットスポット実装（`PALM_XXXX` 形式）に統一
- ホットスポット自動維持は TetheringManager で実装

**オプション 2: SSID を 2 文字に限定**
```kotlin
val ssid = "DIRECT-${androidId.takeLast(2).uppercase()}"  // DIRECT-AB 形式
```

**現在の PALM の実装状況**
- MapActivity での Wi-Fi Direct グループ作成を削除
- DataFilesActivity の通常ホットスポット（`PALM_XXXX`）に統一
- これにより、PC からは常に同じ命名スキーム (`PALM_2F5D` など) でホットスポットが表示される

### ベストプラクティス
- ホットスポットが必要な場合は、**通常のモバイルホットスポット** (`TetheringManager`) を使用する
- Wi-Fi Direct が必ず必要な場合のみ、`DIRECT-xy` フォーマット要件を厳密に守る
- 複数の実装方式（通常ホットスポット vs Wi-Fi Direct）を混在させない

---

## 3. DataTransferServer での自動ファイル配置

### 実装
- アプリ起動時に `DataTransferServer.start()` が呼び出される際、`PALM-Edge.bat` を自動的に `Android/data/com.palm/files/helper/` に配置する
- WebUI からダウンロード可能にすることで、ユーザが手動コピーの手間を省く

### コード例
```kotlin
private fun ensurePalmEdgeBat() {
    try {
        val externalDir = context.getExternalFilesDir(null) ?: return
        val helperDir = java.io.File(externalDir, "helper")
        if (!helperDir.exists()) {
            helperDir.mkdirs()
        }
        val targetFile = java.io.File(helperDir, "PALM-Edge.bat")
        if (targetFile.exists()) return

        val batContent = "set /p URL=URL:\nstart \"\" \"C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe\" --no-proxy-server --user-data-dir=\"%LOCALAPPDATA%\\PALM-Edge\" \"%URL%\""
        targetFile.writeText(batContent, Charsets.UTF_8)
        Log.d(TAG, "PALM-Edge.bat created at ${targetFile.absolutePath}")
    } catch (e: Exception) {
        Log.w(TAG, "ensurePalmEdgeBat failed: ${e.message}")
    }
}
```

---

## 4. クイックリファレンス

### よく使うビルドコマンド
```bash
# 完全クリーン + ビルド（キャッシュ問題時）
./gradlew clean assembleDebug --no-daemon

# gradle デーモン停止
./gradlew --stop

# キャッシュ削除 + ビルド
rm -rf ~/.gradle/caches && ./gradlew clean assembleDebug

# APK インストール（両デバイス）
APK="/c/Temp/PALM/app/build/outputs/apk/debug/app-debug.apk"
adb -s 1A281JEG505382 install -r "$APK"
adb -s 29211FDH300MLG install -r "$APK"
```

---

## 参考資料
- [Android WifiP2pConfig Documentation](https://developer.android.com/reference/android/net/wifi/p2p/WifiP2pConfig)
- [Gradle Build Cache](https://docs.gradle.org/current/userguide/build_cache.html)
- PALM Project CLAUDE.md
