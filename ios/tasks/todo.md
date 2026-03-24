# 電子帳簿保存法（スキャナ保存制度）完全対応 改修計画

## 概要
パシャ iOS アプリを電子帳簿保存法（令和4年改正対応）のスキャナ保存制度に完全対応させる。
既存の SwiftData + CryptoKit 基盤を活かし、最小限の変更で7要件を満たす。

## 調査結果

### 現在の構成（8ファイル, 約370行）
- `Receipt.swift` — SwiftData モデル。SHA-256ハッシュ、変更履歴JSON、サムネイル生成済み
- `CameraView.swift` — AVFoundation カメラ撮影。GPS/デバイス情報なし
- `ReceiptDetailView.swift` — 編集フォーム。onChange で addHistory() 呼び出し済み
- `SearchView.swift` — テキスト検索のみ（日付範囲・金額範囲なし）
- `HomeView.swift` — 月別一覧、CSV エクスポート
- `SettingsView.swift` — CSV/JSON エクスポート、全削除
- `PashaApp.swift` — modelContainer(for: Receipt.self) のみ
- `ContentView.swift` — TabView + フローティングカメラボタン

### 既存の強み（活用できるもの）
- SHA-256 ハッシュ生成 → チェーンハッシュに拡張するだけ
- historyJSON + addHistory() → 監査ログの基盤として利用可能
- SwiftData の自動永続化 → 新モデル追加が容易

### 不足している要素
1. 監査ログが Receipt モデル内 JSON → 改ざん可能（Receipt 削除でログも消える）
2. チェーンハッシュなし → 各レシートが独立しており連鎖的な真実性担保がない
3. 仕訳番号フィールドなし
4. GPS/デバイス情報の記録なし
5. 検索が単純テキストのみ → 日付範囲・金額範囲が必要
6. 削除がハード削除 → 論理削除+監査ログが必要

### 法的要件マッピング
| 要件 | 条文 | 現状 | 対応 |
|------|------|------|------|
| 真実性の確保 | 規則3条5項 | SHA-256のみ | チェーンハッシュ追加 |
| 訂正削除の履歴 | 規則3条5項2号ロ | addHistory()あるが脆弱 | イミュータブル監査ログ |
| 帳簿との相互関連性 | 規則3条5項5号 | なし | 仕訳番号フィールド |
| 検索機能 | 規則3条5項5号 | テキストのみ | 日付範囲・金額範囲・仕訳番号 |
| タイムスタンプ代替 | 令和4年改正 | なし | 訂正削除履歴システム |
| 解像度・色調 | 規則3条5項1号 | カメラ標準 | デバイス情報記録 |

## 実装ステップ

### Step 1: AuditLog モデル新設（推定: 中）
**ファイル: `AuditLog.swift`（新規作成）**

```swift
@Model final class AuditLog {
    var id: String           // UUID
    var timestamp: Date
    var receiptId: String    // 対象レシートID
    var action: String       // "作成" / "金額変更" / "削除" etc.
    var field: String        // 変更フィールド名（空文字=全体操作）
    var oldValue: String     // 変更前の値
    var newValue: String     // 変更後の値
    var sha256Hash: String   // このログエントリ自体のハッシュ
    var previousLogHash: String // 前のログエントリのハッシュ（チェーン）
}
```

- Receipt とは独立したテーブルで、Receipt 削除時もログは残る
- 各ログエントリに前エントリのハッシュを含めてチェーン化 → 改ざん検知
- `PashaApp.swift` の modelContainer に AuditLog.self を追加

**変更対象:** `PashaApp.swift`（modelContainer 拡張）

### Step 2: Receipt モデル拡張（推定: 中）
**ファイル: `Receipt.swift`（変更）**

追加フィールド:
```swift
var journalNumber: String    // 仕訳番号（帳簿との相互関連性）
var previousHash: String     // 前レシートのハッシュ（チェーンハッシュ）
var latitude: Double?        // GPS緯度
var longitude: Double?       // GPS経度
var deviceModel: String      // デバイスモデル (e.g. "iPhone 15 Pro")
var osVersion: String        // OS バージョン (e.g. "iOS 17.4")
var isDeleted: Bool          // 論理削除フラグ
var deletedAt: Date?         // 論理削除日時
```

- SwiftData のスキーママイグレーション: デフォルト値で既存データ互換維持
- `init()` で `UIDevice.current` からデバイス情報を自動取得
- チェーンハッシュ: SHA256(画像データ + previousHash) で生成

### Step 3: 撮影時のGPS・チェーンハッシュ取得（推定: 中）
**ファイル: `CameraView.swift`（変更）, `LocationManager.swift`（新規作成）**

- `CLLocationManager` で撮影時の位置情報を取得
- `project.yml` に `NSLocationWhenInUseUsageDescription` を追加
- `capturePhoto()` 内で最新レシートの sha256Hash を取得し、新レシートの previousHash にセット
- Receipt init に GPS 座標・デバイス情報を渡す

### Step 4: 監査ログ記録の統合（推定: 中）
**ファイル: `ReceiptDetailView.swift`（変更）**

- 既存の `receipt.addHistory()` 呼び出しを `AuditLog` 書き込みに置き換え
- 変更前の値（oldValue）をキャプチャするため、onChange の old/new パラメータを活用
- 削除をハード削除 → 論理削除（isDeleted=true）に変更し、AuditLog に "削除" を記録
- 削除されたレシートの復元UI（オプション）

**ファイル: `HomeView.swift`（変更）**
- `@Query` の filter に `isDeleted == false` を追加

### Step 5: 検索機能の強化（推定: 中）
**ファイル: `SearchView.swift`（変更）**

追加する検索条件:
- 日付範囲（DatePicker x2: 開始日・終了日）
- 金額範囲（TextField x2: 下限・上限）
- 仕訳番号（TextField）
- 既存のテキスト検索はそのまま維持

UI構成:
```
[テキスト検索バー]         ← 既存
[フィルター展開ボタン]      ← 新規
  ├ 日付: [開始] 〜 [終了]
  ├ 金額: [下限] 〜 [上限]
  └ 仕訳番号: [入力欄]
[検索結果リスト]           ← 既存
```

### Step 6: 監査ログ閲覧UI + 整合性検証（推定: 小）
**ファイル: `AuditLogView.swift`（新規作成）**

- 全監査ログの時系列表示（Receipt 単位でフィルタ可能）
- チェーンハッシュの整合性検証ボタン: 全ログを走査し、各エントリの previousLogHash が前エントリの sha256Hash と一致するか確認
- 検証結果を緑/赤で表示

**ファイル: `SettingsView.swift`（変更）**
- 「監査ログ」メニュー項目を追加（AuditLogView への NavigationLink）
- 「データ整合性チェック」ボタンを追加
- CSV/JSON エクスポートに仕訳番号・GPS 情報を含める

### Step 7: Info.plist / project.yml 更新（推定: 小）
**ファイル: `project.yml`（変更）**

```yaml
NSLocationWhenInUseUsageDescription: レシート撮影時の位置情報を電子帳簿保存法の要件として記録します
```

## 新規ファイル一覧
| ファイル | 行数目安 | 役割 |
|---------|---------|------|
| `AuditLog.swift` | ~60行 | イミュータブル監査ログモデル |
| `LocationManager.swift` | ~40行 | CLLocationManager ラッパー |
| `AuditLogView.swift` | ~100行 | 監査ログ閲覧 + 整合性検証UI |

## 変更ファイル一覧
| ファイル | 変更規模 | 内容 |
|---------|---------|------|
| `Receipt.swift` | 中 | 6フィールド追加、init 拡張 |
| `CameraView.swift` | 中 | GPS取得、チェーンハッシュ、デバイス情報 |
| `ReceiptDetailView.swift` | 中 | AuditLog統合、仕訳番号フィールド、論理削除 |
| `SearchView.swift` | 中 | 日付範囲・金額範囲・仕訳番号検索 |
| `HomeView.swift` | 小 | isDeleted フィルタ、CSV に仕訳番号追加 |
| `SettingsView.swift` | 小 | 監査ログUI、エクスポート拡張 |
| `PashaApp.swift` | 小 | modelContainer に AuditLog 追加 |
| `project.yml` | 小 | 位置情報パーミッション追加 |

## テスト方針
- [ ] ビルド確認: `xcodebuild -project Pasha.xcodeproj -scheme Pasha -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
- [ ] Receipt 新規作成 → AuditLog に "作成" が記録されること
- [ ] Receipt フィールド変更 → AuditLog に oldValue/newValue が記録されること
- [ ] Receipt 削除 → 論理削除され、AuditLog に "削除" が記録されること
- [ ] チェーンハッシュ: 2件目以降のレシートに前レシートのハッシュが含まれること
- [ ] 整合性検証: 正常時は全件グリーン、手動でDB改ざんすると赤が出ること
- [ ] 検索: 日付範囲・金額範囲・仕訳番号で正しく絞り込めること
- [ ] GPS: シミュレータのカスタムロケーションで緯度経度が記録されること
- [ ] CSV/JSON エクスポートに新フィールドが含まれること

## リスク
1. **SwiftData マイグレーション**: 既存データがある端末でスキーマ変更時にクラッシュする可能性
   - 対策: 全追加フィールドにデフォルト値を設定、VersionedSchema は不要（全フィールド Optional or デフォルト値）
2. **位置情報パーミッション拒否**: ユーザーが許可しない場合
   - 対策: GPS は Optional、未取得でも保存は可能にする
3. **パフォーマンス**: AuditLog が大量になった場合のクエリ速度
   - 対策: receiptId にインデックス、表示は最新50件にページネーション
4. **チェーンハッシュの一貫性**: 並行保存時にチェーンが壊れる可能性
   - 対策: 保存処理を直列化（CameraView の capturePhoto 内で同期的に前ハッシュ取得）

## 完了条件
- [ ] 電子帳簿保存法スキャナ保存の全要件（真実性・可視性）を満たしている
- [ ] 訂正・削除の全履歴が改ざん不能な形で記録される（令和4年改正対応）
- [ ] 仕訳番号による帳簿との相互関連性が確保されている
- [ ] 日付範囲・金額範囲・仕訳番号での検索が可能
- [ ] チェーンハッシュにより書類間の連続的な真実性が担保される
- [ ] 撮影時のGPS・デバイス情報が記録される
- [ ] 既存データとの互換性が維持される（マイグレーション不要）
- [ ] ビルドが通り、シミュレータで全機能が動作する
