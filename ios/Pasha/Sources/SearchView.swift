import SwiftUI
import SwiftData

struct SearchView: View {
    @Query(filter: #Predicate<Receipt> { !$0.isDeleted }, sort: \Receipt.date, order: .reverse)
    private var allReceipts: [Receipt]
    @State private var query = ""
    @State private var minAmount = ""
    @State private var maxAmount = ""
    @State private var showFilters = false

    private var results: [Receipt] {
        var filtered = allReceipts

        // Text search
        if !query.isEmpty {
            let q = query.lowercased()
            filtered = filtered.filter {
                $0.vendor.lowercased().contains(q) ||
                $0.memo.lowercased().contains(q) ||
                $0.category.contains(q) ||
                $0.journalNumber.lowercased().contains(q) ||
                "\($0.amount)".contains(q) ||
                $0.date.formatted(date: .numeric, time: .omitted).contains(q)
            }
        }

        // Amount range filter
        if let min = Int(minAmount) { filtered = filtered.filter { $0.amount >= min } }
        if let max = Int(maxAmount) { filtered = filtered.filter { $0.amount <= max } }

        return query.isEmpty && minAmount.isEmpty && maxAmount.isEmpty ? [] : filtered
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("取引先・金額・仕訳番号・メモで検索...", text: $query)
                            .textFieldStyle(.plain)
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                        Button { withAnimation { showFilters.toggle() } } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle\(showFilters ? ".fill" : "")")
                                .foregroundStyle(showFilters ? Color(hex: "4CC9F0") : .secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(hex: "16213E"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if showFilters {
                        HStack(spacing: 8) {
                            HStack {
                                Text("¥").foregroundStyle(.secondary).font(.caption)
                                TextField("最小金額", text: $minAmount)
                                    .keyboardType(.numberPad).font(.caption)
                            }
                            .padding(8)
                            .background(Color(hex: "16213E"))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text("〜").foregroundStyle(.secondary)

                            HStack {
                                Text("¥").foregroundStyle(.secondary).font(.caption)
                                TextField("最大金額", text: $maxAmount)
                                    .keyboardType(.numberPad).font(.caption)
                            }
                            .padding(8)
                            .background(Color(hex: "16213E"))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding()

                if results.isEmpty && (query.isEmpty && minAmount.isEmpty && maxAmount.isEmpty) {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40)).foregroundStyle(.quaternary)
                        Text("検索条件を入力").font(.headline)
                        Text("取引先・金額・日付・仕訳番号で検索")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                } else if results.isEmpty {
                    Spacer()
                    Text("該当なし").font(.headline).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(results, id: \.id) { receipt in
                                NavigationLink {
                                    ReceiptDetailView(receipt: receipt)
                                } label: {
                                    ReceiptRow(receipt: receipt)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 80)
                    }
                }
            }
            .background(Color(hex: "0F0F1A"))
            .navigationTitle("検索")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
