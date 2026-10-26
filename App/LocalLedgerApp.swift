import SwiftUI

@main struct LocalLedgerApp: App {
    @AppStorage("appLanguage") private var language = "zh-Hans"
    @StateObject private var store = LedgerStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opening = true
    @State private var revealing = false
    var body: some Scene {
        WindowGroup {
            ZStack {
                LedgerStyle.canvas.ignoresSafeArea()
                RootView().environmentObject(store)
                    .allowsHitTesting(!opening)
                    .accessibilityHidden(opening)
                if opening && scenePhase == .active {
                    LedgerCover(animated: true, departing: revealing) {
                        guard !revealing else { return }
                        if reduceMotion { opening = false; return }
                        revealing = true
                    }.accessibilityIdentifier("opening.cover")
                        .task(id: revealing) {
                            guard revealing else { return }
                            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                            opening = false
                        }
                }
            }
                .overlay {
                    if scenePhase != .active {
                        LedgerCover().accessibilityIdentifier("privacy.cover")
                    }
                }
                .alert("提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("知道了", role: .cancel) { store.error = nil }
                } message: { Text(L10n.text(store.error ?? "")) }
                .environment(\.locale, Locale(identifier: language))
        }
    }
}
