import SwiftUI

// Shared native styling adapts to system appearance and accessibility settings.
enum LedgerStyle {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.82, green: 0.72, blue: 0.52, alpha: 1) : UIColor(red: 0.57, green: 0.46, blue: 0.29, alpha: 1)
    })
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.13, green: 0.10, blue: 0.08, alpha: 1) : UIColor(red: 0.975, green: 0.966, blue: 0.941, alpha: 1)
    })

    static func headingFont(_ size: CGFloat = 22) -> Font {
        .custom("NotoSerifSC-Regular", size: size, relativeTo: .title2)
    }
    static func labelFont(_ size: CGFloat = 16) -> Font {
        .custom("NotoSerifSC-Regular", size: size, relativeTo: .subheadline)
    }
    static func englishFont(_ size: CGFloat = 12) -> Font {
        .custom("Baskerville", size: size, relativeTo: .caption)
    }
    static let rule = Color.primary.opacity(0.16)
    static func amountFont(_ size: CGFloat) -> Font { .custom("Baskerville", size: size, relativeTo: .title) }
    private static func swatch(red: Double, green: Double, blue: Double) -> Color {
        Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            return UIColor(red: dark ? red * 0.62 + 0.32 : red,
                           green: dark ? green * 0.62 + 0.32 : green,
                           blue: dark ? blue * 0.62 + 0.32 : blue, alpha: 1)
        })
    }
    static func category(_ key: String) -> Color {
        switch key {
        case "购物": return swatch(red: 0.35, green: 0.27, blue: 0.21)
        case "餐饮": return swatch(red: 0.50, green: 0.53, blue: 0.46)
        case "居家": return swatch(red: 0.74, green: 0.66, blue: 0.55)
        case "交通": return swatch(red: 0.45, green: 0.51, blue: 0.54)
        case "订阅": return swatch(red: 0.57, green: 0.48, blue: 0.51)
        case "理发护理": return swatch(red: 0.64, green: 0.49, blue: 0.41)
        case "洗衣": return swatch(red: 0.59, green: 0.65, blue: 0.62)
        case "娱乐": return swatch(red: 0.51, green: 0.40, blue: 0.37)
        default: return swatch(red: 0.62, green: 0.58, blue: 0.51)
        }
    }

}
// Shared original ink paths unify the app icon, cover and settings mark.
struct LedgerMark: View {
    var body: some View {
        HandwrittenLedger().frame(width: 86, height: 43).accessibilityHidden(true)
    }
}
struct LedgerCover: View {
    var animated = false
    var departing = false
    var onFinished: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var subtitleVisible = false
    var body: some View {
        ZStack {
            LedgerStyle.canvas.ignoresSafeArea()
                .opacity(departing ? 0 : 1)
                .animation(reduceMotion ? nil : .timingCurve(0.22, 0.0, 0.18, 1.0, duration: 0.5).delay(0.12), value: departing)
            VStack(spacing: 14) {
                HandwrittenLedger(progress: animated && !reduceMotion ? progress : 1)
                    .frame(width: 268, height: 134)
                VStack(spacing: 13) {
                    Rectangle().fill(LedgerStyle.accent.opacity(0.32)).frame(width: 32, height: 0.5)
                    Text("日 常 · 有 序").font(.system(size: 10)).tracking(3).foregroundStyle(.secondary)
                }.opacity(subtitleVisible || !animated || reduceMotion ? 1 : 0)
            }
            .opacity(departing ? 0 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: departing)
            .accessibilityElement(children: .ignore).accessibilityLabel("账本")
        }.task {
            guard animated else { progress = 1; subtitleVisible = true; return }
            guard !reduceMotion else { progress = 1; subtitleVisible = true; onFinished?(); return }
            withAnimation(.linear(duration: 1.05)) { progress = 1 }
            try? await Task.sleep(for: .milliseconds(1050))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { subtitleVisible = true }
            // Allow the subtitle to finish fading in, then hold the complete lockup.
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            onFinished?()
        }
    }
}
extension View {
    func ledgerCanvas() -> some View {
        self.scrollContentBackground(.hidden).background(LedgerStyle.canvas)
    }
}
struct QuickStartView: View {
    @Environment(\.dismiss) private var dismiss
    var onFinish: () -> Void = {}
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    LedgerMark()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("生活有数，\n花钱有度。").font(LedgerStyle.headingFont(28))
                        Text("你的私人美元账本。无需注册，截图或手动记录，数据留在设备上。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        step("1", "先定自己的额度", "预算可以稍后填写，也可以随时调整。")
                        step("2", "选截图，核对后保存", "单笔付款或多笔账单都可以。疑似重复的消费会提醒你核对。")
                        step("3", "看看花在哪，再做备份", "在“周期”查看花费，在“设置”保存账本副本，换机时再找回。")
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    Label("周期起始日可在设置中修改。预算每期单独填写，支持美元消费及关联退款。", systemImage: "calendar")
                        .font(.footnote).foregroundStyle(.secondary)
                    NavigationLink { BudgetEditor() } label: {
                        Label("先设置我的预算", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                    Button { onFinish(); dismiss() } label: {
                        Text("开始记账").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("welcome.finish")
                }.padding(24)
            }.background(LedgerStyle.canvas).navigationTitle("欢迎使用").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { onFinish(); dismiss() } } }
        }.tint(LedgerStyle.accent)
    }
    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.system(.headline, design: .rounded)).foregroundStyle(LedgerStyle.accent)
                .frame(width: 30, height: 30).background(LedgerStyle.accent.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(title)).font(.headline)
                Text(LocalizedStringKey(detail)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct EditorialAction: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: symbol).font(.system(size: 19, weight: .ultraLight))
                .foregroundStyle(LedgerStyle.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 7) {
                Text(LocalizedStringKey(title)).font(LedgerStyle.labelFont(17)).foregroundStyle(.primary)
                Text(LocalizedStringKey(detail)).font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .light)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 18).contentShape(Rectangle())
            .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityHint(detail)
    }
}

// A root overlay cannot cover a presented sheet. Protect each modal surface too.
private struct LedgerPrivacyProtection: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .accessibilityHidden(scenePhase != .active)
            .overlay {
                if scenePhase != .active {
                    LedgerCover().ignoresSafeArea().accessibilityIdentifier("privacy.modalCover")
                }
            }
    }
}
extension View {
    func privacyProtected() -> some View { modifier(LedgerPrivacyProtection()) }
}

// Shared exit policy for transaction editors: explicit discard, never a silent swipe loss.
struct UnsavedChangesGuard: ViewModifier {
    let dirty: Bool
    @Binding var requested: Bool
    let discard: () -> Void
    func body(content: Content) -> some View {
        content.interactiveDismissDisabled(dirty)
            .alert("放弃未保存的修改？", isPresented: $requested) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃修改", role: .destructive, action: discard)
            } message: { Text("关闭后，本次尚未保存的内容将丢失。已保存的账目不会改变。") }
    }
}
