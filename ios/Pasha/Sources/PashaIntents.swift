import AppIntents

struct OpenCameraIntent: AppIntent {
    static var title: LocalizedStringResource = "レシートを撮影"
    static var description = IntentDescription("パシャでレシートを撮影します")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct ScanReceiptIntent: AppIntent {
    static var title: LocalizedStringResource = "レシートをスキャン"
    static var description = IntentDescription("パシャを開いてレシートをスキャンします")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct PashaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCameraIntent(),
            phrases: [
                "パシャでレシート撮って",
                "レシートを撮影",
                "経費を記録",
                "Take a receipt photo with \(.applicationName)"
            ],
            shortTitle: "レシート撮影",
            systemImageName: "camera"
        )
        AppShortcut(
            intent: ScanReceiptIntent(),
            phrases: [
                "パシャでレシートをスキャン",
                "Scan a receipt with \(.applicationName)"
            ],
            shortTitle: "レシートスキャン",
            systemImageName: "doc.viewfinder"
        )
    }
}
