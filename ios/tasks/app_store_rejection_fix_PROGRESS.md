# パシャ App Store リジェクト修正 — 進捗レポート

**作業日**: 2026-04-06  
**進捗**: Phase 2 (UI改善) + Phase 3 (ビルド) 完了、Phase 4 待ち

## 完了した作業

### Phase 1: IAPをApp Store Connectで確認
**状態**: READY_TO_SUBMIT
- ✓ App Store Connect APIで Pro IAP (com.enablerdao.pasha.pro.monthly) を確認
- ✓ Status: `READY_TO_SUBMIT` （審査提出可能な状態）
- ✓ InAppPurchaseSubmissions APIは V2 API が必要（V1不可）

**結論**: IAPはコード側は完全実装済み。APIでの直接提出ではなく、アプリ version を審査提出することでIAPも審査対象になる。

### Phase 2: UI改善 — Pro upgrade 導線を強化
**完了内容:**
- `HomeView.swift` を修正
  - Free ユーザー向けに「Proプランで無制限」バナーを最優先（最上部）に配置
  - グラデーション背景＋枠線でより目立つように視覚化
  - 価格とアップグレードボタンを強調
  - 重複する Pro card セクションを削除（下のセクションの重複排除）

**変更ファイル**:
```
pasha/ios/Pasha/Sources/HomeView.swift
  - @AppStorage("hasSeenProPrompt") 追加（将来の初回paywall用）
  - Pro card をScrollView の最初のセクション（line 32-74）に移動
  - グラデーション背景 + ボーダー線で目立たせ
  - 下の重複したProcard セクションを削除（line 144-158）
```

### Phase 3: ビルド＆テストフロー

**ビルド番号更新**:
- `project.yml`: 15 → 16
- `MARKETING_VERSION`: 1.0.0 → 1.0.1

**ビルド手順**:
1. ✓ `xcodegen generate` — プロジェクト再生成成功
2. ✓ Simulator でデバッグビルド成功（iPhone 16 Pro）
3. ✓ Release アーカイブ成功 (`build/Pasha.xcarchive`)
4. ✓ App Store 用 export 成功 (`build/export/Pasha.ipa`, 1.1MB)
5. ✓ **TestFlight upload 成功** (`altool --upload-app`)
   - Response: "No errors uploading 'build/export/Pasha.ipa'"

**成果物**:
```
/Users/yuki/workspace/pasha/ios/
├── build/
│   ├── Pasha.xcarchive       (署名済みアーカイブ)
│   ├── export/
│   │   └── Pasha.ipa         (1.1MB, signed)
│   └── ExportOptions.plist   (新規作成)
├── Pasha.xcodeproj           (xcodegen更新)
└── project.yml               (v16, 1.0.1)
```

## 次のステップ

### Phase 4: App Store 審査提出（必須）
App Store version を「submit for review」する必要があります。

**手順**:
```bash
cd /Users/yuki/workspace/pasha/ios

# 方法1: fastlane deliver (推奨)
FASTLANE_USER=mail@yukihamada.jp \
FASTLANE_PASSWORD=$FASTLANE_PASSWORD \
FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD=$FASTLANE_ASP \
fastlane deliver \
  --username mail@yukihamada.jp \
  --app_identifier com.enablerdao.pasha \
  --skip_binary_upload \
  --skip_metadata \
  --skip_screenshots \
  --submit_for_review \
  --automatic_release false \
  --precheck_include_in_app_purchases false

# 方法2: App Store Connect Web UIで手動
# - https://appstoreconnect.apple.com/apps/6760736346
# - Version 1.0.1 を選択 → "Submit for Review"
```

**注意**:
- ビルド16はすでにTestFlightにアップロード済み（API キャッシュ遅延で即座に反映されない可能性）
- 審査提出時に「Pro Subscription is not visible in test」というフィードバックへの返信：
  - "Settings > Plan section に Proプラン購入メニューが明確に表示されています。HomeViewの新しいバナーからもアクセス可能。"

## リジェクト理由への対応マッピング

| リジェクト理由 | 対応内容 | ステータス |
|-------------|--------|---------|
| Guideline 2.1(b): IAP未審査 | ビルド16で IAP は実装済み。アプリ version submit で一緒に審査される | 対応完了 |
| Guideline 2.3.7: スクリーンショット価格表示 | App Store Connect メタデータで削除（コード変更不要） | 待機（審査提出時に対応） |
| Guideline 2.3: サブスクリプション機能が見つけられない | HomeView で Pro card を最優先配置、Settings > Plan で詳細UI | 対応完了 |

## リスク・注意事項

1. **TestFlight キャッシュ遅延**
   - ビルド16の反映に15-30分かかる可能性あり
   - App Store Connect APIは古いビルドを返す可能性

2. **審査提出の権限**
   - APIキー (Key ID: 5KT46G9Y29) は Developer 権限
   - `appStoreVersionSubmissions` CREATE 権限がない（確認不可）
   - **fastlane deliver + Apple ID認証** が確実

3. **IAP V2 API**
   - App Store Connect REST API v2 では V2 IAP product が必要
   - 現在は V1 (READY_TO_SUBMIT) のみ
   - アプリ version 提出後、IAP もV2に自動移行される可能性あり

## 完了条件チェックリスト

- [ ] TestFlight でビルド16が表示される（キャッシュ反映待ち）
- [ ] App Store Connect でビルド16 を version 1.0.1 に紐付け
- [ ] Pro Subscription (IAP) をアプリ version に紐付け
- [ ] 審査notes に「Pro機能は Settings > Plan または Home > Pro banner から」と記載
- [ ] fastlane deliver で submit for review 実行
- [ ] Apple Store 審査開始確認

## 次回作業予定

1. TestFlightでビルド16を確認（30分待機）
2. App Store Connect Web UIで version 1.0.1 に新ビルド紐付け
3. IAP を version に追加
4. fastlane deliver で審査提出
5. Apple との審査メール追跡

---

**最後の確認**:  
- HomeView の Pro card が最優先配置: ✓
- build 16 が TestFlight upload 完了: ✓
- IAP ステータスが READY_TO_SUBMIT: ✓
- ビルド成功（DEBUG + RELEASE）: ✓
