import SwiftUI
import SwiftData

struct ReceiptDetailView: View {
    @Bindable var receipt: Receipt
    @Environment(\.modelContext) private var modelContext
    @Environment(\.auditModelContext) private var auditModelContext
    @EnvironmentObject private var auditManager: AuditManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomCategory.sortOrder) private var customCategories: [CustomCategory]
    @ObservedObject private var vlmManager = VLMManager.shared
    @State private var showDeleteAlert = false
    @State private var showImage = false
    @State private var isReanalyzing = false

    @State private var origDate: Date = .now
    @State private var origAmount: Int = 0
    @State private var origVendor: String = ""
    @State private var origCategory: String = ""
    @State private var origJournalNumber: String = ""
    @State private var origMemo: String = ""
    @State private var origCurrency: String = "JPY"
    @State private var origExchangeRate: Double = 1.0

    @State private var reanalyzeMessage = ""
    @State private var ocrRawLines: [String] = []
    @State private var showOCRLines = false
    @State private var showDownloadAlert = false
    @State private var auditLogs: [AuditLog] = []

    private var auditContext: ModelContext { auditModelContext ?? modelContext }

    private var categoryNames: [String] {
        customCategories.isEmpty ? CustomCategory.defaults : customCategories.map(\.name)
    }

    private var hasChanges: Bool {
        receipt.date != origDate || receipt.amount != origAmount ||
        receipt.vendor != origVendor || receipt.category != origCategory ||
        receipt.journalNumber != origJournalNumber || receipt.memo != origMemo ||
        receipt.currency != origCurrency || receipt.exchangeRate != origExchangeRate
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroImage
                amountSection
                formSection
                saveButton
                aiReanalyzeButton

                // OCR raw lines picker
                if showOCRLines && !ocrRawLines.isEmpty {
                    ocrLinesSection
                }

                blockchainBadge
                captureMetadata
                auditTrail

                Button(role: .destructive) { showDeleteAlert = true } label: {
                    Label("削除", systemImage: "trash")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered).tint(.red)
            }
            .padding()
            .padding(.bottom, 40)
        }
        .background(Color.pashaBg)
        .navigationTitle("レシート詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { saveChanges() } label: {
                    Text("保存").fontWeight(.semibold)
                        .foregroundStyle(hasChanges ? Color.pasha : .secondary)
                }
                .disabled(!hasChanges)
            }
        }
        .onAppear { captureOriginalValues(); refreshAuditLogs() }
        .alert("このレシートを削除しますか？", isPresented: $showDeleteAlert) {
            Button("削除", role: .destructive) {
                auditManager.logDeletion(receiptId: receipt.id, vendor: receipt.vendor,
                    amount: receipt.amount, category: receipt.category,
                    date: receipt.date, context: auditContext)
                receipt.isDeleted = true
                receipt.addHistory("削除")
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("監査ログは保持されます") }
        .alert("高精度AIモデルをダウンロードしますか？", isPresented: $showDownloadAlert) {
            Button("ダウンロード（\(vlmManager.modelSizeLabel)）") {
                vlmManager.downloadModel()
            }
            Button("OCRだけで解析") {
                Task { await reanalyzeWithAI() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("Qwen3-VL 2Bモデル（\(vlmManager.modelSizeLabel)）をダウンロードすると、レシートの読み取り精度が大幅に向上します。Wi-Fi環境でのダウンロードを推奨します。")
        }
        .fullScreenCover(isPresented: $showImage) {
            if let data = receipt.imageData, let img = UIImage(data: data) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                        .onTapGesture { showImage = false }
                }
            }
        }
    }

    // MARK: - Hero Image

    @ViewBuilder
    private var heroImage: some View {
        if let data = receipt.imageData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                .onTapGesture { showImage = true }
        }
    }

    // MARK: - Amount

    private var amountSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(receipt.currencySymbol)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("0", value: $receipt.amount, format: .number)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.pashaWarn)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .glassCard()

            if receipt.currency != "JPY" {
                Text("≈ ¥\(receipt.amountInJPY.formatted())")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Form

    private var formSection: some View {
        VStack(spacing: 2) {
            fieldRow(icon: "building.2", label: "取引先") {
                TextField("店名を入力", text: $receipt.vendor).font(.body)
            }
            Divider().padding(.leading, 44)
            fieldRow(icon: "calendar", label: "日付") {
                DatePicker("", selection: $receipt.date, displayedComponents: .date).labelsHidden()
            }
            Divider().padding(.leading, 44)
            fieldRow(icon: "tag", label: "勘定科目") {
                Picker("", selection: $receipt.category) {
                    ForEach(categoryNames, id: \.self) { Text($0) }
                }.pickerStyle(.menu).tint(.primary)
            }
            Divider().padding(.leading, 44)
            fieldRow(icon: "yensign.circle", label: "通貨") {
                Picker("", selection: $receipt.currency) {
                    ForEach(Receipt.supportedCurrencies, id: \.self) { code in
                        Text("\(Receipt.currencySymbols[code] ?? "") \(code)").tag(code)
                    }
                }.pickerStyle(.menu).tint(.primary)
            }
            if receipt.currency != "JPY" {
                Divider().padding(.leading, 44)
                fieldRow(icon: "arrow.left.arrow.right", label: "為替レート") {
                    TextField("1.0", value: $receipt.exchangeRate, format: .number).keyboardType(.decimalPad)
                }
            }
            Divider().padding(.leading, 44)
            if subscriptionManager.hasComplianceFeatures {
                fieldRow(icon: "number", label: "仕訳番号") {
                    TextField("J-2026-001", text: $receipt.journalNumber)
                        .font(.system(.body, design: .monospaced))
                }
                Divider().padding(.leading, 44)
            }
            fieldRow(icon: "text.alignleft", label: "メモ") {
                TextField("用途などを記入...", text: $receipt.memo, axis: .vertical).lineLimit(2...4)
            }
        }
        .padding(.vertical, 4)
        .glassCard()
    }

    private func fieldRow<Content: View>(icon: String, label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16)).foregroundStyle(Color.pasha)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - Save Button

    @ViewBuilder
    private var saveButton: some View {
        Button { saveChanges() } label: {
            HStack(spacing: 8) {
                Image(systemName: hasChanges ? "checkmark.circle.fill" : "checkmark.circle")
                Text(hasChanges ? "保存" : "変更なし")
            }
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(hasChanges
                ? AnyShapeStyle(LinearGradient(colors: [Color.pasha, Color.pashaAccent], startPoint: .leading, endPoint: .trailing))
                : AnyShapeStyle(Color.white.opacity(0.06)))
            .foregroundStyle(hasChanges ? .white : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!hasChanges)
    }

    // MARK: - AI Re-analysis

    @ViewBuilder
    private var aiReanalyzeButton: some View {
        // Main re-analyze button
        Button {
            if !vlmManager.isAvailable, case .notDownloaded = vlmManager.status {
                showDownloadAlert = true
            } else {
                Task { await reanalyzeWithAI() }
            }
        } label: {
            HStack(spacing: 8) {
                if isReanalyzing {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "brain")
                }
                Text(isReanalyzing ? "AI 解析中..." : "AI で再解析")
            }
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                        LinearGradient(colors: [Color.pasha.opacity(0.5), Color.pashaAccent.opacity(0.5)],
                                       startPoint: .leading, endPoint: .trailing), lineWidth: 1))
            )
            .foregroundStyle(LinearGradient(colors: [Color.pasha, Color.pashaAccent],
                                            startPoint: .leading, endPoint: .trailing))
        }
        .disabled(isReanalyzing)

        // VLM download progress
        if case .downloading(let progress) = vlmManager.status {
            VStack(spacing: 4) {
                ProgressView(value: progress)
                    .tint(Color.pasha)
                Text("AIモデルをダウンロード中... \(Int(progress * 100))%")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.pasha.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }


        if !reanalyzeMessage.isEmpty {
            Text(reanalyzeMessage)
                .font(.caption)
                .foregroundStyle(reanalyzeMessage.contains("更新") ? Color.pashaSuccess : .secondary)
        }
    }

    // MARK: - OCR Raw Lines (tap to use as vendor/amount)

    @ViewBuilder
    private var ocrLinesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("読み取ったテキスト", systemImage: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { showOCRLines = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
            }
            Text("タップで取引先に設定、長押しで金額に設定")
                .font(.caption2).foregroundStyle(.tertiary)

            ForEach(ocrRawLines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        receipt.vendor = line
                        reanalyzeMessage = "更新: 取引先→\(line)"
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .onLongPressGesture {
                        // Try to extract number from this line
                        let nums = line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                        if let num = Int(nums), num > 0 {
                            receipt.amount = num
                            reanalyzeMessage = "更新: 金額→¥\(num)"
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
            }
        }
        .padding(14)
        .glassCard()
    }

    // MARK: - Re-analyze Logic

    private func reanalyzeWithAI() async {
        guard let imageData = receipt.imageData else {
            reanalyzeMessage = "画像データがありません"
            return
        }
        isReanalyzing = true
        let dataSize = imageData.count
        reanalyzeMessage = "解析中... (\(dataSize/1024)KB)"
        defer { isReanalyzing = false }

        // Step 1: OCR text recognition
        let ocrResult = await OCREngine.scan(imageData)

        var ocrChanges: [String] = []

        await MainActor.run {
            let rawLines = ocrResult.rawLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ocrRawLines = rawLines

            // Amount
            if let amount = ocrResult.amount, amount > 0, amount != receipt.amount {
                receipt.amount = amount
                ocrChanges.append("金額→¥\(amount)")
            }

            // Date
            if let date = ocrResult.date, date != receipt.date {
                receipt.date = date
                ocrChanges.append("日付")
            }

            // Vendor
            if let vendor = ocrResult.vendor, !vendor.isEmpty, vendor != receipt.vendor {
                receipt.vendor = vendor
                ocrChanges.append("取引先→\(vendor)")
            }

            // Category (auto-guess via parser)
            let parsed = ReceiptParser.parse(lines: rawLines)
            if let category = parsed.category, receipt.category == "その他" {
                receipt.category = category
                ocrChanges.append("科目→\(category)")
            }

            if !ocrChanges.isEmpty {
                let action = "AI解析: " + ocrChanges.joined(separator: ", ")
                receipt.addHistory(action)
                auditManager.log(action: action, receipt: receipt, context: auditContext)
                try? modelContext.save()
                captureOriginalValues()
            }
        }

        // Step 2: VLM enhancement when OCR confidence is low
        let needsVLM = ocrResult.confidence.isLow && VLMManager.shared.isAvailable
        if needsVLM {
            await MainActor.run { reanalyzeMessage = "高精度AI解析中..." }
            if let vlmResult = await VLMManager.shared.analyzeReceipt(imageData: imageData) {
                await MainActor.run {
                    var vlmChanges: [String] = []

                    if let a = vlmResult.amount, a > 0, (receipt.amount == 0 || ocrResult.amount == nil) {
                        receipt.amount = a
                        vlmChanges.append("金額→¥\(a)")
                    }
                    if let v = vlmResult.vendor, !v.isEmpty, (receipt.vendor.isEmpty || ocrResult.vendor == nil) {
                        receipt.vendor = v
                        vlmChanges.append("取引先→\(v)")
                    }
                    if let d = vlmResult.date, ocrResult.date == nil {
                        receipt.date = d
                        vlmChanges.append("日付")
                    }

                    if !vlmChanges.isEmpty {
                        let action = "VLM解析: " + vlmChanges.joined(separator: ", ")
                        receipt.addHistory(action)
                        auditManager.log(action: action, receipt: receipt, context: auditContext)
                        try? modelContext.save()
                        captureOriginalValues()
                        ocrChanges.append(contentsOf: vlmChanges)
                    }

                    // Also add VLM-extracted items to rawLines for display
                    if !vlmResult.rawLines.isEmpty {
                        ocrRawLines.append(contentsOf: vlmResult.rawLines)
                    }
                }
            }
        }

        await MainActor.run {
            if !ocrChanges.isEmpty {
                reanalyzeMessage = "更新: " + ocrChanges.joined(separator: ", ")
                showOCRLines = false
                refreshAuditLogs()
            } else if !ocrRawLines.isEmpty {
                reanalyzeMessage = "\(ocrRawLines.count)行読み取り済み。タップで選択↓"
                showOCRLines = true
            } else {
                reanalyzeMessage = "テキストを読み取れませんでした"
            }

            UINotificationFeedbackGenerator().notificationOccurred(ocrChanges.isEmpty ? .warning : .success)
        }
    }

    // MARK: - Save Logic

    private func saveChanges() {
        guard hasChanges else { return }
        var changes: [String] = []
        if receipt.date != origDate { changes.append("日付") }
        if receipt.amount != origAmount { changes.append("金額") }
        if receipt.vendor != origVendor { changes.append("取引先") }
        if receipt.category != origCategory { changes.append("科目") }
        if receipt.journalNumber != origJournalNumber { changes.append("仕訳番号") }
        if receipt.memo != origMemo { changes.append("メモ") }
        if receipt.currency != origCurrency { changes.append("通貨") }
        if receipt.exchangeRate != origExchangeRate { changes.append("為替レート") }

        let action = changes.joined(separator: "・") + "変更"
        receipt.addHistory(action)
        auditManager.log(action: action, receipt: receipt, context: auditContext)
        try? modelContext.save()
        captureOriginalValues()
        refreshAuditLogs()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func captureOriginalValues() {
        origDate = receipt.date; origAmount = receipt.amount
        origVendor = receipt.vendor; origCategory = receipt.category
        origJournalNumber = receipt.journalNumber; origMemo = receipt.memo
        origCurrency = receipt.currency; origExchangeRate = receipt.exchangeRate
    }

    private func refreshAuditLogs() {
        auditLogs = auditManager.logsForReceipt(receipt.id, context: auditContext)
    }

    // MARK: - Blockchain Badge

    @ViewBuilder
    private var blockchainBadge: some View {
        let anchored = auditLogs.contains { $0.isAnchored }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: anchored ? "checkmark.shield.fill" : "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(anchored ? Color.solana : Color.pashaSuccess)
                VStack(alignment: .leading, spacing: 2) {
                    Text(anchored ? "ブロックチェーン記録済み" : "ローカル検証済み")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(anchored ? Color.solana : Color.pashaSuccess)
                    Text("SHA-256: \(String(receipt.sha256Hash.prefix(24)))...")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Capture Metadata

    @ViewBuilder
    private var captureMetadata: some View {
        if receipt.captureLatitude != 0 || !receipt.captureDevice.isEmpty {
            HStack(spacing: 16) {
                if !receipt.captureDevice.isEmpty {
                    Label(receipt.captureDevice, systemImage: "iphone").font(.caption2).foregroundStyle(.tertiary)
                }
                if !receipt.captureResolution.isEmpty {
                    Label(receipt.captureResolution, systemImage: "camera.metering.spot").font(.caption2).foregroundStyle(.tertiary)
                }
                if receipt.captureLatitude != 0 {
                    Label("\(receipt.captureLatitude, specifier: "%.2f"), \(receipt.captureLongitude, specifier: "%.2f")",
                          systemImage: "location").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassCard()
        }
    }

    // MARK: - Audit Trail

    @ViewBuilder
    private var auditTrail: some View {
        if subscriptionManager.hasComplianceFeatures && !auditLogs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("監査ログ", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(auditLogs.count)件").font(.caption2).foregroundStyle(.tertiary)
                }
                ForEach(auditLogs.suffix(10), id: \.id) { log in
                    HStack(spacing: 8) {
                        Circle().fill(log.isAnchored ? Color.solana : Color.pasha.opacity(0.6))
                            .frame(width: 5, height: 5)
                        Text(log.action).font(.caption2)
                        Spacer()
                        Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .glassCard()
        }
    }
}

struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content.padding(10).background(Color.pashaCard).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
