---
id: version-management
title: Version management
description: App version system + in-app display + CI auto-increment
audience: [claude]
priority: high
applyTo:
  default: "**/*"
tags: [versioning, release, ci]
---

# Version management

## 要件

- 全アプリは marketingVersion (SemVer = Semantic Versioning、人間用) と buildNumber (整数 monotonic、配布チャネル用) の 2 階建てバージョンを持つ
- バージョン定義は単一 source of truth (source code 内 1 箇所) に置き、CI が build 時に各所に流す
- アプリは設定 / About 画面で `{marketingVersion} (build {buildNumber}) · commit {short SHA}` を必ず表示する
- crash report / log header / debug API (`/api/debug/state` 等) にも同じ identifier を埋め込む
- CI が `bump_build` workflow_dispatch で buildNumber を auto-increment する

## バージョン体系 (各 OS マッピング)

| platform | marketingVersion | buildNumber | source of truth |
|---|---|---|---|
| Android | `versionName` (1.2.3) | `versionCode` (整数 monotonic) | `app/build.gradle.kts` or `gradle.properties` |
| iOS | `CFBundleShortVersionString` (1.2.3) | `CFBundleVersion` (整数 or 1.2.3.456) | `xcconfig` or `Info.plist` or `project.yml` (xcodegen) |
| Flutter | `version: 1.2.3+456` | `+` 以降 | `pubspec.yaml` |
| Web (PWA) | `version` in `package.json` | git commit SHA short | `package.json` |
| ESP32 / firmware | `PROJECT_VER` 定数 | `BUILD_NUMBER` define | `platformio.ini` build_flags or `version.h` |

## Do

- バージョン定義は 1 ファイルに集約する
- 設定 / About 画面に必ずバージョン表示。形式: `1.2.3 (build 456) / commit a1b2c3d / built 2026-06-28`
- 表示は長押し / 5 連タップでクリップボードコピーできると故障報告時に楽 (推奨)
- crash report (Firebase Crashlytics / Sentry) にカスタム key で `app_build_full = "1.2.3-456-a1b2c3d"` を 1 つ立てる
- debug API (`/api/debug/state`) の response 先頭に `version` / `buildNumber` / `commit` / `builtAt` field を必ず含める
- CI で commit short SHA + built timestamp を build flag として inject (注入) する
- buildNumber は CI `bump_build` workflow_dispatch で auto-increment し、main に commit (PAT or GITHUB_TOKEN with contents: write)
- SemVer 判定:
  - Major ← API 互換性破壊
  - Minor ← 機能追加 (互換性保持)
  - Patch ← bug fix のみ
- リリースに対応する git tag (`vX.Y.Z`) を push

## Don't

- バージョン文字列を複数箇所にハードコードしない (drift する)
- buildNumber を減らさない (TestFlight / Play Store が reject する)
- crash report 用 identifier に PII (個人情報) を混ぜない
- 設定画面のバージョン表示を release build から除外しない (サポート時に必要)
- main 直接 push で buildNumber を上げない (CI `bump_build` workflow_dispatch で必ず PR 経由 + squash merge)

## 配布チャネル要件

| チャネル | buildNumber 増加 | 同一 buildNumber 再 upload |
|---|---|---|
| TestFlight | monotonic 必須 | 不可 (reject) |
| Play Store internal | monotonic 必須 | 不可 (reject) |
| Firebase App Distribution | 推奨 | 上書き可 (warning) |
| 社内 ad-hoc | 任意 | 可 |

## アプリ内表示の最小実装例 (Android Compose)

```kotlin
@Composable
fun AboutScreen() {
  Column {
    Text("バージョン: ${BuildConfig.VERSION_NAME} (build ${BuildConfig.VERSION_CODE})")
    Text("commit: ${BuildConfig.GIT_COMMIT}")
    Text("built: ${BuildConfig.BUILD_DATE}")
  }
}
```

## アプリ内表示の最小実装例 (iOS SwiftUI)

```swift
struct AboutView: View {
  var body: some View {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    let c = Bundle.main.infoDictionary?["GitCommit"] as? String ?? "?"
    VStack(alignment: .leading) {
      Text("バージョン: \(v) (build \(b))")
      Text("commit: \(c)")
    }
  }
}
```

## 根拠

- 「ユーザの screenshot から build を一意特定できる」がサポート品質の基準。in-app 表示なしだとリリース漏れ・再現困難の温床
- buildNumber monotonic は配布チャネル仕様で reject 条件、後追い対応はコストが高い
- 単一 source of truth は drift (差分蓄積) を防ぐ最も簡単な手段
- CI auto-increment は人為的ミス (build 番号巻き戻し / 重複) を排除

## 例外

- 自動生成コード (`*.g.kt` / `*_pb2.py`) はバージョン埋込対象外
- 開発初期 (1.0.0 未満) の experimental project は SemVer の Patch 桁を頻繁に動かしてもよい
- 内部社内ツール (社外配布なし) は in-app 表示を簡易化可 (commit のみでも可)

## 関連 rule

- `commit-convention` — Conventional Commits + squash merge + delete-branch
- (将来) `durable-references` — `vX.Y.Z` tag を `Refs:` で使う際の参照スタイル
- (将来) `dev-cycle` — debug API (`/api/debug/state`) にバージョン埋込する根拠
