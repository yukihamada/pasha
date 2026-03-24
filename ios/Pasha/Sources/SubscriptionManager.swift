import StoreKit
import SwiftUI
import SwiftData

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    enum Tier: String, Codable {
        case free = "free"
        case pro = "pro"  // ¥980/月 - 全機能（電子帳簿保存法、ブロックチェーン、無制限）
    }

    static let proProductID = "com.enablerdao.pasha.pro.monthly"

    @Published var currentTier: Tier = .free
    @Published var monthlyReceiptCount: Int = 0
    @Published var proProduct: Product?
    @Published var purchaseError: String?
    @Published var isPurchasing: Bool = false
    @Published var expirationDate: Date?

    let freeMonthlyLimit = 30

    private var transactionListener: Task<Void, Never>?

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

    var formattedPrice: String {
        proProduct?.displayPrice ?? "¥980/月"
    }

    var subscriptionStatusText: String {
        guard currentTier == .pro else { return "" }
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
    }

    deinit {
        transactionListener?.cancel()
    }

    /// Count receipts created this month
    func updateMonthlyCount(context: ModelContext) {
        let cal = Calendar.current
        let now = Date()
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let descriptor = FetchDescriptor<Receipt>(
            predicate: #Predicate { $0.createdAt >= startOfMonth && !$0.isDeleted }
        )
        monthlyReceiptCount = (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Load subscription status from StoreKit 2
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

    /// Check current entitlements and update tier
    func updateSubscriptionStatus() async {
        var foundPro = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.proProductID && transaction.revocationDate == nil {
                foundPro = true
                expirationDate = transaction.expirationDate
                break
            }
        }

        currentTier = foundPro ? .pro : .free
        if !foundPro {
            expirationDate = nil
        }
    }

    /// Purchase the Pro subscription
    func purchasePro() async {
        guard let product = proProduct else {
            purchaseError = "商品情報を取得できません"
            return
        }

        isPurchasing = true
        purchaseError = nil

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
