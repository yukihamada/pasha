import Foundation
import SwiftData
import CryptoKit

/// Immutable audit log entry — independent of Receipt so deletion history survives.
/// Each entry chains to the previous via `previousLogHash` forming a tamper-evident chain.
/// Optionally anchored to Solana blockchain for public verifiability.
@Model
final class AuditLog {
    var id: String
    var receiptId: String
    var action: String          // 作成, 日付変更, 金額変更, 削除, etc.
    var timestamp: Date
    var dataHash: String        // SHA-256 of receipt state at this point
    var previousLogHash: String // Chain hash — hash of the previous AuditLog entry
    var logHash: String         // SHA-256(action + timestamp + dataHash + previousLogHash)

    // Solana anchoring
    var solanaTxSignature: String  // Solana transaction signature (empty until anchored)
    var solanaSlot: Int            // Solana slot number (0 until anchored)
    var anchoredAt: Date?         // When the hash was anchored on-chain

    // Snapshot of key fields at this point (for audit trail)
    var snapshotVendor: String
    var snapshotAmount: Int
    var snapshotCategory: String
    var snapshotDate: String     // yyyy-MM-dd

    init(receiptId: String, action: String, receipt: Receipt?, previousLogHash: String) {
        let now = Date()
        let vendor = receipt?.vendor ?? ""
        let amount = receipt?.amount ?? 0
        let category = receipt?.category ?? ""
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: receipt?.date ?? now)
        let imageHash = receipt?.sha256Hash ?? ""

        // Compute hashes before assigning any stored properties
        let stateString = "\(receiptId)|\(dateStr)|\(amount)|\(vendor)|\(category)|\(imageHash)"
        let computedDataHash = SHA256.hash(data: Data(stateString.utf8)).hexString
        let chainInput = "\(action)|\(now.timeIntervalSince1970)|\(computedDataHash)|\(previousLogHash)"
        let computedLogHash = SHA256.hash(data: Data(chainInput.utf8)).hexString

        // Now assign all stored properties
        self.id = "log_\(Int(now.timeIntervalSince1970))_\(String(UUID().uuidString.prefix(4)))"
        self.receiptId = receiptId
        self.action = action
        self.timestamp = now
        self.previousLogHash = previousLogHash
        self.solanaTxSignature = ""
        self.solanaSlot = 0
        self.anchoredAt = nil
        self.snapshotVendor = vendor
        self.snapshotAmount = amount
        self.snapshotCategory = category
        self.snapshotDate = dateStr
        self.dataHash = computedDataHash
        self.logHash = computedLogHash
    }

    var isAnchored: Bool { !solanaTxSignature.isEmpty }
}
