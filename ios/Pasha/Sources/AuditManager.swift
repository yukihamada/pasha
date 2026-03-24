import Foundation
import SwiftData
import CoreLocation

/// Manages audit logging, chain hashing, and Solana anchoring.
/// This is the single entry point for all compliance-related operations.
@MainActor
final class AuditManager: ObservableObject {
    static let shared = AuditManager()

    @Published var lastAnchorStatus: String = ""
    @Published var unanchoredCount: Int = 0

    private let locationManager = CLLocationManager()

    /// Record an audit log entry for a receipt action
    func log(action: String, receipt: Receipt, context: ModelContext) {
        // Get previous log hash for chain
        let previousHash = getLastLogHash(context: context)

        let entry = AuditLog(
            receiptId: receipt.id,
            action: action,
            receipt: receipt,
            previousLogHash: previousHash
        )

        context.insert(entry)
        try? context.save()

        // Update count
        updateUnanchoredCount(context: context)
    }

    /// Record deletion (receipt may already be gone, so we pass id + last known state)
    func logDeletion(receiptId: String, vendor: String, amount: Int, category: String, date: Date, context: ModelContext) {
        let previousHash = getLastLogHash(context: context)

        let entry = AuditLog(receiptId: receiptId, action: "削除", receipt: nil, previousLogHash: previousHash)
        entry.snapshotVendor = vendor
        entry.snapshotAmount = amount
        entry.snapshotCategory = category
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        entry.snapshotDate = df.string(from: date)

        context.insert(entry)
        try? context.save()

        updateUnanchoredCount(context: context)
    }

    /// Last successful on-chain transaction signature (for UI display)
    @Published var lastTxSignature: String = ""
    @Published var solBalance: Double?
    @Published var walletAddressDisplay: String = ""

    /// Anchor all unanchored logs to Solana
    func anchorToSolana(context: ModelContext) async {
        do {
            let descriptor = FetchDescriptor<AuditLog>(
                predicate: #Predicate { $0.solanaTxSignature == "" },
                sortBy: [SortDescriptor(\.timestamp)]
            )
            let unanchored = (try? context.fetch(descriptor)) ?? []

            guard !unanchored.isEmpty else {
                lastAnchorStatus = "全ログ記録済み"
                return
            }

            lastAnchorStatus = "\(unanchored.count)件をSolanaに送信中..."

            let anchorId = try await SolanaAnchor.shared.anchorBatch(unanchored, modelContext: context)

            // Update all logs with the anchor ID
            let now = Date()
            for log in unanchored {
                log.solanaTxSignature = anchorId
                log.anchoredAt = now
            }
            try? context.save()

            let isOnChain = !anchorId.hasPrefix("local_")
            if isOnChain {
                lastTxSignature = anchorId
                lastAnchorStatus = "オンチェーン記録完了"
            } else {
                lastAnchorStatus = "ローカル記録完了（RPC接続失敗）"
            }
            updateUnanchoredCount(context: context)
        } catch {
            lastAnchorStatus = "エラー: \(error.localizedDescription)"
        }
    }

    /// Fetch the current SOL balance from mainnet and wallet address
    func fetchBalance() async {
        walletAddressDisplay = await SolanaAnchor.shared.getPublicKeyBase58()
        do {
            solBalance = try await SolanaAnchor.shared.getBalance()
        } catch {
            solBalance = nil
        }
    }

    /// Get the hash of the last audit log entry (for chaining)
    private func getLastLogHash(context: ModelContext) -> String {
        var descriptor = FetchDescriptor<AuditLog>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        let last = (try? context.fetch(descriptor))?.first
        return last?.logHash ?? "GENESIS"
    }

    /// Get all audit logs for a specific receipt
    func logsForReceipt(_ receiptId: String, context: ModelContext) -> [AuditLog] {
        let descriptor = FetchDescriptor<AuditLog>(
            predicate: #Predicate { $0.receiptId == receiptId },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Verify the integrity of the entire audit chain
    func verifyChain(context: ModelContext) -> (valid: Bool, count: Int, errors: [String]) {
        let descriptor = FetchDescriptor<AuditLog>(sortBy: [SortDescriptor(\.timestamp)])
        let allLogs = (try? context.fetch(descriptor)) ?? []

        var errors: [String] = []
        var expectedPreviousHash = "GENESIS"

        for log in allLogs {
            if log.previousLogHash != expectedPreviousHash {
                errors.append("チェーン断裂: \(log.id)")
            }
            expectedPreviousHash = log.logHash
        }

        return (errors.isEmpty, allLogs.count, errors)
    }

    private func updateUnanchoredCount(context: ModelContext) {
        let descriptor = FetchDescriptor<AuditLog>(
            predicate: #Predicate { $0.solanaTxSignature == "" }
        )
        unanchoredCount = (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Get current GPS location (best effort, non-blocking)
    func getCurrentLocation() -> (latitude: Double, longitude: Double)? {
        guard CLLocationManager.locationServicesEnabled(),
              locationManager.authorizationStatus == .authorizedWhenInUse ||
              locationManager.authorizationStatus == .authorizedAlways else {
            return nil
        }
        if let loc = locationManager.location {
            return (loc.coordinate.latitude, loc.coordinate.longitude)
        }
        return nil
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
}
