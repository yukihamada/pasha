import Foundation
import SwiftData

@MainActor
struct DuplicateDetector {
    /// Check if a similar receipt already exists
    /// Match: same amount + similar date (within 3 days) + similar vendor (> 0.7)
    static func findDuplicate(amount: Int, date: Date, vendor: String, in context: ModelContext) -> Receipt? {
        guard amount > 0 else { return nil }

        let calendar = Calendar.current
        guard let threeDaysBefore = calendar.date(byAdding: .day, value: -3, to: date),
              let threeDaysAfter = calendar.date(byAdding: .day, value: 3, to: date) else {
            return nil
        }

        let descriptor = FetchDescriptor<Receipt>(
            predicate: #Predicate<Receipt> {
                $0.amount == amount && !$0.isDeleted &&
                $0.date >= threeDaysBefore && $0.date <= threeDaysAfter
            }
        )

        guard let candidates = try? context.fetch(descriptor) else { return nil }

        for candidate in candidates {
            if vendor.isEmpty || candidate.vendor.isEmpty {
                // If either vendor is empty, amount + date match is enough
                return candidate
            }
            if similarity(candidate.vendor, vendor) > 0.7 {
                return candidate
            }
        }
        return nil
    }

    /// Simple string similarity using character overlap ratio
    private static func similarity(_ a: String, _ b: String) -> Double {
        let aLower = a.lowercased()
        let bLower = b.lowercased()

        if aLower == bLower { return 1.0 }
        if aLower.isEmpty || bLower.isEmpty { return 0.0 }

        // Check containment
        if aLower.contains(bLower) || bLower.contains(aLower) { return 0.9 }

        // Character-level bigram similarity (Dice coefficient)
        let aBigrams = bigrams(aLower)
        let bBigrams = bigrams(bLower)

        guard !aBigrams.isEmpty && !bBigrams.isEmpty else { return 0.0 }

        let intersection = aBigrams.filter { bBigrams.contains($0) }.count
        return Double(2 * intersection) / Double(aBigrams.count + bBigrams.count)
    }

    private static func bigrams(_ s: String) -> [String] {
        let chars = Array(s)
        guard chars.count >= 2 else { return [s] }
        return (0..<chars.count - 1).map { String(chars[$0...$0+1]) }
    }
}
