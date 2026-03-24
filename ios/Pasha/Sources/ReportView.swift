import SwiftUI
import SwiftData
import Charts

// MARK: - Report View

struct ReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Receipt> { !$0.isDeleted }, sort: \Receipt.date, order: .reverse)
    private var allReceipts: [Receipt]
    @State private var currentMonth = Date()
    @State private var selectedCategory: String?
    @State private var monthReceipts: [Receipt] = []
    @State private var lastMonthReceipts: [Receipt] = []

    private var cal: Calendar { Calendar.current }

    private var lastMonthDate: Date {
        cal.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }

    private var monthTotal: Int { monthReceipts.reduce(0) { $0 + $1.amountInJPY } }
    private var lastMonthTotal: Int { lastMonthReceipts.reduce(0) { $0 + $1.amountInJPY } }

    private var changePercent: Double? {
        guard lastMonthTotal > 0 else { return nil }
        return Double(monthTotal - lastMonthTotal) / Double(lastMonthTotal) * 100
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f
    }()

    private var monthLabel: String {
        Self.monthFormatter.string(from: currentMonth)
    }

    // Category breakdown
    private var categoryData: [CategorySlice] {
        let grouped = Dictionary(grouping: monthReceipts) { $0.category }
        let total = max(monthTotal, 1)
        return grouped.map { key, receipts in
            let sum = receipts.reduce(0) { $0 + $1.amountInJPY }
            return CategorySlice(
                category: key,
                amount: sum,
                percentage: Double(sum) / Double(total) * 100
            )
        }.sorted { $0.amount > $1.amount }
    }

    // Daily spending
    private var dailyData: [DailySpending] {
        guard let range = cal.range(of: .day, in: .month, for: currentMonth) else { return [] }
        let grouped = Dictionary(grouping: monthReceipts) { cal.component(.day, from: $0.date) }
        return range.map { day in
            let amount = grouped[day]?.reduce(0) { $0 + $1.amountInJPY } ?? 0
            return DailySpending(day: day, amount: amount)
        }
    }

    // Top 5 expenses
    private var topExpenses: [Receipt] {
        Array(monthReceipts.sorted { $0.amountInJPY > $1.amountInJPY }.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Month navigation
                    monthNavigationView

                    // Monthly summary header
                    summaryHeader

                    // Category pie chart
                    if !categoryData.isEmpty {
                        categoryChart
                    }

                    // Daily bar chart
                    if !dailyData.isEmpty {
                        dailyChart
                    }

                    // Top 5 expenses
                    if !topExpenses.isEmpty {
                        topExpensesSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 90)
            }
            .background(Color.pashaBg)
            .navigationTitle("レポート")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { fetchMonthData() }
            .onChange(of: currentMonth) { _, _ in fetchMonthData() }
            .onChange(of: allReceipts.count) { _, _ in fetchMonthData() }
        }
    }

    private func fetchMonthData() {
        // Fetch current month
        if let interval = cal.dateInterval(of: .month, for: currentMonth) {
            let start = interval.start
            let end = interval.end
            var descriptor = FetchDescriptor<Receipt>(
                predicate: #Predicate<Receipt> {
                    !$0.isDeleted && $0.date >= start && $0.date < end
                },
                sortBy: [SortDescriptor(\Receipt.date, order: .reverse)]
            )
            monthReceipts = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            monthReceipts = []
        }

        // Fetch last month
        if let interval = cal.dateInterval(of: .month, for: lastMonthDate) {
            let start = interval.start
            let end = interval.end
            var descriptor = FetchDescriptor<Receipt>(
                predicate: #Predicate<Receipt> {
                    !$0.isDeleted && $0.date >= start && $0.date < end
                },
                sortBy: [SortDescriptor(\Receipt.date, order: .reverse)]
            )
            lastMonthReceipts = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            lastMonthReceipts = []
        }
    }

    // MARK: - Month Navigation

    private var monthNavigationView: some View {
        HStack {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2).symbolRenderingMode(.hierarchical)
            }
            Spacer()
            Text(monthLabel)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Spacer()
            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2).symbolRenderingMode(.hierarchical)
            }
        }
        .foregroundStyle(Color.pasha)
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        VStack(spacing: 12) {
            Text("¥\(monthTotal.formatted())")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Color.pashaWarn)

            HStack(spacing: 16) {
                Label("\(monthReceipts.count)件", systemImage: "doc.text.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if let pct = changePercent {
                    HStack(spacing: 4) {
                        Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(String(format: "%@%.0f%%", pct >= 0 ? "+" : "", pct))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pct >= 0 ? Color.pashaAccent : Color.pashaSuccess)
                } else {
                    Text("先月データなし")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .glassCard()
    }

    // MARK: - Category Pie Chart

    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリ別")
                .font(.headline)
                .foregroundStyle(.primary)

            Chart(categoryData) { slice in
                SectorMark(
                    angle: .value("金額", slice.amount),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(slice.color)
                .opacity(selectedCategory == nil || selectedCategory == slice.category ? 1.0 : 0.4)
            }
            .chartAngleSelection(value: $selectedCategory)
            .frame(height: 220)

            // Legend
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(categoryData) { slice in
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            selectedCategory = selectedCategory == slice.category ? nil : slice.category
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(slice.color)
                                .frame(width: 10, height: 10)
                            Text(slice.category)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.0f%%", slice.percentage))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Selected detail
            if let sel = selectedCategory, let slice = categoryData.first(where: { $0.category == sel }) {
                HStack {
                    Text(slice.category)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("¥\(slice.amount.formatted())")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.pashaWarn)
                }
                .padding(10)
                .background(Color.pasha.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .transition(.opacity)
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Daily Bar Chart

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("日別支出")
                .font(.headline)
                .foregroundStyle(.primary)

            Chart(dailyData) { item in
                BarMark(
                    x: .value("日", item.day),
                    y: .value("金額", item.amount)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.pasha, .pashaAccent],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(3)
            }
            .chartXAxisLabel("日", position: .bottom)
            .chartYAxisLabel("円", position: .leading)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(v >= 10000 ? "\(v / 10000)万" : "\(v)")
                                .font(.system(size: 9))
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 5)) { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Top 5 Expenses

    private var topExpensesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("高額TOP 5")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(Array(topExpenses.enumerated()), id: \.element.id) { index, receipt in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(index == 0 ? Color.pashaWarn : .secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(receipt.vendor.isEmpty ? "未入力" : receipt.vendor)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(formatDay(receipt.date))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(receipt.category)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.pasha.opacity(0.12))
                                .foregroundStyle(Color.pasha)
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    Text("¥\(receipt.amountInJPY.formatted())")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.pashaWarn)
                }
                .padding(.vertical, 6)

                if index < topExpenses.count - 1 {
                    Divider().opacity(0.3)
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Helpers

    private func changeMonth(_ delta: Int) {
        withAnimation(.spring(duration: 0.3)) {
            currentMonth = cal.date(byAdding: .month, value: delta, to: currentMonth) ?? currentMonth
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    private func formatDay(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }
}

// MARK: - Data Models

struct CategorySlice: Identifiable {
    let id = UUID()
    let category: String
    let amount: Int
    let percentage: Double

    var color: Color {
        let colors: [Color] = [
            .pasha, .pashaAccent, .pashaSuccess, .pashaWarn,
            .solana, .cyan, .orange, .mint, .indigo, .pink
        ]
        let hash = abs(category.hashValue)
        return colors[hash % colors.count]
    }
}

struct DailySpending: Identifiable {
    var id: Int { day }
    let day: Int
    let amount: Int
}
