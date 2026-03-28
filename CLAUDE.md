# パシャ — AI搭載レシート経費管理

## 概要
- **サイト**: https://pasha.run (Fly.io `pasha-app`, Cloudflare DNS)
- **iOS**: Swift/SwiftUI + SwiftData + Vision OCR + Swift Charts
- **Bundle ID**: `com.enablerdao.pasha`
- **App Store Connect**: App ID `6760736346`
- **TestFlight**: https://testflight.apple.com/join/CTmyqV6H
- **Solanaウォレット**: `BeWJUYAp1rijxcNmYe9hvKCt9UvA4sHJvPKVGqrd5gmo`
- **料金**: Free(月30件) / Pro(¥980/月)

## ディレクトリ構成
```
pasha/
├── ios/                    # iOSアプリ (SwiftUI)
│   ├── Pasha/
│   │   ├── Sources/        # 全Swiftソース
│   │   ├── Resources/      # Assets.xcassets
│   │   ├── Info.plist
│   │   └── Pasha.entitlements
│   ├── project.yml         # XcodeGen設定
│   ├── fastlane/           # Fastfile, Appfile
│   ├── build/              # アーカイブ, IPA出力
│   └── .keys/              # Solanaウォレット鍵 (gitignore)
├── site/                   # サービスサイト (静的HTML)
│   ├── index.html
│   ├── privacy.html
│   ├── Dockerfile
│   ├── nginx.conf
│   └── fly.toml
└── CLAUDE.md               # このファイル
```

## 主要ソースファイル
| ファイル | 役割 |
|---------|------|
| `PashaApp.swift` | エントリポイント。2つのModelContainer(Main+Audit) |
| `ContentView.swift` | タブ管理、ブランドカラー定義、GlassCard modifier |
| `CameraView.swift` | カメラ撮影、フォトライブラリ、連続撮影、OCR→ReceiptParser |
| `HomeView.swift` | レシート一覧、月次統計、予算バー |
| `ReportView.swift` | 月次レポート、ドーナツチャート、棒グラフ (Swift Charts) |
| `SearchView.swift` | テキスト検索、金額範囲フィルタ |
| `SettingsView.swift` | プラン管理、カテゴリ管理、エクスポート、AI設定、Solana |
| `ReceiptDetailView.swift` | レシート詳細編集、AI再解析、監査ログ表示 |
| `Receipt.swift` | SwiftDataモデル、画像ファイルI/O、チェーンハッシュ |
| `AuditLog.swift` | 監査ログモデル、チェーンハッシュ |
| `AuditManager.swift` | 監査ログ管理、Solanaアンカリング |
| `OCREngine.swift` | Vision OCRテキスト認識 (rawLines抽出のみ) |
| `ReceiptParser.swift` | レシート構造解析 (金額/日付/取引先/カテゴリ推定) |
| `SolanaAnchor.swift` | Merkleルート計算、オンチェーンMemo Tx送信 |
| `SubscriptionManager.swift` | Free/Proプラン管理 |
| `VLMManager.swift` | Qwen3-VL 2B GGUFモデルDL管理 |
| `CustomCategory.swift` | カスタム勘定科目 |
| `DuplicateDetector.swift` | 重複レシート検知 |
| `ProcessingTipsView.swift` | AI解析中のTips表示 |
| `PashaIntents.swift` | Siriショートカット |
| `SeedTestData.swift` | テストデータ生成 (#if DEBUG) |

## ビルド & デプロイ

### iOSアプリ（フル自動パイプライン）
```bash
cd pasha/ios

# 1. ビルド番号更新
sed -i '' 's/CURRENT_PROJECT_VERSION: N/CURRENT_PROJECT_VERSION: N+1/' project.yml

# 2. プロジェクト生成
xcodegen generate

# 3. アーカイブ
xcodebuild archive -project Pasha.xcodeproj -scheme Pasha -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Pasha.xcarchive \
  PROVISIONING_PROFILE_SPECIFIER="com.enablerdao.pasha AppStore" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" DEVELOPMENT_TEAM=5BV85JW8US

# 4. TestFlightアップロード
xcodebuild -exportArchive -archivePath build/Pasha.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_5KT46G9Y29.p8 \
  -authenticationKeyID 5KT46G9Y29 \
  -authenticationKeyIssuerID e0d22675-afb3-45f0-a821-06b477f44da0

# 5. 審査提出
FASTLANE_USER=mail@yukihamada.jp \
FASTLANE_PASSWORD=$FASTLANE_PASSWORD \
FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD=$FASTLANE_ASP \
# Note: Set FASTLANE_PASSWORD and FASTLANE_ASP in ~/.env or shell environment (never commit plaintext)
fastlane deliver --username mail@yukihamada.jp --app_identifier com.enablerdao.pasha \
  --skip_binary_upload --skip_metadata --skip_screenshots \
  --submit_for_review --automatic_release false --force \
  --precheck_include_in_app_purchases false
```

### 実機インストール (Debug)
```bash
xcodebuild -project Pasha.xcodeproj -scheme Pasha \
  -destination 'generic/platform=iOS' -sdk iphoneos -configuration Debug \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_5KT46G9Y29.p8 \
  -authenticationKeyID 5KT46G9Y29 \
  -authenticationKeyIssuerID e0d22675-afb3-45f0-a821-06b477f44da0 build
xcrun devicectl device install app --device 00008140-0005453411E0801C \
  ~/Library/Developer/Xcode/DerivedData/Pasha-*/Build/Products/Debug-iphoneos/Pasha.app
xcrun devicectl device process launch --device 00008140-0005453411E0801C com.enablerdao.pasha
```

### サイトデプロイ
```bash
cd pasha/site && fly deploy --remote-only
```

## 署名 & プロビジョニング
- **Team ID**: 5BV85JW8US
- **Distribution Cert**: `20FD22928A6D5ACF3D34A278979F712E5B13ED64`
- **Profile**: `com.enablerdao.pasha AppStore` (sighで自動生成)
- **APIキー**: 5KT46G9Y29 (Developer権限 — 審査提出はfastlane deliver経由)
- **Apple ID**: mail@yukihamada.jp

## アーキテクチャ
- **2つのModelContainer**: Main(Receipt+CustomCategory, CloudKit準備済) + Audit(AuditLog, ローカルのみ)
- **OCRパイプライン**: Vision OCR → rawLines → ReceiptParser (構造解析、40+チェーン店認識、カテゴリ自動判定)
- **チェーンハッシュ**: Receipt間 + AuditLog間の二重チェーン (SHA-256)
- **Solana**: Merkleルート → Memo Tx (秘密鍵はKeychain保存)
- **画像保存**: Documents/receipts/ にJPEG保存、NSCacheでメモリキャッシュ (50枚/50MB)

## 注意事項
- 審査提出時は `demoAccountRequired: false` 必須（ログイン不要アプリ）
- APIキーの権限では `appStoreVersionSubmissions` CREATE不可 → fastlane deliver経由
- CloudKit entitlementはDev profileに含まれない → Debug時は `.none`、App Store版で `.automatic`
- XcodeGenが `Pasha.entitlements` を毎回上書きする → entitlement propertiesは `project.yml` に記述
- Solana秘密鍵はKeychain保存。ソースコードに含めない
- `#if DEBUG` で `SeedTestData.seed()` が動く → Releaseビルドには含まれない
