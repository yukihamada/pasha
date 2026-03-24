import WidgetKit
import SwiftUI

// MARK: - Data Model

struct PashaWidgetEntry: TimelineEntry {
    let date: Date
    let totalExpenses: Int
    let receiptCount: Int
    let monthlyBudget: Int
    let topCategories: [(String, Int)]
}

// MARK: - Provider

struct PashaProvider: TimelineProvider {
    private let suiteName = "group.com.enablerdao.pasha"

    func placeholder(in context: Context) -> PashaWidgetEntry {
        PashaWidgetEntry(
            date: Date(),
            totalExpenses: 45800,
            receiptCount: 23,
            monthlyBudget: 100000,
            topCategories: [("食費", 15000), ("交通費", 8000), ("消耗品", 5000)]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PashaWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PashaWidgetEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> PashaWidgetEntry {
        let defaults = UserDefaults(suiteName: suiteName)
        let total = defaults?.integer(forKey: "widget_total_expenses") ?? 0
        let count = defaults?.integer(forKey: "widget_receipt_count") ?? 0
        let budget = defaults?.integer(forKey: "widget_monthly_budget") ?? 0

        var categories: [(String, Int)] = []
        if let data = defaults?.data(forKey: "widget_top_categories"),
           let decoded = try? JSONDecoder().decode([CategoryItem].self, from: data) {
            categories = decoded.map { ($0.name, $0.amount) }
        }

        return PashaWidgetEntry(
            date: Date(),
            totalExpenses: total,
            receiptCount: count,
            monthlyBudget: budget,
            topCategories: categories
        )
    }
}

private struct CategoryItem: Codable {
    let name: String
    let amount: Int
}

// MARK: - Views

struct PashaSmallView: View {
    let entry: PashaWidgetEntry

    private var budgetRatio: Double {
        guard entry.monthlyBudget > 0 else { return 0 }
        return min(1.0, Double(entry.totalExpenses) / Double(entry.monthlyBudget))
    }

    private var accentColor: Color {
        budgetRatio >= 1.0 ? .red : (budgetRatio >= 0.8 ? Color(red: 1, green: 0.6, blue: 0) : Color(red: 0.6, green: 0.4, blue: 1.0))
    }

    var body: some View {
        ZStack {
            Color(red: 0.059, green: 0.059, blue: 0.102)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.caption2)
                        .foregroundStyle(accentColor)
                    Text("パシャ")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Text(formatYen(entry.totalExpenses))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)

                Text("\(monthLabel())の経費")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 4) {
                    Text("\(entry.receiptCount)件")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                    if entry.monthlyBudget > 0 {
                        Spacer()
                        Text("\(Int(budgetRatio * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                if entry.monthlyBudget > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity(0.1))
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accentColor)
                                .frame(width: geo.size.width * budgetRatio, height: 3)
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(14)
        }
    }
}

struct PashaMediumView: View {
    let entry: PashaWidgetEntry

    private var budgetRatio: Double {
        guard entry.monthlyBudget > 0 else { return 0 }
        return min(1.0, Double(entry.totalExpenses) / Double(entry.monthlyBudget))
    }

    private var budgetRemaining: Int {
        max(0, entry.monthlyBudget - entry.totalExpenses)
    }

    private var accentColor: Color {
        budgetRatio >= 1.0 ? .red : (budgetRatio >= 0.8 ? Color(red: 1, green: 0.6, blue: 0) : Color(red: 0.6, green: 0.4, blue: 1.0))
    }

    var body: some View {
        ZStack {
            Color(red: 0.059, green: 0.059, blue: 0.102)
            HStack(spacing: 0) {
                // Left column: totals
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.caption2)
                            .foregroundStyle(accentColor)
                        Text("パシャ")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()

                    Text(formatYen(entry.totalExpenses))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)

                    Text("\(monthLabel())の経費 \(entry.receiptCount)件")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))

                    if entry.monthlyBudget > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.white.opacity(0.1))
                                    .frame(height: 3)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(accentColor)
                                    .frame(width: geo.size.width * budgetRatio, height: 3)
                            }
                        }
                        .frame(height: 3)

                        Text("残 \(formatYen(budgetRemaining))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(budgetRemaining == 0 ? .red : accentColor)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(14)

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)

                // Right column: top categories
                VStack(alignment: .leading, spacing: 0) {
                    Text("費目 TOP")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.bottom, 6)

                    if entry.topCategories.isEmpty {
                        Text("データなし")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.3))
                    } else {
                        ForEach(Array(entry.topCategories.prefix(3).enumerated()), id: \.offset) { _, cat in
                            HStack {
                                Text(cat.0)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                                Spacer()
                                Text(formatYen(cat.1))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.white)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(14)
            }
        }
    }
}

// MARK: - Widget

@main
struct PashaWidget: Widget {
    let kind = "PashaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PashaProvider()) { entry in
            PashaWidgetEntryView(entry: entry)
                .containerBackground(Color(red: 0.059, green: 0.059, blue: 0.102), for: .widget)
        }
        .configurationDisplayName("パシャ")
        .description("今月の経費を確認")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PashaWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: PashaWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            PashaSmallView(entry: entry)
        case .systemMedium:
            PashaMediumView(entry: entry)
        default:
            PashaSmallView(entry: entry)
        }
    }
}

// MARK: - Helpers

private func formatYen(_ amount: Int) -> String {
    if amount >= 10000 {
        let man = Double(amount) / 10000.0
        if man == Double(Int(man)) {
            return "¥\(Int(man))万"
        } else {
            return String(format: "¥%.1f万", man)
        }
    }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return "¥\(formatter.string(from: NSNumber(value: amount)) ?? "\(amount)")"
}

private func monthLabel() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "M月"
    return f.string(from: Date())
}
