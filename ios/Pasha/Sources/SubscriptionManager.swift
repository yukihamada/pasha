import StoreKit
import SwiftUI
import SwiftData
import Foundation
import CommonCrypto

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    enum Tier: String, Codable {
        case free = "free"
        case pro = "pro"  // ¥980/月 - 全機能（電子帳簿保存法、ブロックチェーン、無制限）
    }

    enum ProSource: String {
        case none
        case subscription  // IAP
        case fanClub       // ENABLER NFT
    }

    static let proProductID = "com.enablerdao.pasha.pro.monthly"

    /// Promo code verification endpoint (enablerdao.com fan club API)
    static let promoCodesURL = "https://enablerdao.com/api/fanclub/codes"

    @Published var currentTier: Tier = .free
    @Published var proSource: ProSource = .none
    @Published var monthlyReceiptCount: Int = 0
    @Published var proProduct: Product?
    @Published var purchaseError: String?
    @Published var isPurchasing: Bool = false
    @Published var expirationDate: Date?

    // Fan club (promo code)
    @Published var isFanClubVerified: Bool = false
    @Published var fanClubError: String?
    @Published var isVerifyingFanClub: Bool = false

    let freeMonthlyLimit = 30

    private var transactionListener: Task<Void, Never>?

    // UserDefaults keys for fan club persistence
    private let fanClubCodeHashKey = "enabler_fanclub_code_hash"
    private let fanClubVerifiedKey = "enabler_fanclub_verified"
    private let fanClubVerifiedDateKey = "enabler_fanclub_verified_date"

    var canAddReceipt: Bool {
        currentTier != .free || monthlyReceiptCount < freeMonthlyLimit
    }

    var remainingFreeCount: Int {
        max(0, freeMonthlyLimit - monthlyReceiptCount)
    }

    var hasComplianceFeatures: Bool {
        currentTier == .pro
    }

    var hasBlockchainFeatures: Bool {
        currentTier == .pro
    }

    var hasExportFeatures: Bool {
        currentTier == .pro
    }

    var tierDisplayName: String {
        switch currentTier {
        case .free: return "Free"
        case .pro: return "Pro"
        }
    }

    var proSourceText: String {
        switch proSource {
        case .subscription: return "サブスクリプション"
        case .fanClub: return "Enablerファンクラブ"
        case .none: return ""
        }
    }

    var formattedPrice: String {
        proProduct?.displayPrice ?? ""
    }

    var subscriptionStatusText: String {
        guard currentTier == .pro else { return "" }
        if proSource == .fanClub {
            return "Enablerファンクラブ特典"
        }
        if let exp = expirationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "次回更新: \(formatter.string(from: exp))"
        }
        return "有効"
    }

    // MARK: - Lifecycle

    init() {
        transactionListener = listenForTransactions()
        loadFanClubState()
    }

    deinit {
        transactionListener?.cancel()
    }

    /// Count receipts created this month
    func updateMonthlyCount(context: ModelContext) {
        let cal = Calendar.current
        let now = Date()
        guard let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return }
        let descriptor = FetchDescriptor<Receipt>(
            predicate: #Predicate { $0.createdAt >= startOfMonth && !$0.isDeleted }
        )
        monthlyReceiptCount = (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Load subscription status from StoreKit 2 + fan club
    func loadTier() {
        Task {
            await fetchProduct()
            await updateSubscriptionStatus()
        }
    }

    // MARK: - StoreKit 2

    /// Fetch the Pro product from App Store
    func fetchProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
        } catch {
            print("[SubscriptionManager] Failed to fetch products: \(error)")
        }
    }

    /// Check current entitlements and update tier (StoreKit + fan club)
    func updateSubscriptionStatus() async {
        var foundStoreKitPro = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.proProductID && transaction.revocationDate == nil {
                foundStoreKitPro = true
                expirationDate = transaction.expirationDate
                break
            }
        }

        if foundStoreKitPro {
            currentTier = .pro
            proSource = .subscription
        } else if isFanClubVerified {
            currentTier = .pro
            proSource = .fanClub
            expirationDate = nil
        } else {
            currentTier = .free
            proSource = .none
            expirationDate = nil
        }
    }

    // MARK: - Fan Club (Promo Code)

    /// Load persisted fan club state from UserDefaults
    private func loadFanClubState() {
        let defaults = UserDefaults.standard
        isFanClubVerified = defaults.bool(forKey: fanClubVerifiedKey)

        // Re-verify code validity every 7 days
        if isFanClubVerified, let lastDate = defaults.object(forKey: fanClubVerifiedDateKey) as? Date {
            if Date().timeIntervalSince(lastDate) > 7 * 86400 {
                Task { await refreshFanClubCode() }
            }
        }
    }

    /// Verify a promo code against the server hash list
    func verifyPromoCode(_ code: String) async {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            fanClubError = "招待コードを入力してください"
            return
        }

        isVerifyingFanClub = true
        fanClubError = nil

        do {
            let codeHash = sha256(normalized)
            let valid = try await checkCodeHash(codeHash)

            if valid {
                isFanClubVerified = true
                saveFanClubState(codeHash: codeHash)
                await updateSubscriptionStatus()
            } else {
                fanClubError = "無効な招待コードです"
            }
        } catch {
            fanClubError = "検証に失敗しました。ネットワークを確認してください。"
        }

        isVerifyingFanClub = false
    }

    /// Disconnect fan club membership
    func disconnectFanClub() {
        isFanClubVerified = false
        fanClubError = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: fanClubCodeHashKey)
        defaults.set(false, forKey: fanClubVerifiedKey)
        defaults.removeObject(forKey: fanClubVerifiedDateKey)
        Task { await updateSubscriptionStatus() }
    }

    /// Silently re-verify the stored code is still valid
    private func refreshFanClubCode() async {
        let defaults = UserDefaults.standard
        guard let storedHash = defaults.string(forKey: fanClubCodeHashKey) else { return }
        do {
            let valid = try await checkCodeHash(storedHash)
            isFanClubVerified = valid
            if valid {
                defaults.set(Date(), forKey: fanClubVerifiedDateKey)
            } else {
                defaults.set(false, forKey: fanClubVerifiedKey)
            }
            await updateSubscriptionStatus()
        } catch {
            // Keep existing state on network error
        }
    }

    private func saveFanClubState(codeHash: String) {
        let defaults = UserDefaults.standard
        defaults.set(codeHash, forKey: fanClubCodeHashKey)
        defaults.set(true, forKey: fanClubVerifiedKey)
        defaults.set(Date(), forKey: fanClubVerifiedDateKey)
    }

    /// Fetch hash list from server and check if codeHash exists
    private func checkCodeHash(_ codeHash: String) async throws -> Bool {
        guard let url = URL(string: Self.promoCodesURL) else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let hashes = json?["hashes"] as? [String] else { return false }
        return hashes.contains(codeHash)
    }

    /// SHA-256 hash of a string
    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Purchase the Pro subscription
    func purchasePro() async {
        isPurchasing = true
        purchaseError = nil

        // If the product has not yet been fetched, fetch it now before proceeding.
        if proProduct == nil {
            await fetchProduct()
        }

        guard let product = proProduct else {
            purchaseError = "商品情報を取得できません。しばらくしてから再度お試しください。"
            isPurchasing = false
            return
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseError = "トランザクションの検証に失敗しました"
                    isPurchasing = false
                    return
                }
                await transaction.finish()
                await updateSubscriptionStatus()

            case .userCancelled:
                break

            case .pending:
                purchaseError = "購入が保留中です。承認後に反映されます。"

            @unknown default:
                purchaseError = "不明なエラーが発生しました"
            }
        } catch {
            purchaseError = "購入に失敗しました: \(error.localizedDescription)"
        }

        isPurchasing = false
    }

    /// Restore purchases
    func restorePurchases() async {
        isPurchasing = true
        purchaseError = nil

        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            if currentTier == .free {
                purchaseError = "復元可能なサブスクリプションが見つかりません"
            }
        } catch {
            purchaseError = "復元に失敗しました: \(error.localizedDescription)"
        }

        isPurchasing = false
    }

    // MARK: - Transaction Listener

    /// Listen for transaction updates (renewals, cancellations, revocations)
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.updateSubscriptionStatus()
            }
        }
    }
}
