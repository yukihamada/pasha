# パシャ App Store リジェクト修正計画

## リジェクト理由（2026-04-05）

1. **Guideline 2.1(b)**: In-App Purchase未審査
   - Pro subscription (¥980/月) がアプリに実装されているが、App Store Connectで審査提出されていない
   - status: likely WAITING_FOR_REVIEW or READY_TO_SUBMIT

2. **Guideline 2.3.7**: スクリーンショットに価格表示
   - ¥980/月 などの記載がスクリーンショットに含まれている
   - 対策: App Store Connectのメタデータ側で削除（コード変更不要）

3. **Guideline 2.3**: サブスクリプション機能が見つけられない
   - iPad Air M3でテストしたレビュアーが、Pro機能にアクセスできなかった
   - 対策: SettingsViewへの導線を明確化、初回起動でも見つけやすく

## 実装状況

### 既に実装済み
- SubscriptionManager.swift: StoreKit 2 完全実装
  - purchasePro(), restorePurchases(), updateSubscriptionStatus()
  - Fan Club (promo code) 対応済み
- SettingsView.swift: Pro購入UI完備
  - 現在のプラン表示、購入ボタン、購入復元、エラー表示

### 不足している
- **App Store Connect側**: IAP (com.enablerdao.pasha.pro.monthly) が審査提出されていない
- **初回起動フロー**: Free時に Pro upgrade を促すフローが弱い
- **Pro機能ランディング**: Settings > Plan セクションに到達する導線がわかりにくい可能性

## 対応手順

### 1. App Store Connect APIでIAP審査提出（高優先度）
```bash
# JWT token生成 + API呼び出し
# IAPのstateが READY_TO_SUBMIT ならPATCHでsubmit for review
# stateがWAITING_FOR_REVIEWなら何もしない
```

### 2. UI改善: Pro upgrade 導線を強化（中優先度）
- [ ] HomeView: Free時に「Proプランで無制限」バナーを追加
- [ ] Settings > Plan セクションを最上部に移動
- [ ] Pro badge を home タブに表示

### 3. スクリーンショット修正（低優先度、ASC作業）
- [ ] App Store Connectで価格記載を削除
- [ ] プライバシーポリシーなどの法的情報は残す

### 4. TestFlightでテスト（全対応後）
```bash
cd /Users/yuki/workspace/pasha/ios
# ビルド番号を15→16に更新
# xcodegen + archive + export
# TestFlightアップロード
```

### 5. App Store 審査提出
```bash
fastlane deliver \
  --username mail@yukihamada.jp \
  --app_identifier com.enablerdao.pasha \
  --submit_for_review
```

## 作業内容

### Phase 1: IAPを App Store Connectで審査提出（必須）
- **内容**: REST APIで IAP product state を確認し、submit for review へ遷移
- **所要時間**: 30分
- **リスク**: API認証失敗時は手動でASC UIから対応

### Phase 2: コード軽微改善（推奨）
- **HomeView**: Free / Pro バナー追加
- **SettingsView**: Plan セクションをリスト最上部に移動
- **所要時間**: 1時間
- **リスク**: UIレイアウト崩れ可能性→シミュレータ確認必須

### Phase 3: ビルド＆テスト
- ビルド番号15→16更新
- xcodegen generate
- Simulator/実機でPro購入フローテスト
- TestFlightアップロード
- **所要時間**: 30分

### Phase 4: 最終審査提出
- fastlane deliver で App Store に提出
- **所要時間**: 10分（自動）

## 完了条件
- [ ] IAPが App Store Connect審査へ提出済み
- [ ] TestFlightで Pro 購入フローが動作確認済み
- [ ] App Store 審査提出完了
- [ ] レビュアー向け Notes に「Pro機能は Settings > Plan section から」と記載
