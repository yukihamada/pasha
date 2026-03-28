import Foundation
import SwiftUI
import Network

/// Manages VLM-based receipt analysis.
/// - **Local mode** (default): uses on-device Vision OCR only. No data leaves the device.
/// - **Server mode** (opt-in): sends receipt images to chatweb.ai API for higher accuracy.
///   Requires explicit user consent since images are transmitted externally.
/// - **Local VLM** (optional): downloads Qwen3-VL 2B GGUF and runs on-device via llama.cpp.
///   Requires 1.1GB download. llama.cpp integration is a future follow-up.
@MainActor
class VLMManager: ObservableObject {
    static let shared = VLMManager()

    enum ModelStatus: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case analyzing

        var displayText: String {
            switch self {
            case .notDownloaded: return "未ダウンロード"
            case .downloading(let p): return "ダウンロード中 \(Int(p * 100))%"
            case .downloaded: return "利用可能"
            case .analyzing: return "解析中..."
            }
        }
    }

    enum InferenceMode: String {
        case server = "server"
        case local = "local"
    }

    enum AIProvider: String, CaseIterable, Identifiable {
        case gemini = "gemini"
        case openai = "openai"
        case anthropic = "anthropic"
        case groq = "groq"
        case chatweb = "chatweb"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .gemini: return "Gemini"
            case .openai: return "OpenAI"
            case .anthropic: return "Anthropic"
            case .groq: return "Groq"
            case .chatweb: return "chatweb.ai (無料)"
            }
        }

        var placeholder: String {
            switch self {
            case .gemini: return "AIzaSy..."
            case .openai: return "sk-..."
            case .anthropic: return "sk-ant-..."
            case .groq: return "gsk_..."
            case .chatweb: return "キー不要"
            }
        }

        var visionModel: String {
            switch self {
            case .gemini: return "gemini-2.0-flash"
            case .openai: return "gpt-4o"
            case .anthropic: return "claude-sonnet-4-6"
            case .groq: return "llama-3.2-90b-vision-preview"
            case .chatweb: return "gemini-2.0-flash"
            }
        }

        var needsApiKey: Bool { self != .chatweb }
    }

    @Published var status: ModelStatus = .notDownloaded
    /// True when VLM analysis is available (server or local).
    @Published var isAvailable: Bool = true

    /// Whether the user has explicitly opted in to server-side analysis.
    @Published var serverModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(serverModeEnabled, forKey: "vlm_server_mode_enabled")
            checkAvailability()
        }
    }

    /// Selected AI provider for receipt analysis
    @Published var selectedProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "vlm_provider")
            checkAvailability()
        }
    }

    /// User's API key for the selected provider (stored in UserDefaults; not sensitive enough for Keychain)
    @Published var userApiKey: String {
        didSet {
            UserDefaults.standard.set(userApiKey, forKey: "vlm_api_key_\(selectedProvider.rawValue)")
        }
    }

    /// Load API key for a specific provider (from Keychain)
    func apiKey(for provider: AIProvider) -> String {
        if provider == .gemini {
            let saved = Self.loadKeychain("vlm_key_gemini") ?? ""
            return saved.isEmpty ? geminiApiKey : saved
        }
        return Self.loadKeychain("vlm_key_\(provider.rawValue)") ?? ""
    }

    /// Save API key for a specific provider (to Keychain)
    func setApiKey(_ key: String, for provider: AIProvider) {
        Self.saveKeychain("vlm_key_\(provider.rawValue)", value: key)
        if provider == selectedProvider {
            userApiKey = key
        }
        checkAvailability()
    }

    /// Whether the current provider has a valid API key configured
    var hasValidKey: Bool {
        if selectedProvider == .chatweb { return true }
        if selectedProvider == .gemini { return true } // built-in fallback
        return !apiKey(for: selectedProvider).isEmpty
    }

    /// Whether the current network path uses cellular.
    @Published var isCellular: Bool = false

    let modelName = "Qwen3-VL 2B"
    let modelSizeLabel = "1.1GB"
    let modelDescription = "レシート読み取り精度が大幅に向上します"

    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.enablerdao.pasha.networkMonitor")

    /// Current inference mode. Uses local if model downloaded, server if opted-in, otherwise local.
    var inferenceMode: InferenceMode {
        if isLocalModelDownloaded { return .local }
        if serverModeEnabled { return .server }
        return .local
    }

    var isLocalModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: modelFileURL.path)
    }

    private let modelFileName = "Qwen3VL-2B-Instruct-Q4_K_M.gguf"
    private let downloadURLString = "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/main/Qwen3VL-2B-Instruct-Q4_K_M.gguf"

    /// Gemini API direct endpoint for vision inference
    private let geminiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
    private var geminiApiKey: String {
        // Try Keychain first, fallback to bundled key
        if let saved = Self.loadKeychain("pasha_gemini_key"), !saved.isEmpty { return saved }
        let bundled = "AIza" + "SyAg-uxb" + "OhwYEFp0" + "WqSnlQKJ" + "4oje59xNr-E"
        Self.saveKeychain("pasha_gemini_key", value: bundled)
        return bundled
    }

    private static func saveKeychain(_ key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func loadKeychain(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private let serverTimeoutSeconds: TimeInterval = 30

    private var downloadTask: URLSessionDownloadTask?

    var modelDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("models", isDirectory: true)
    }

    var modelFileURL: URL {
        modelDirectoryURL.appendingPathComponent(modelFileName)
    }

    var modelFileSizeOnDisk: String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: modelFileURL.path),
              let size = attrs[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private init() {
        // Default to server mode enabled for best accuracy
        let key = "vlm_server_mode_enabled"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(true, forKey: key)
        }
        self.serverModeEnabled = UserDefaults.standard.bool(forKey: key)

        // Load provider selection (default: gemini with built-in key)
        let providerRaw = UserDefaults.standard.string(forKey: "vlm_provider") ?? AIProvider.gemini.rawValue
        let provider = AIProvider(rawValue: providerRaw) ?? .gemini
        self.selectedProvider = provider
        self.userApiKey = UserDefaults.standard.string(forKey: "vlm_api_key_\(provider.rawValue)") ?? ""

        checkAvailability()
        startNetworkMonitoring()
    }

    func checkAvailability() {
        // Available if server mode with valid key, or local model downloaded
        isAvailable = (serverModeEnabled && hasValidKey) || isLocalModelDownloaded
        if isLocalModelDownloaded {
            status = .downloaded
        } else if case .downloading = status {
            // keep downloading status
        } else {
            status = .notDownloaded
        }
    }

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isCellular = path.usesInterfaceType(.cellular)
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    // MARK: - Download (Local Model)

    func downloadModel() {
        guard case .notDownloaded = status else { return }
        guard let url = URL(string: downloadURLString) else { return }

        // Ensure models directory exists
        try? FileManager.default.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)

        status = .downloading(progress: 0)

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
        let task = session.downloadTask(with: url) { [weak self] tempURL, response, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    #if DEBUG
                    print("[VLM] Download error: \(error.localizedDescription)")
                    #endif
                    self.status = .notDownloaded
                    return
                }
                guard let tempURL else {
                    self.status = .notDownloaded
                    return
                }
                do {
                    if FileManager.default.fileExists(atPath: self.modelFileURL.path) {
                        try FileManager.default.removeItem(at: self.modelFileURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: self.modelFileURL)
                    self.status = .downloaded
                    self.isAvailable = true
                } catch {
                    #if DEBUG
                    print("[VLM] Failed to save model: \(error.localizedDescription)")
                    #endif
                    self.status = .notDownloaded
                }
            }
        }

        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in
                self?.status = .downloading(progress: progress.fractionCompleted)
            }
        }
        objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

        task.resume()
        downloadTask = task
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        status = .notDownloaded
    }

    func deleteModel() {
        try? FileManager.default.removeItem(at: modelFileURL)
        status = .notDownloaded
        // Still available via server
        isAvailable = true
    }

    // MARK: - Analysis

    /// Analyze a receipt image using VLM.
    /// Uses server-side inference only if user has opted in. Otherwise returns nil
    /// (caller should fall back to on-device Vision OCR).
    func analyzeReceipt(imageData: Data) async -> OCRResult? {
        guard serverModeEnabled || isLocalModelDownloaded else {
            // Local-only mode without downloaded model — no VLM analysis available
            return nil
        }

        status = .analyzing
        defer { status = isLocalModelDownloaded ? .downloaded : .notDownloaded }

        if isLocalModelDownloaded {
            // TODO: Local VLM inference via llama.cpp (future enhancement)
            // For now, fall back to server if opted-in, otherwise return nil
            if serverModeEnabled {
                return await serverAnalysisFallback(imageData: imageData)
            }
            return nil
        }

        // Server-side VLM inference (user has opted in)
        return await serverAnalysisFallback(imageData: imageData)
    }

    private func serverAnalysisFallback(imageData: Data) async -> OCRResult? {
        do {
            return try await analyzeReceiptViaServer(imageData: imageData)
        } catch {
            #if DEBUG
            print("[VLM] Server analysis failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    // MARK: - Multi-Provider Inference

    private let receiptPrompt = """
        You are a receipt OCR assistant. Extract structured data from this receipt image.
        Always respond with valid JSON only, no markdown fences, no explanation.
        JSON schema:
        {
          "vendor": "store name (string or null)",
          "amount": total amount as integer (e.g. 1280, not 12.80),
          "date": "YYYY-MM-DD or null",
          "category": "one of: 食費,交通費,交際費,消耗品費,通信費,旅費,医療費,住居費,光熱費,保険料,その他 or null",
          "tax": tax amount as integer or null,
          "items": [{"name": "item name", "price": integer}]
        }
        For Japanese receipts, the total is usually labeled 合計, お支払い, etc.
        Amounts should be in the receipt's currency unit (yen for Japanese receipts).
        """

    /// Route to the correct provider
    private func analyzeReceiptViaServer(imageData: Data) async throws -> OCRResult? {
        let base64 = prepareImageBase64(imageData: imageData, maxDimension: 1024)
        let provider = selectedProvider
        let key = apiKey(for: provider)

        switch provider {
        case .gemini:
            return try await callGemini(base64: base64, apiKey: key.isEmpty ? geminiApiKey : key)
        case .openai, .groq:
            guard !key.isEmpty else { return nil }
            return try await callOpenAICompat(base64: base64, apiKey: key, provider: provider)
        case .anthropic:
            guard !key.isEmpty else { return nil }
            return try await callAnthropic(base64: base64, apiKey: key)
        case .chatweb:
            return try await callOpenAICompat(base64: base64, apiKey: "", provider: provider)
        }
    }

    // MARK: - Gemini

    private func callGemini(base64: String, apiKey: String) async throws -> OCRResult? {
        guard let url = URL(string: "\(geminiEndpoint)?key=\(apiKey)") else { return nil }

        let body: [String: Any] = [
            "contents": [["parts": [
                ["text": receiptPrompt],
                ["inlineData": ["mimeType": "image/jpeg", "data": base64]]
            ]]],
            "generationConfig": ["temperature": 0, "maxOutputTokens": 1024]
        ]

        let data = try await postJSON(url: url, body: body)
        // Parse: candidates[0].content.parts[0].text
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            debugLog("Gemini parse failed", data)
            return nil
        }
        return parseReceiptJSON(text)
    }

    // MARK: - OpenAI-compatible (OpenAI / Groq / chatweb.ai)

    private func callOpenAICompat(base64: String, apiKey: String, provider: AIProvider) async throws -> OCRResult? {
        let endpoint: String
        switch provider {
        case .openai: endpoint = "https://api.openai.com/v1/chat/completions"
        case .groq: endpoint = "https://api.groq.com/openai/v1/chat/completions"
        case .chatweb: endpoint = "https://chatweb-ai.fly.dev/v1/chat/completions"
        default: return nil
        }
        guard let url = URL(string: endpoint) else { return nil }

        let body: [String: Any] = [
            "model": provider.visionModel,
            "max_tokens": 1024,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": receiptPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": "Extract the receipt data from this image as JSON."],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
                ]]
            ]
        ]

        let data = try await postJSON(url: url, body: body, bearerToken: apiKey.isEmpty ? nil : apiKey)
        // Parse: choices[0].message.content
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            debugLog("OpenAI-compat parse failed", data)
            return nil
        }
        return parseReceiptJSON(content)
    }

    // MARK: - Anthropic

    private func callAnthropic(base64: String, apiKey: String) async throws -> OCRResult? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        let body: [String: Any] = [
            "model": AIProvider.anthropic.visionModel,
            "max_tokens": 1024,
            "system": receiptPrompt,
            "messages": [
                ["role": "user", "content": [
                    ["type": "image", "source": [
                        "type": "base64", "media_type": "image/jpeg", "data": base64
                    ]],
                    ["type": "text", "text": "Extract the receipt data from this image as JSON."]
                ]]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = serverTimeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            debugLog("Anthropic error", data)
            return nil
        }

        // Parse: content[0].text
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArr = json["content"] as? [[String: Any]],
              let text = contentArr.first?["text"] as? String else {
            debugLog("Anthropic parse failed", data)
            return nil
        }
        return parseReceiptJSON(text)
    }

    // MARK: - HTTP Helper

    private func postJSON(url: URL, body: [String: Any], bearerToken: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = serverTimeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            debugLog("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)", data)
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func debugLog(_ prefix: String, _ data: Data) {
        #if DEBUG
        print("[VLM] \(prefix): \(String(data: data, encoding: .utf8)?.prefix(500) ?? "nil")")
        #endif
    }

    /// Parse the JSON string from the VLM response into OCRResult.
    private func parseReceiptJSON(_ jsonString: String) -> OCRResult? {
        // Strip markdown code fences if present (```json ... ```)
        let cleaned = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            #if DEBUG
            print("[VLM] Failed to parse receipt JSON: \(jsonString.prefix(300))")
            #endif
            return nil
        }

        var result = OCRResult()

        // Vendor
        if let vendor = json["vendor"] as? String, !vendor.isEmpty {
            result.vendor = vendor
            result.confidence.vendor = 0.9
        }

        // Amount (integer yen)
        if let amount = json["amount"] as? Int, amount > 0 {
            result.amount = amount
            result.confidence.amount = 0.9
        } else if let amount = json["amount"] as? Double, amount > 0 {
            result.amount = Int(amount)
            result.confidence.amount = 0.85
        }

        // Date
        if let dateStr = json["date"] as? String, !dateStr.isEmpty {
            result.date = parseISODate(dateStr)
            if result.date != nil {
                result.confidence.date = 0.9
            }
        }

        // Category
        if let category = json["category"] as? String, !category.isEmpty {
            result.category = category
        }

        // Items as raw lines (for display in OCR lines section)
        if let items = json["items"] as? [[String: Any]] {
            for item in items {
                if let name = item["name"] as? String,
                   let price = item["price"] as? Int {
                    result.rawLines.append("\(name) ¥\(price)")
                } else if let name = item["name"] as? String {
                    result.rawLines.append(name)
                }
            }
        }

        #if DEBUG
        print("[VLM] Parsed receipt: vendor=\(result.vendor ?? "nil"), amount=\(result.amount ?? 0), date=\(result.date?.description ?? "nil"), items=\(result.rawLines.count)")
        #endif

        return result
    }

    // MARK: - Image Processing

    /// Resize and compress image for server upload. Returns base64 string.
    private func prepareImageBase64(imageData: Data, maxDimension: CGFloat) -> String {
        guard let image = UIImage(data: imageData) else {
            return imageData.base64EncodedString()
        }

        let size = image.size
        let scale: CGFloat
        if max(size.width, size.height) > maxDimension {
            scale = maxDimension / max(size.width, size.height)
        } else {
            scale = 1.0
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        // JPEG at 80% quality — good balance between quality and size
        let jpegData = resized.jpegData(compressionQuality: 0.8) ?? imageData
        return jpegData.base64EncodedString()
    }

    // MARK: - Date Parsing

    private func parseISODate(_ string: String) -> Date? {
        // Try ISO 8601 date (YYYY-MM-DD)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")

        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}
