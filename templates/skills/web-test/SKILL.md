---
name: web-test
description: |
  Web / Node.js プロジェクトのテスト実行と依存管理を支援する skill。
  user が npm test / jest / vitest 等を依頼したときに起動。
---

# web-test

Web / Node プロジェクトの test 実行・依存管理を支援する。

## 起動条件

user の依頼に以下のキーワードが含まれるとき:
- 「テスト」「test」「jest」「vitest」「mocha」
- 「npm」「yarn」「pnpm」
- 「依存」「dependency」「install」「update」

## 主要コマンド

### Test
```powershell
npm test                               # package.json の test script
npm run test:watch                     # watch モード (定義済なら)
npx jest <pattern>                     # 個別 file pattern
npx vitest                             # vitest 直接
```

### 依存管理
```powershell
npm install                            # package.json から install
npm install <pkg> --save               # 追加
npm outdated                           # 更新可能 list
npm audit fix                          # 脆弱性自動修正
```

## 制約

- `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` の整合性を保つ (削除しない)
- Node version は `.nvmrc` / `engines` で固定推奨
- monorepo の場合は workspace 構造を最初に確認

## Refs

- npm docs: https://docs.npmjs.com/
- Jest: https://jestjs.io/
