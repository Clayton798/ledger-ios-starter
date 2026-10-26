import SwiftUI

@main struct LocalLedgerApp: App {
    @StateObject private var store = LedgerStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opening = true
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .overlay {
                    if scenePhase != .active {
                        LedgerCover().accessibilityIdentifier("privacy.cover")
                    } else if opening {
                        LedgerCover(animated: true) {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { opening = false }
                        }.transition(.opacity).accessibilityIdentifier("opening.cover")
                    }
                }
                .alert("提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("知道了", role: .cancel) { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}
