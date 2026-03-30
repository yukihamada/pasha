import SwiftUI
import SwiftData
import WidgetKit

struct HomeView: View {
    @Binding var showCamera: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query(filter: #Predicate<Receipt> { !$0.isDeleted }, sort: \Receipt.date, order: .reverse)
    private var allReceipts: [Receipt]
    @State private var currentMonth = Date()
    @State private var monthReceipts: [Receipt] = []
    @AppStorage("monthlyBudget") private var monthlyBudget: Int = 0

    private var monthTotal: Int { monthReceipts.reduce(0) { $0 + $1.amountInJPY } }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f
    }()

    private var monthLabel: String {
        Self.monthFormatter.string(from: currentMonth)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Usage banner
                    if subscriptionManager.currentTier == .free {
                        if !subscriptionManager.canAddReceipt {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.pashaWarn)
                                Text("今月の登録枠を使い切りました")
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text("アップグレード")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.pasha)
                            }
                            .padding(12)
                            .background(Color.pashaWarn.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "camera.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Color.pasha)
                                Text("今月 \(subscriptionManager.monthlyReceiptCount)件登録済み")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(10)
                            .glassCard()
                        }
                    }

                    // Stats — glass cards
                    HStack(spacing: 10) {
                        StatCard(value: "\(monthReceipts.count)", label: "件数", color: .pasha)
                        StatCard(value: "¥\(monthTotal.formatted())", label: "合計", color: .pashaWarn)
                        StatCard(value: "\(allReceipts.count)", label: "全件", color: .pashaSuccess)
                    }

                    // Budget progress
                    if monthlyBudget > 0 {
                        let ratio = Double(monthTotal) / Double(monthlyBudget)
                        let budgetColor: Color = ratio >= 1.0 ? .red : (ratio >= 0.8 ? .pashaWarn : .pashaSuccess)
                        let exceeded = monthTotal > monthlyBudget

                        VStack(spacing: 8) {
                            if exceeded {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text("予算を超過しています")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.red)
                                    Spacer()
                                }
                            }
                            HStack {
                                Text("予算")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\u{00a5}\(monthTotal.formatted()) / \u{00a5}\(monthlyBudget.formatted())")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(budgetColor)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(height: 8)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(budgetColor)
                                        .frame(width: min(geo.size.width, geo.size.width * ratio), height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                        .padding(12)
                        .glassCard()
                    }

                    // Month nav
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

                    // Receipt list
                    if monthReceipts.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 52, weight: .thin))
                                .foregroundStyle(Color.pasha.opacity(0.3))
                            Text("レシートがありません")
                                .font(.headline).foregroundStyle(.secondary)
                            Text("撮影ボタンで追加")
                                .font(.subheadline).foregroundStyle(.tertiary)
                        }
                        .padding(.top, 50)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(monthReceipts, id: \.id) { receipt in
                                NavigationLink {
                                    ReceiptDetailView(receipt: receipt)
                                } label: {
                                    ReceiptRow(receipt: receipt)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 90)
            }
            .background(Color.pashaBg)
            .navigationTitle("パシャ")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let csv = generateCSV()
                        let av = UIActivityViewController(activityItems: [csv], applicationActivities: nil)
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root = scene.windows.first?.rootViewController {
                            root.present(av, animated: true)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .onAppear { fetchMonthReceipts() }
            .onChange(of: currentMonth) { _, _ in fetchMonthReceipts() }
            .onChange(of: allReceipts.count) { _, _ in fetchMonthReceipts() }
        }
    }

    private func fetchMonthReceipts() {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .month, for: currentMonth) else {
            monthReceipts = []
            return
        }
        let startDate = start.start
        let endDate = start.end
        var descriptor = FetchDescriptor<Receipt>(
            predicate: #Predicate<Receipt> {
                !$0.isDeleted && $0.date >= startDate && $0.date < endDate
            },
            sortBy: [SortDescriptor(\Receipt.date, order: .reverse)]
        )
        monthReceipts = (try? modelContext.fetch(descriptor)) ?? []
        updateWidgetData()
    }

    private func updateWidgetData() {
        guard let defaults = UserDefaults(suiteName: "group.com.enablerdao.pasha") else { return }
        let total = monthReceipts.reduce(0) { $0 + $1.amountInJPY }
        defaults.set(total, forKey: "widget_total_expenses")
        defaults.set(monthReceipts.count, forKey: "widget_receipt_count")
        defaults.set(monthlyBudget, forKey: "widget_monthly_budget")

        // Top categories
        var catMap: [String: Int] = [:]
        for r in monthReceipts { catMap[r.category, default: 0] += r.amountInJPY }
        let top3 = catMap.sorted { $0.value > $1.value }.prefix(3)
        struct CatItem: Codable { let name: String; let amount: Int }
        let items = top3.map { CatItem(name: $0.key, amount: $0.value) }
        if let encoded = try? JSONEncoder().encode(items) {
            defaults.set(encoded, forKey: "widget_top_categories")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "PashaWidget")
    }

    private func changeMonth(_ delta: Int) {
        withAnimation(.spring(duration: 0.3)) {
            currentMonth = Calendar.current.date(byAdding: .month, value: delta, to: currentMonth) ?? currentMonth
        }
    }

    private func generateCSV() -> String {
        var csv = "\u{FEFF}日付,取引先,金額,通貨,為替レート,JPY金額,勘定科目,仕訳番号,メモ,SHA-256,チェーンハッシュ\n"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for r in allReceipts {
            csv += "\(df.string(from: r.date)),\"\(r.vendor)\",\(r.amount),\(r.currency),\(r.exchangeRate),\(r.amountInJPY),\(r.category),\(r.journalNumber),\"\(r.memo)\",\(r.sha256Hash),\(r.chainHash)\n"
        }
        return csv
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let value: String
    let label: String
    var color: Color = .pasha

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassCard()
    }
}

// MARK: - Receipt Row

struct ReceiptRow: View {
    let receipt: Receipt

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    private var dateStr: String {
        Self.dateFormatter.string(from: receipt.date)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail with subtle border
            Group {
                if let data = receipt.thumbnailData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.pashaCard
                        .overlay { Image(systemName: "doc.text").foregroundStyle(.quaternary) }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06)))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.vendor.isEmpty ? "未入力" : receipt.vendor)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(dateStr)
                        .font(.caption).foregroundStyle(.tertiary)
                    Text(receipt.category)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.pasha.opacity(0.12))
                        .foregroundStyle(Color.pasha)
                        .clipShape(Capsule())
                    if !receipt.journalNumber.isEmpty {
                        Text(receipt.journalNumber)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.solana)
                    }
                }
            }

            Spacer(minLength: 4)

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(receipt.currencySymbol)\(receipt.amount.formatted())")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.pashaWarn)
                if receipt.currency != "JPY" {
                    Text("¥\(receipt.amountInJPY.formatted())")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .glassCard()
    }
}
