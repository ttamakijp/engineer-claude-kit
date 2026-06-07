---
name: android-build
description: |
  Android プロジェクトのビルド・ADB インストール・gradle 操作を支援する skill。
  user が build / install apk / ADB / gradle 関連を依頼したときに起動。
---

# android-build

Android プロジェクトの代表的なタスク (build (ビルド) / install / clean / test) を支援する。

## 起動条件

user の依頼に以下のキーワードが含まれるとき:
- 「ビルド」「build」「APK」「apk」
- 「インストール」「install」「adb」「ADB」
- 「gradle」「gradlew」「clean」
- 「Android テスト」「unit test」

## 主要コマンド

### Build
```powershell
./gradlew assembleDebug                # debug APK 生成
./gradlew assembleRelease              # release APK
./gradlew clean                        # clean
```

### ADB
```powershell
adb devices                            # 接続デバイス一覧
adb install -r build/outputs/apk/debug/app-debug.apk
adb logcat | Select-String "<package>" # logcat フィルタ
```

### Test
```powershell
./gradlew test                         # unit test
./gradlew connectedAndroidTest         # instrumentation test
```

## 制約

- Windows / OneDrive 環境では cloud-build-wrapper を推奨 (file lock 回避)
- release build は `keystore` / `local.properties` を必要、これらは config 化推奨
- ADB 接続トラブル時は `adb kill-server && adb start-server`

## Refs

- Android Developers: https://developer.android.com/studio/build
