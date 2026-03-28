import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var allReceipts: [Receipt]
    @Query(sort: \CustomCategory.sortOrder) private var customCategories: [CustomCategory]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.auditModelContext) private var auditModelContext
    @EnvironmentObject private var auditManager: AuditManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @ObservedObject private var vlmManager = VLMManager.shared
    @State private var showDeleteAlert = false
    @State private var chainVerification = ""
    @State private var isAnchoring = false
    @State private var verificationProofJSON = "{}"
    @State private var newCategoryName = ""
    @State private var allLogs: [AuditLog] = []
    @AppStorage("monthlyBudget") private var monthlyBudget: Int = 0
    @State private var budgetInput: String = ""
    @State private var showServerModeAlert = false
    @State private var showCellularDownloadAlert = false

    private var anchoredCount: Int { allLogs.filter { $0.isAnchored }.count }
    private var activeCount: Int { allReceipts.filter { !$0.isDeleted }.count }
    private var deletedCount: Int { allReceipts.filter { $0.isDeleted }.count }

    /// The ModelContext to use for audit log operations (separate local-only store)
    private var auditContext: ModelContext {
        auditModelContext ?? modelContext
    }

    var body: some View {
        NavigationStack {
            List {
                // Plan
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.title3)
                            .foregroundStyle(subscriptionManager.currentTier == .free ? .secondary : Color.pashaWarn)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("現在のプラン: \(subscriptionManager.tierDisplayName)")
                                .font(.subheadline.weight(.medium))
                            if subscriptionManager.currentTier == .free {
                                Text("月\(subscriptionManager.freeMonthlyLimit)件まで無料")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(subscriptionManager.subscriptionStatusText)
                                    .font(.caption).foregroundStyle(Color.pashaSuccess)
                            }
                        }
                        Spacer()
                    }

                    if subscriptionManager.currentTier == .free {
                        Button {
                            Task { await subscriptionManager.purchasePro() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Proプランに登録")
                                        .font(.subheadline.weight(.semibold))
                                    Text("無制限 + 電子帳簿保存法 + ブロックチェーン記録")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if subscriptionManager.isPurchasing || subscriptionManager.proProduct == nil {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text(subscriptionManager.formattedPrice)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color.pasha)
                                }
                            }
                        }
                        .disabled(subscriptionManager.isPurchasing || subscriptionManager.proProduct == nil)

                        Button {
                            Task { await subscriptionManager.restorePurchases() }
                        } label: {
                            Label("購入を復元", systemImage: "arrow.clockwise")
                                .font(.subheadline)
                        }
                        .disabled(subscriptionManager.isPurchasing)
                    } else {
                        Text("サブスクリプションの管理はiOSの設定アプリから行えます")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    if let error = subscriptionManager.purchaseError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Label("プラン", systemImage: "crown")
                }

                // Data Storage
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone")
                            .font(.title3)
                            .foregroundStyle(Color.pasha)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ローカル保存").font(.subheadline.weight(.medium))
                            Text("レシートデータはすべて端末内に保存されます")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title3)
                            .foregroundStyle(Color.pashaSuccess)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("監査ログはローカル専用")
                                .font(.subheadline.weight(.medium))
                            Text("改ざん防止のため、監査ログはクラウド同期の対象外です")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("データ保存", systemImage: "internaldrive")
                } footer: {
                    Text("iCloud同期は今後のアップデートで対応予定です。現在はすべてのデータが端末内にのみ保存されます。")
                        .font(.caption2)
                }

                // Compliance
                Section {
                    if subscriptionManager.hasComplianceFeatures {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill").font(.title3).foregroundStyle(Color.pashaSuccess)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("電子帳簿保存法対応").font(.subheadline.weight(.medium))
                                Text("チェーンハッシュ + 監査ログ + Merkle検証").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath").font(.title3).foregroundStyle(Color.pasha)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("監査ログ \(allLogs.count)件").font(.subheadline.weight(.medium))
                                Text("うち\(anchoredCount)件 Merkle記録済み").font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            let result = auditManager.verifyChain(context: auditContext)
                            chainVerification = result.valid
                                ? "OK: \(result.count)件、改ざんなし"
                                : "NG: \(result.errors.count)件の不整合"
                        } label: {
                            Label("チェーン整合性を検証", systemImage: "checkmark.circle")
                        }

                        if !chainVerification.isEmpty {
                            Label(chainVerification,
                                  systemImage: chainVerification.contains("OK") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(chainVerification.contains("OK") ? Color.pashaSuccess : Color.red)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill").font(.title3).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("電子帳簿保存法対応").font(.subheadline.weight(.medium))
                                Text("Proプランで監査ログ・チェーン検証を利用可能")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("コンプライアンス") }

                // Blockchain
                Section {
                    if subscriptionManager.hasComplianceFeatures {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("未記録: \(auditManager.unanchoredCount)件")
                                    .font(.subheadline.weight(.medium))
                                if !auditManager.lastAnchorStatus.isEmpty {
                                    Text(auditManager.lastAnchorStatus)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                isAnchoring = true
                                Task {
                                    await auditManager.anchorToSolana(context: auditContext)
                                    await auditManager.fetchBalance()
                                    isAnchoring = false
                                    fetchAuditLogs()
                                }
                            } label: {
                                Group {
                                    if isAnchoring {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("記録", systemImage: "lock.shield")
                                    }
                                }
                                .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered).tint(Color.solana)
                            .disabled(isAnchoring || auditManager.unanchoredCount == 0)
                        }

                        // Last on-chain tx signature with Explorer link
                        if !auditManager.lastTxSignature.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("最新トランザクション")
                                    .font(.caption).foregroundStyle(.secondary)
                                Link(destination: URL(string: "https://explorer.solana.com/tx/\(auditManager.lastTxSignature)")!) {
                                    HStack(spacing: 4) {
                                        Text(String(auditManager.lastTxSignature.prefix(20)) + "...")
                                            .font(.system(size: 10, design: .monospaced))
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(Color.solana)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Solanaウォレット")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if let balance = auditManager.solBalance {
                                    Text(String(format: "%.4f SOL", balance))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color.solana)
                                }
                            }
                            Text(auditManager.walletAddressDisplay)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color.solana).textSelection(.enabled)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill").font(.title3).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Solanaブロックチェーン").font(.subheadline.weight(.medium))
                                Text("Proプラン ¥980/月でオンチェーン記録を利用可能")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("ブロックチェーン", systemImage: "link")
                }

                // AI Engine
                Section {
                    // Provider picker
                    Picker(selection: Binding(
                        get: { vlmManager.selectedProvider },
                        set: { newProvider in
                            vlmManager.selectedProvider = newProvider
                            vlmManager.userApiKey = vlmManager.apiKey(for: newProvider)
                            vlmManager.serverModeEnabled = true
                        }
                    )) {
                        ForEach(VLMManager.AIProvider.allCases) { provider in
                            HStack {
                                Text(provider.displayName)
                                if !vlmManager.apiKey(for: provider).isEmpty || !provider.needsApiKey {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.pashaSuccess)
                                        .font(.caption)
                                }
                            }
                            .tag(provider)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "brain")
                                .font(.title3)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.pasha, Color.pashaAccent],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AIプロバイダー")
                                    .font(.subheadline.weight(.medium))
                                Text(vlmManager.selectedProvider.visionModel)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    // API key input
                    if vlmManager.selectedProvider.needsApiKey {
                        HStack {
                            SecureField(vlmManager.selectedProvider.placeholder, text: Binding(
                                get: { vlmManager.apiKey(for: vlmManager.selectedProvider) },
                                set: { vlmManager.setApiKey($0, for: vlmManager.selectedProvider) }
                            ))
                            .font(.system(size: 14, design: .monospaced))
                            .textContentType(.password)
                            .autocorrectionDisabled()

                            if !vlmManager.apiKey(for: vlmManager.selectedProvider).isEmpty {
                                Button {
                                    vlmManager.setApiKey("", for: vlmManager.selectedProvider)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Status
                    HStack {
                        if vlmManager.hasValidKey && vlmManager.serverModeEnabled {
                            Label("AI解析: 有効", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(Color.pashaSuccess)
                        } else if !vlmManager.hasValidKey {
                            Label("APIキーを入力してください", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(Color.pashaWarn)
                        } else {
                            Label("AI解析: 無効（設定でONにしてください）", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    // Cloud toggle
                    Toggle(isOn: Binding(
                        get: { vlmManager.serverModeEnabled },
                        set: { newValue in
                            if newValue {
                                showServerModeAlert = true
                            } else {
                                vlmManager.serverModeEnabled = false
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("クラウドAI解析")
                                .font(.subheadline.weight(.medium))
                            Text("撮影時にAIが自動で金額・日付・取引先を判定")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color.pasha)

                    // Local model download
                    switch vlmManager.status {
                    case .notDownloaded:
                        Button {
                            if vlmManager.isCellular {
                                showCellularDownloadAlert = true
                            } else {
                                vlmManager.downloadModel()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("オフライン用モデルをダウンロード")
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(vlmManager.modelSizeLabel) \u{2022} オフラインでも高精度解析が可能に")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.pasha)
                            }
                        }
                    case .downloading(let progress):
                        VStack(spacing: 8) {
                            ProgressView(value: progress).tint(Color.pasha)
                            HStack {
                                Text("ダウンロード中... \(Int(progress * 100))%")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("キャンセル") { vlmManager.cancelDownload() }
                                    .font(.caption).foregroundStyle(.red)
                            }
                        }
                    case .downloaded:
                        HStack {
                            if let size = vlmManager.modelFileSizeOnDisk {
                                Text("ディスク使用量: \(size)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { vlmManager.deleteModel() } label: {
                                Text("削除").font(.caption)
                            }
                        }
                    case .analyzing:
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("解析中...").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("AI解析エンジン", systemImage: "cpu")
                } footer: {
                    Text("Geminiはデフォルトキー付き（無料）。OpenAI/Anthropic/Groqは自分のAPIキーを設定すると利用可能。chatweb.aiはキー不要（精度低め）。")
                        .font(.caption2)
                }

                // Monthly Budget
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "yensign.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.pashaWarn)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("月間予算")
                                .font(.subheadline.weight(.medium))
                            if monthlyBudget > 0 {
                                Text("現在: \u{00a5}\(monthlyBudget.formatted())")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("未設定")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        TextField("予算額を入力", text: $budgetInput)
                            .keyboardType(.numberPad)
                            .font(.body)
                        Button {
                            if let value = Int(budgetInput), value >= 0 {
                                monthlyBudget = value
                                budgetInput = ""
                            }
                        } label: {
                            Text("設定")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.pasha)
                        }
                        .disabled(budgetInput.isEmpty)
                    }
                    if monthlyBudget > 0 {
                        Button(role: .destructive) {
                            monthlyBudget = 0
                        } label: {
                            Text("予算をリセット")
                                .font(.caption)
                        }
                    }
                } header: {
                    Label("予算管理", systemImage: "chart.bar")
                }

                // Category Management
                Section {
                    ForEach(customCategories, id: \.id) { cat in
                        Text(cat.name)
                    }
                    .onDelete(perform: deleteCategories)
                    .onMove(perform: moveCategories)

                    HStack {
                        TextField("新しいカテゴリ名", text: $newCategoryName)
                        Button {
                            addCategory()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.pasha)
                        }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Label("カテゴリ管理", systemImage: "tag")
                }

                // Data
                Section {
                    Label("\(activeCount)件のレシート（削除済み\(deletedCount)件）", systemImage: "doc.text")
                        .font(.subheadline)
                } header: {
                    Label("データ", systemImage: "cylinder")
                }

                // Send to Sakutsu
                Section {
                    Button {
                        sendToSakutsu()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color(hex: "3B82F6"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("サクッに送る")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("確定申告アプリに経費データを送信")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Label("姉妹アプリ連携", systemImage: "arrow.triangle.2.circlepath")
                } footer: {
                    Text("パシャの経費データをサクッ（確定申告）に送って、経費として反映できます。")
                }

                // Export
                Section {
                    Button { shareText(generateCSV()) } label: {
                        Label("CSVエクスポート", systemImage: "tablecells")
                    }
                    if subscriptionManager.hasExportFeatures {
                        Button { shareText(generateFreeeCSV()) } label: {
                            Label("freee互換CSV", systemImage: "tablecells")
                        }
                        Button { shareText(generateMoneyForwardCSV()) } label: {
                            Label("MoneyForward互換CSV", systemImage: "tablecells")
                        }
                        Button { shareText(generateAuditJSON()) } label: {
                            Label("監査ログ", systemImage: "doc.badge.clock")
                        }
                        Button { shareText(verificationProofJSON) } label: {
                            Label("Merkle検証プルーフ", systemImage: "checkmark.seal")
                        }
                    } else {
                        HStack {
                            Label("freee互換CSV", systemImage: "lock.fill")
                            Spacer()
                            Text("Pro").font(.caption2).foregroundStyle(Color.pasha)
                        }
                        .foregroundStyle(.secondary)
                        HStack {
                            Label("MoneyForward互換CSV", systemImage: "lock.fill")
                            Spacer()
                            Text("Pro").font(.caption2).foregroundStyle(Color.pasha)
                        }
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("エクスポート", systemImage: "square.and.arrow.up")
                }

                // About
                Section {
                    VStack(spacing: 6) {
                        Text("パシャ")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.pasha)
                        Text("v2.0 — 撮って、終わり。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("電子帳簿保存法対応 + Solanaブロックチェーン検証")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .listRowBackground(Color.clear)

                    Link(destination: URL(string: "https://pasha.run/privacy.html")!) {
                        Label("プライバシーポリシー", systemImage: "hand.raised.fill")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.pashaBg)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                EditButton()
            }
            .alert("クラウドAI解析を有効にしますか？", isPresented: $showServerModeAlert) {
                Button("有効にする") {
                    vlmManager.serverModeEnabled = true
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("レシート画像が\(vlmManager.selectedProvider.displayName)のAPIに送信され、AI解析が行われます。送信されたデータはレシート解析のみに使用されます。")
            }
            .alert("モバイルデータ通信で大容量ダウンロード", isPresented: $showCellularDownloadAlert) {
                Button("ダウンロード") {
                    vlmManager.downloadModel()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("AIモデル（\(vlmManager.modelSizeLabel)）をモバイルデータ通信でダウンロードします。Wi-Fi環境でのダウンロードを推奨します。")
            }
            .task {
                verificationProofJSON = await SolanaAnchor.shared.exportVerificationProof()
                await auditManager.fetchBalance()
                fetchAuditLogs()
            }
        }
    }

    private func fetchAuditLogs() {
        let descriptor = FetchDescriptor<AuditLog>(sortBy: [SortDescriptor(\.timestamp)])
        allLogs = (try? auditContext.fetch(descriptor)) ?? []
    }

    // MARK: - Send to Sakutsu

    private func sendToSakutsu() {
        let active = allReceipts.filter { !$0.isDeleted }
        let totalExpenses = active.reduce(0) { $0 + $1.amountInJPY }

        var byCategory: [String: Int] = [:]
        for r in active {
            byCategory[r.category, default: 0] += r.amountInJPY
        }

        let data: [String: Any] = [
            "app": "pasha",
            "type": "expense",
            "totalExpenses": totalExpenses,
            "byCategory": byCategory,
            "count": active.count,
            "year": Calendar.current.component(.year, from: .now)
        ]

        if let json = try? JSONSerialization.data(withJSONObject: data),
           let str = String(data: json, encoding: .utf8) {
            UIPasteboard.general.setItems([["public.utf8-plain-text": "SAKUTSU_IMPORT:" + str]], options: [.expirationDate: Date().addingTimeInterval(60)])
            if let url = URL(string: "sakutsu://import?source=pasha") {
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Category Management

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let maxOrder = customCategories.map(\.sortOrder).max() ?? -1
        let cat = CustomCategory(name: name, sortOrder: maxOrder + 1)
        modelContext.insert(cat)
        try? modelContext.save()
        newCategoryName = ""
    }

    private func deleteCategories(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(customCategories[index])
        }
        try? modelContext.save()
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var cats = customCategories
        cats.move(fromOffsets: source, toOffset: destination)
        for (index, cat) in cats.enumerated() {
            cat.sortOrder = index
        }
        try? modelContext.save()
    }

    private func shareText(_ text: String) {
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }

    // MARK: - CSV Export (Standard)

    private func generateCSV() -> String {
        let active = allReceipts.filter { !$0.isDeleted }
        var csv = "\u{FEFF}日付,取引先,金額,通貨,為替レート,JPY金額,勘定科目,仕訳番号,メモ,SHA-256,チェーンハッシュ\n"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for r in active {
            csv += "\(df.string(from: r.date)),\"\(r.vendor)\",\(r.amount),\(r.currency),\(r.exchangeRate),\(r.amountInJPY),\(r.category),\(r.journalNumber),\"\(r.memo)\",\(r.sha256Hash),\(r.chainHash)\n"
        }
        return csv
    }

    // MARK: - freee互換CSV

    private func generateFreeeCSV() -> String {
        let active = allReceipts.filter { !$0.isDeleted }
        var csv = "\u{FEFF}取引日,勘定科目,税区分,金額,取引先,品目,メモ,税額\n"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for r in active {
            let jpyAmount = r.amountInJPY
            let taxAmount = jpyAmount * 10 / 110
            csv += "\(df.string(from: r.date)),\(r.category),課税仕入10%,\(jpyAmount),\"\(r.vendor)\",\(r.category),\"\(r.memo)\",\(taxAmount)\n"
        }
        return csv
    }

    // MARK: - MoneyForward互換CSV

    private func generateMoneyForwardCSV() -> String {
        let active = allReceipts.filter { !$0.isDeleted }
        var csv = "\u{FEFF}日付,内容,金額（税込）,勘定科目,補助科目,税区分,メモ\n"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for r in active {
            let jpyAmount = r.amountInJPY
            csv += "\(df.string(from: r.date)),\"\(r.vendor)\",\(jpyAmount),\(r.category),,課対仕入10%,\"\(r.memo)\"\n"
        }
        return csv
    }

    // MARK: - Audit JSON

    private func generateAuditJSON() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let entries = allLogs.map { log -> [String: Any] in
            var entry: [String: Any] = [
                "id": log.id, "receiptId": log.receiptId, "action": log.action,
                "timestamp": df.string(from: log.timestamp), "dataHash": log.dataHash,
                "logHash": log.logHash, "vendor": log.snapshotVendor,
                "amount": log.snapshotAmount, "date": log.snapshotDate
            ]
            if log.isAnchored {
                entry["anchorId"] = log.solanaTxSignature
                entry["anchoredAt"] = df.string(from: log.anchoredAt ?? Date())
            }
            return entry
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
