import Foundation
import SwiftData

@Model
final class CustomCategory {
    var id: String = ""
    var name: String = ""
    var sortOrder: Int = 0

    init(name: String, sortOrder: Int) {
        self.id = UUID().uuidString
        self.name = name
        self.sortOrder = sortOrder
    }

    /// Default categories to seed on first launch
    static let defaults = ["食費", "交通費", "消耗品費", "交際費", "通信費", "家賃", "水道光熱費", "旅費", "雑費", "その他"]

    /// Seed defaults if the store is empty
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<CustomCategory>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        for (index, name) in defaults.enumerated() {
            let cat = CustomCategory(name: name, sortOrder: index)
            context.insert(cat)
        }
        try? context.save()
    }
}
