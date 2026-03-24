import SwiftUI
import SwiftData

// MARK: - Environment key for the audit-only ModelContext

private struct AuditModelContextKey: EnvironmentKey {
    static let defaultValue: ModelContext? = nil
}

extension EnvironmentValues {
    var auditModelContext: ModelContext? {
        get { self[AuditModelContextKey.self] }
        set { self[AuditModelContextKey.self] = newValue }
    }
}

@main
struct PashaApp: App {
    @StateObject private var auditManager = AuditManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    // Main container — synced to CloudKit
    let mainContainer: ModelContainer
    // Audit container — local only (immutable audit trail must NOT sync)
    let auditContainer: ModelContainer

    /// True when a persistent container could not be created and in-memory fallbacks are used.
    let containerError: Bool

    init() {
        var usedFallback = false

        // Receipt + CustomCategory → CloudKit sync
        let mainSchema = Schema([Receipt.self, CustomCategory.self])
        let mainConfig = ModelConfiguration(
            "MainStore",
            schema: mainSchema,
            cloudKitDatabase: .none // Enable .automatic for App Store with iCloud capability
        )
        let resolvedMain: ModelContainer
        do {
            resolvedMain = try ModelContainer(for: mainSchema, configurations: mainConfig)
        } catch {
            #if DEBUG
            print("[PashaApp] Failed to create main ModelContainer: \(error). Using in-memory fallback.")
            #endif
            let fallbackConfig = ModelConfiguration(
                "MainStore",
                schema: mainSchema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            resolvedMain = (try? ModelContainer(for: mainSchema, configurations: fallbackConfig))
                ?? (try! ModelContainer(for: mainSchema))
            usedFallback = true
        }
        mainContainer = resolvedMain

        // AuditLog → local only, never synced
        let auditSchema = Schema([AuditLog.self])
        let auditConfig = ModelConfiguration(
            "AuditStore",
            schema: auditSchema,
            cloudKitDatabase: .none
        )
        let resolvedAudit: ModelContainer
        do {
            resolvedAudit = try ModelContainer(for: auditSchema, configurations: auditConfig)
        } catch {
            #if DEBUG
            print("[PashaApp] Failed to create audit ModelContainer: \(error). Using in-memory fallback.")
            #endif
            let fallbackConfig = ModelConfiguration(
                "AuditStore",
                schema: auditSchema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            resolvedAudit = (try? ModelContainer(for: auditSchema, configurations: fallbackConfig))
                ?? (try! ModelContainer(for: auditSchema))
            usedFallback = true
        }
        auditContainer = resolvedAudit
        containerError = usedFallback
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auditManager)
                .environmentObject(subscriptionManager)
                .environment(\.auditModelContext, auditContainer.mainContext)
                .onAppear {
                    subscriptionManager.loadTier()
                    subscriptionManager.updateMonthlyCount(context: mainContainer.mainContext)
                }
                .overlay(alignment: .top) {
                    if containerError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("データベースの読み込みに失敗しました。データは一時保存です。")
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.85))
                    }
                }
        }
        .modelContainer(mainContainer)
    }
}
