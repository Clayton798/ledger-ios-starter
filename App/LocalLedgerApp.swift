import SwiftUI

@main struct LocalLedgerApp: App {
    @StateObject private var store = LedgerStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opening = true
    var body: some Scene {
        WindowGroup {
            ZStack {
                LedgerStyle.canvas.ignoresSafeArea()
                RootView().environmentObject(store)
                    .opacity(opening ? 0 : 1)
                    .allowsHitTesting(!opening)
                    .accessibilityHidden(opening)
                if opening && scenePhase == .active {
                    LedgerCover(animated: true) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { opening = false }
                    }.transition(.opacity).accessibilityIdentifier("opening.cover")
                }
            }
                .overlay {
                    if scenePhase != .active {
                        LedgerCover().accessibilityIdentifier("privacy.cover")
                    }
                }
                .alert("提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("知道了", role: .cancel) { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}
