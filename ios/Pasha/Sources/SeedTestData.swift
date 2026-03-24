import SwiftData
import Foundation

/// Seed realistic test data for App Store screenshots
struct SeedTestData {
    static func seed(context: ModelContext) {
        // Check if already seeded
        let descriptor = FetchDescriptor<Receipt>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        if count > 3 { return } // already has data

        let entries: [(String, Int, String, String, Int)] = [
            // (vendor, amount, category, dateOffset days ago, daysAgo)
            ("ドトール 渋谷店", 780, "交際費", "2026-03-18", 0),
            ("JR東日本 新宿駅", 580, "交通費", "2026-03-18", 0),
            ("ヨドバシカメラ 新宿西口", 12800, "消耗品費", "2026-03-17", 1),
            ("Uber Eats", 2340, "食費", "2026-03-17", 1),
            ("Amazon.co.jp", 5980, "消耗品費", "2026-03-16", 2),
            ("スターバックス 丸の内", 1280, "交際費", "2026-03-15", 3),
            ("タクシー", 3200, "交通費", "2026-03-14", 4),
            ("セブンイレブン 神保町", 450, "消耗品費", "2026-03-14", 4),
            ("ローソン 大手町", 620, "食費", "2026-03-13", 5),
            ("丸善 丸の内本店", 2750, "消耗品費", "2026-03-12", 6),
            ("ファミリーマート 銀座", 380, "食費", "2026-03-11", 7),
            ("モスバーガー 渋谷", 890, "食費", "2026-03-10", 8),
        ]

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        var prevHash = "GENESIS"
        for (vendor, amount, category, dateStr, _) in entries {
            let date = df.date(from: dateStr) ?? Date()
            let receipt = Receipt(imageData: nil, date: date, previousChainHash: prevHash)
            receipt.vendor = vendor
            receipt.amount = amount
            receipt.category = category
            receipt.addHistory("テストデータ")
            prevHash = receipt.chainHash
            context.insert(receipt)
        }

        try? context.save()
    }
}
