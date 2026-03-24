import SwiftUI
import AVFoundation
import PhotosUI
import SwiftData

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.auditModelContext) private var auditModelContext
    @EnvironmentObject private var auditManager: AuditManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var camera = CameraModel()
    @State private var flashOpacity = 0.0
    @State private var navigateToDetail: Receipt?
    @State private var showLimitAlert = false
    @State private var isProcessing = false
    @State private var processingWithVLM = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    // Continuous capture mode
    @State private var continuousMode = false
    @State private var continuousCaptureCount = 0
    @State private var showSavedToast = false

    // Duplicate detection
    @State private var showDuplicateAlert = false
    @State private var duplicateReceipt: Receipt?
    @State private var pendingReceipt: Receipt?
    @State private var showCelebration = false

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            GeometryReader { geo in
                let width = max(geo.size.width, 100)
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                        .frame(width: width * 0.65, height: width * 1.1)
                        .overlay {
                            Text("レシートを枠内に合わせてください")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()

                    // Continuous mode toggle
                    Button { continuousMode.toggle() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "repeat")
                                .font(.system(size: 14, weight: .semibold))
                            Text("連続撮影")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(continuousMode ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            continuousMode
                                ? AnyShapeStyle(LinearGradient(colors: [.pasha, .pashaAccent], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(.ultraThinMaterial)
                        )
                        .clipShape(Capsule())
                    }
                }
                .padding()

                // Continuous capture counter
                if continuousMode && continuousCaptureCount > 0 {
                    Text("\(continuousCaptureCount)枚撮影済み")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer()
                HStack(alignment: .center) {
                    // Photo library button
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .onChange(of: selectedPhotoItem) {
                        Task { await loadSelectedPhoto() }
                    }

                    Spacer()

                    // Shutter button
                    Button { capturePhoto() } label: {
                        Circle()
                            .strokeBorder(.white, lineWidth: 4)
                            .frame(width: 72, height: 72)
                            .overlay { Circle().fill(.white).padding(8) }
                    }
                    .disabled(isProcessing)

                    Spacer()

                    // Placeholder for symmetry
                    Color.clear.frame(width: 48, height: 48)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }

            // Saved toast for continuous mode
            if showSavedToast {
                VStack {
                    Spacer()
                    SuccessCheckmark(color: .pashaSuccess)
                    Text("保存済み")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            // Celebration effect on successful capture
            if showCelebration {
                VStack {
                    Spacer()
                    SuccessCheckmark(color: .pasha)
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            // Processing overlay with tips
            if isProcessing {
                ProcessingTipsView(isVLM: processingWithVLM)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isProcessing)
        .animation(.easeInOut(duration: 0.2), value: showSavedToast)
        .animation(.easeInOut(duration: 0.3), value: showCelebration)
        .onAppear {
            camera.start()
            auditManager.requestLocationPermission()
        }
        .onDisappear { camera.stop() }
        .sheet(item: $navigateToDetail) { receipt in
            NavigationStack { ReceiptDetailView(receipt: receipt) }
        }
        .alert("無料プランは月30件まで", isPresented: $showLimitAlert) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("Proプラン（¥980/月）にアップグレードして無制限にレシートを記録しましょう。設定画面からプランを変更できます。")
        }
        .alert("似たレシートが既にあります", isPresented: $showDuplicateAlert) {
            Button("保存する") {
                // Keep the receipt as-is (already inserted)
                if let receipt = pendingReceipt {
                    if continuousMode {
                        finishContinuousCapture()
                    } else {
                        navigateToDetail = receipt
                    }
                }
                pendingReceipt = nil
                duplicateReceipt = nil
            }
            Button("削除する", role: .destructive) {
                // Mark pending receipt as deleted
                if let receipt = pendingReceipt {
                    receipt.isDeleted = true
                    try? modelContext.save()
                }
                pendingReceipt = nil
                duplicateReceipt = nil
                isProcessing = false
            }
        } message: {
            Text(duplicateAlertMessage)
        }
    }

    private var duplicateAlertMessage: String {
        guard let dup = duplicateReceipt else {
            return "重複の可能性があります。保存しますか？"
        }
        let df = DateFormatter()
        df.dateFormat = "M/d"
        let dateStr = df.string(from: dup.date)
        return "\u{00a5}\(dup.amount.formatted()) \(dup.vendor) (\(dateStr))\n重複の可能性があります。保存しますか？"
    }

    private func loadSelectedPhoto() async {
        guard let item = selectedPhotoItem else { return }
        selectedPhotoItem = nil

        subscriptionManager.updateMonthlyCount(context: modelContext)
        guard subscriptionManager.canAddReceipt else {
            showLimitAlert = true
            return
        }

        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        // Convert to JPEG if needed
        guard let uiImage = UIImage(data: data),
              let jpegData = uiImage.jpegData(compressionQuality: 0.85) else { return }

        processImageData(jpegData)
    }

    private func capturePhoto() {
        // Check free tier limit
        subscriptionManager.updateMonthlyCount(context: modelContext)
        guard subscriptionManager.canAddReceipt else {
            showLimitAlert = true
            return
        }

        camera.capture { data in
            guard let data else { return }
            withAnimation(.easeOut(duration: 0.15)) { flashOpacity = 0.8 }
            withAnimation(.easeIn(duration: 0.3).delay(0.15)) { flashOpacity = 0 }
            processImageData(data)
        }
    }

    private func finishContinuousCapture() {
        continuousCaptureCount += 1
        showSavedToast = true
        isProcessing = false
        Task {
            try? await Task.sleep(for: .seconds(1.0))
            showSavedToast = false
        }
    }

    private func processImageData(_ data: Data) {
        isProcessing = true
        processingWithVLM = false

        var descriptor = FetchDescriptor<Receipt>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        let lastReceipt = try? modelContext.fetch(descriptor).first
        let previousChainHash = lastReceipt?.chainHash ?? "GENESIS"

        let location = auditManager.getCurrentLocation()

        // Receipt init does SHA-256 + image saving; run on background
        let imageData = data
        Task.detached(priority: .userInitiated) {
            let receipt = Receipt(imageData: imageData, previousChainHash: previousChainHash)

            let auditCtx: ModelContext = await MainActor.run {
                if let loc = location {
                    receipt.captureLatitude = loc.latitude
                    receipt.captureLongitude = loc.longitude
                }

                modelContext.insert(receipt)
                try? modelContext.save()

                let ctx = auditModelContext ?? modelContext
                auditManager.log(action: "作成", receipt: receipt, context: ctx)

                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                SoundPlayer.shared.play("pasha")
                subscriptionManager.updateMonthlyCount(context: modelContext)
                return ctx
            }

            // Continue with OCR
            let ocrResult = await OCREngine.scan(imageData)
            var needsVLM = false

            await MainActor.run {
                var changes: [String] = []

                if let amount = ocrResult.amount, amount > 0 {
                    receipt.amount = amount; changes.append("金額")
                }
                if let date = ocrResult.date {
                    receipt.date = date; changes.append("日付")
                }
                if let vendor = ocrResult.vendor, !vendor.isEmpty {
                    receipt.vendor = vendor; changes.append("取引先")
                }
                // Category from parser
                let parsed = ReceiptParser.parse(lines: ocrResult.rawLines)
                if let category = parsed.category {
                    receipt.category = category; changes.append("科目")
                }
                if !changes.isEmpty {
                    receipt.addHistory("AI自動入力: " + changes.joined(separator: ", "))
                    auditManager.log(action: "AI自動入力", receipt: receipt, context: auditCtx)
                    try? modelContext.save()
                }
                needsVLM = ocrResult.confidence.isLow && VLMManager.shared.isAvailable
            }

            if needsVLM {
                await MainActor.run { processingWithVLM = true }
                if let vlmResult = await VLMManager.shared.analyzeReceipt(imageData: imageData) {
                    await MainActor.run {
                        var vlmChanged = false
                        if let a = vlmResult.amount, a > 0, receipt.amount == 0 { receipt.amount = a; vlmChanged = true }
                        if let v = vlmResult.vendor, !v.isEmpty, receipt.vendor.isEmpty { receipt.vendor = v; vlmChanged = true }
                        if vlmChanged {
                            receipt.addHistory("VLM自動入力")
                            auditManager.log(action: "VLM自動入力", receipt: receipt, context: auditCtx)
                            try? modelContext.save()
                        }
                    }
                }
            }

            await MainActor.run {
                processingWithVLM = false

                // Duplicate detection
                let foundDuplicate: Bool
                if let dup = DuplicateDetector.findDuplicate(
                    amount: receipt.amount,
                    date: receipt.date,
                    vendor: receipt.vendor,
                    in: modelContext
                ), dup.id != receipt.id {
                    isProcessing = false
                    pendingReceipt = receipt
                    duplicateReceipt = dup
                    showDuplicateAlert = true
                    foundDuplicate = true
                } else {
                    foundDuplicate = false
                }

                if !foundDuplicate {
                    if continuousMode {
                        finishContinuousCapture()
                    } else {
                        isProcessing = false
                        showCelebration = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            showCelebration = false
                            camera.stop()
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Camera Model

@MainActor
class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var completion: ((Data?) -> Void)?
    @Published var isAuthorized = false

    func start() {
        checkPermission { [weak self] granted in
            guard granted else { return }
            self?.setupSession()
        }
    }

    private func checkPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.isAuthorized = true }
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { self?.isAuthorized = granted }
                completion(granted)
            }
        default:
            DispatchQueue.main.async { self.isAuthorized = false }
            completion(false)
        }
    }

    private func setupSession() {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func capture(completion: @escaping (Data?) -> Void) {
        self.completion = completion
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor [weak self] in self?.completion?(data) }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
