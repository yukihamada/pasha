import Foundation
import UIKit
import SwiftData
import CryptoKit

@Model
final class Receipt {
    var id: String
    var imageFilename: String
    var thumbFilename: String
    var date: Date
    var vendor: String
    var amount: Int
    var category: String
    var memo: String
    var sha256Hash: String
    var createdAt: Date
    var modifiedAt: Date
    var historyJSON: String

    // Compliance fields
    var journalNumber: String      // 仕訳番号
    var chainHash: String          // Hash including previous receipt's chainHash
    var previousReceiptHash: String // Link to previous receipt for chain

    // Capture metadata
    var captureLatitude: Double    // GPS lat (0 if unavailable)
    var captureLongitude: Double   // GPS lon (0 if unavailable)
    var captureDevice: String     // Device model
    var captureResolution: String  // e.g. "4032x3024"

    // Multi-currency
    var currency: String       // ISO 4217 code (default "JPY")
    var exchangeRate: Double   // Rate to convert to JPY (default 1.0)

    /// Computed: amount converted to JPY
    var amountInJPY: Int {
        if currency == "JPY" { return amount }
        return Int(Double(amount) * exchangeRate)
    }

    // Logical deletion (never physically delete for compliance)
    var isDeleted: Bool

    private static var imageCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 50
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        return cache
    }()
    private static var thumbnailCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 100
        cache.totalCostLimit = 10 * 1024 * 1024 // 10MB
        return cache
    }()

    /// Computed: load full image data from disk (cached)
    var imageData: Data? {
        guard !imageFilename.isEmpty else { return nil }
        let key = imageFilename as NSString
        if let cached = Self.imageCache.object(forKey: key) { return cached as Data }
        guard let data = Receipt.loadImage(imageFilename) else { return nil }
        Self.imageCache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }

    /// Computed: load thumbnail data from disk (cached)
    var thumbnailData: Data? {
        guard !thumbFilename.isEmpty else { return nil }
        let key = thumbFilename as NSString
        if let cached = Self.thumbnailCache.object(forKey: key) { return cached as Data }
        guard let data = Receipt.loadImage(thumbFilename) else { return nil }
        Self.thumbnailCache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }

    init(imageData: Data?, date: Date = .now, previousChainHash: String = "") {
        let receiptId = "r_\(Int(date.timeIntervalSince1970))_\(String(UUID().uuidString.prefix(6)))"
        self.id = receiptId
        self.date = date
        self.vendor = ""
        self.amount = 0
        self.category = "その他"
        self.memo = ""
        self.createdAt = date
        self.modifiedAt = date
        self.historyJSON = "[]"
        self.journalNumber = ""
        self.previousReceiptHash = previousChainHash
        self.isDeleted = false
        self.currency = "JPY"
        self.exchangeRate = 1.0
        self.captureLatitude = 0
        self.captureLongitude = 0
        self.captureDevice = UIDevice.current.model
        self.captureResolution = ""

        // Save image and thumbnail to disk
        if let data = imageData {
            let imgName = "\(receiptId).jpg"
            let thumbName = "\(receiptId)_thumb.jpg"
            Receipt.saveImage(data, filename: imgName)
            if let thumbData = Receipt.makeThumbnail(from: data) {
                Receipt.saveImage(thumbData, filename: thumbName)
            }
            self.imageFilename = imgName
            self.thumbFilename = thumbName
        } else {
            self.imageFilename = ""
            self.thumbFilename = ""
        }

        // Compute hashes
        var computedHash = ""
        var resolution = ""
        if let data = imageData {
            computedHash = SHA256.hash(data: data).hexString
            if let img = UIImage(data: data) {
                resolution = "\(Int(img.size.width * img.scale))x\(Int(img.size.height * img.scale))"
            }
        }
        self.sha256Hash = computedHash
        self.captureResolution = resolution

        let chainInput = "\(computedHash)|\(previousChainHash)"
        self.chainHash = SHA256.hash(data: Data(chainInput.utf8)).hexString

        let entry = HistoryEntry(action: "作成", timestamp: date, hash: computedHash)
        if let json = try? JSONEncoder().encode([entry]) {
            self.historyJSON = String(data: json, encoding: .utf8) ?? "[]"
        }
    }

    var history: [HistoryEntry] {
        guard let data = historyJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    func addHistory(_ action: String) {
        var entries = history
        entries.append(HistoryEntry(action: action, timestamp: .now, hash: sha256Hash))
        if let json = try? JSONEncoder().encode(entries) {
            historyJSON = String(data: json, encoding: .utf8) ?? historyJSON
        }
        modifiedAt = .now
    }

    // MARK: - File-based image storage

    /// Directory for receipt images: Documents/receipts/
    static var receiptsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("receipts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Save image data to Documents/receipts/<filename>
    static func saveImage(_ data: Data, filename: String) {
        let url = receiptsDirectory.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
    }

    /// Load image data from Documents/receipts/<filename>
    static func loadImage(_ filename: String) -> Data? {
        let url = receiptsDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    static func makeThumbnail(from data: Data?) -> Data? {
        guard let data, let img = UIImage(data: data) else { return nil }
        let size = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        return thumb.jpegData(compressionQuality: 0.5)
    }
}

extension Receipt {
    static let supportedCurrencies = ["JPY", "USD", "EUR", "GBP", "CNY", "KRW", "THB"]

    static let currencySymbols: [String: String] = [
        "JPY": "¥", "USD": "$", "EUR": "€", "GBP": "£",
        "CNY": "¥", "KRW": "₩", "THB": "฿"
    ]

    var currencySymbol: String {
        Receipt.currencySymbols[currency] ?? "¥"
    }
}

struct HistoryEntry: Codable {
    let action: String
    let timestamp: Date
    let hash: String
}

extension Sequence where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
