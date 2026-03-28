import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showCamera = false
    @State private var capturedReceipt: Receipt?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView(showCamera: $showCamera)
                    .tag(0)
                    .tabItem { Label("ホーム", systemImage: "house.fill") }

                SearchView()
                    .tag(1)
                    .tabItem { Label("検索", systemImage: "magnifyingglass") }

                ReportView()
                    .tag(2)
                    .tabItem { Label("レポート", systemImage: "chart.pie") }

                SettingsView()
                    .tag(3)
                    .tabItem { Label("設定", systemImage: "gearshape.fill") }
            }
            .tint(.pasha)

            // Floating capture button — glass morphism
            Button { showCamera = true } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 68, height: 68)
                    Circle()
                        .fill(LinearGradient(colors: [.pasha, .pashaAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 60, height: 60)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .pashaAccent.opacity(0.35), radius: 16, y: 6)
            }
            .offset(y: -2)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(onCaptured: { receipt in
                capturedReceipt = receipt
            })
        }
        .sheet(item: $capturedReceipt) { receipt in
            NavigationStack { ReceiptDetailView(receipt: receipt) }
        }
        .preferredColorScheme(.dark)
        .task {
            CustomCategory.seedIfNeeded(context: modelContext)
            #if DEBUG
            SeedTestData.seed(context: modelContext)
            #endif
        }
    }
}

// MARK: - Brand Colors

extension Color {
    /// Primary cyan: #4CC9F0
    static let pasha = Color(hex: "4CC9F0")
    /// Accent magenta: #F72585
    static let pashaAccent = Color(hex: "F72585")
    /// Solana purple: #9945FF
    static let solana = Color(hex: "9945FF")
    /// Success green: #06D6A0
    static let pashaSuccess = Color(hex: "06D6A0")
    /// Warning yellow: #FFD60A
    static let pashaWarn = Color(hex: "FFD60A")
    /// Card background
    static let pashaCard = Color(hex: "16213E")
    /// Page background
    static let pashaBg = Color(hex: "0F0F1A")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Glass Card Modifier

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}
