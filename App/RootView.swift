import SwiftUI
import Combine
import Charts
import PhotosUI
import UIKit

struct Draft: Identifiable {
    let id = UUID()
    var entry: Entry?
    var receipt: ReceiptResult?
    var text: String = ""
}
struct RootView: View {
    @AppStorage("appLanguage") private var language = "zh-Hans"
    @EnvironmentObject private var store: LedgerStore
    @AppStorage("welcomeCompleted") private var welcomeCompleted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let dayCheck = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var clockTimeZone = TimeZone.current
    @State private var showWelcome = false
    @State private var appeared = false
    @State private var cycleDate = LedgerDate.cycleSelection(Date())
    var body: some View {
        TabView {
            DashboardView(date: $cycleDate).tabItem { Label("周期", systemImage: "square.grid.2x2") }
            AnalysisView(date: $cycleDate).tabItem { Label("分析", systemImage: "chart.bar.xaxis") }
            EntriesView(date: $cycleDate).tabItem { Label("记账", systemImage: "list.bullet.rectangle") }
            SettingsView(date: $cycleDate).tabItem { Label("设置", systemImage: "gearshape") }
        }.id(language).tint(LedgerStyle.accent)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                if !appeared { cycleDate = store.ledger.settings.selection(Date()) }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { appeared = true }
                if !welcomeCompleted && store.ready {
                    if store.ledger.entries.isEmpty && store.ledger.settings.budgets.values.allSatisfy({ $0 == nil }) && store.ledger.settings.overrides.values.allSatisfy({ $0.values.allSatisfy({ $0 == nil }) }) {
                        showWelcome = true
                    } else { welcomeCompleted = true }
                }
            }
            .onChange(of: store.ledger.settings.startDay) { _, _ in
                cycleDate = store.ledger.settings.selection(Date())
            }
            .onReceive(dayCheck) { _ in refreshClock() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshClock() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshClock() } }
            .sheet(isPresented: $showWelcome, onDismiss: { welcomeCompleted = true }) {
                QuickStartView { welcomeCompleted = true }.privacyProtected()
            }
    }
    private func refreshClock() {
        let selected = String(LedgerDate.string(cycleDate, timeZone: clockTimeZone).prefix(7))
        let oldDay = store.today
        store.refreshToday()
        let key = selected == store.ledger.settings.cycleKey(for: oldDay) ? store.ledger.settings.cycleKey(for: store.today) : selected
        clockTimeZone = .current
        if let refreshed = LedgerDate.formatter().date(from: key + "-01") {
            cycleDate = refreshed
        }
    }
}

struct MonthSelector: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var date: Date
    var body: some View {
        VStack(spacing: 2) {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("上一期")
            Spacer(); Text(L10n.period(LedgerDate.month(date), settings: store.ledger.settings)).font(.caption).monospacedDigit(); Spacer()
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("下一期")
        }.buttonStyle(.borderless)
        if LedgerDate.month(date) != store.ledger.settings.cycleKey(for: store.today) {
            Button("回到本期") { date = store.ledger.settings.selection(Date()) }
                .font(.caption).frame(minHeight: 36).accessibilityIdentifier("period.current")
        }
        }
    }
    func move(_ delta: Int) {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        if let next = calendar.date(byAdding: .month, value: delta, to: start), LedgerDate.valid(LedgerDate.string(next)) { date = next }
    }
}

struct BudgetRow: View {
    @EnvironmentObject private var store: LedgerStore
    var category: String
    var month: String
    var body: some View {
        let spent = store.ledger.cycleSpent(category: category, cycle: month)
        let limit = store.ledger.settings.limit(category, month: month)
        let status = store.ledger.cycleStatus(category: category, cycle: month)
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(L10n.text(Categories.title(category))).font(LedgerStyle.labelFont(17)); Spacer(); Text(Money.display(spent)).monospacedDigit() }
            Text(L10n.text(Categories.detail(category))).font(.caption).foregroundStyle(.secondary)
            if let limit {
                ProgressView(value: min(Double(spent), Double(max(1, limit))), total: Double(max(1, limit))).tint(spent > limit ? .orange : LedgerStyle.accent)
                Text("\(L10n.text(status)) · \(L10n.text(spent > limit ? "超出" : "剩余")) \(Money.display(abs(limit - spent))) / 预算 \(Money.display(limit))")
                    .font(.caption).foregroundStyle(spent >= limit ? .orange : .secondary)
            } else { Text("未设预算").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 5)
    }
}

struct EntriesView: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var date: Date
    @State private var item: PhotosPickerItem?
    @State private var statementItem: PhotosPickerItem?
    @State private var statement: StatementResult?
    @State private var draft: Draft?
    @State private var busy = false
    @State private var showVoided = false
    @State private var search = ""
    @State private var allPeriods = false
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    LedgerHeading(title: "记账", subtitle: "THE DAILY JOURNAL")
                    Divider()
                    PhotosPicker(selection: $item, matching: .images) {
                        EditorialAction(title: "选择付款截图", detail: "一张付款凭证，核对后记一笔", symbol: "photo")
                    }.disabled(busy || !store.ready)
                    Divider()
                    PhotosPicker(selection: $statementItem, matching: .images) {
                        EditorialAction(title: "识别账单列表（多笔）", detail: "同一张图里的多笔消费，一起整理", symbol: "list.bullet.rectangle")
                    }.disabled(busy || !store.ready)
                    Divider()
                    Button { draft = Draft() } label: {
                        EditorialAction(title: "手动记一笔", detail: "留下一笔消费，也可以写点备注", symbol: "square.and.pencil")
                    }.disabled(busy || !store.ready)
                    Divider()
                    if busy { ProgressView("正在设备上识别…").padding(.vertical, 12) }
                    EditorialSectionTitle(title: "本期记录", index: "01").padding(.top, 32)
                    if !allPeriods { MonthSelector(date: $date).padding(.vertical, 10) }
                    if allPeriods { Text("正在查找所有周期的记录").font(.caption).foregroundStyle(.secondary).padding(.vertical, 10) }
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.footnote).foregroundStyle(.secondary)
                        TextField("搜索商家、分类或备注", text: $search).font(.subheadline)
                            .accessibilityIdentifier("entries.search").submitLabel(.search)
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") }
                    }.padding(.vertical, 12)
                    Divider()
                    Toggle("显示已作废", isOn: $showVoided).font(.caption).tint(LedgerStyle.accent).padding(.vertical, 14)
                    Picker("查找范围", selection: $allPeriods) {
                        Text("当前周期").tag(false)
                        Text("全部周期").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("entries.scope").padding(.bottom, 12)
                    let rows = store.ledger.matchingEntries(cycle: allPeriods ? nil : LedgerDate.month(date), query: search, includeVoided: showVoided) {
                        L10n.merchant($0.merchant) + " " + L10n.text(Categories.title($0.category))
                    }
                    HStack {
                        Text(L10n.format("%d 笔记录", rows.count))
                        Spacer()
                        Text(L10n.format("净支出 %@", Money.display(Ledger.netTotal(of: rows))))
                    }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 12).accessibilityIdentifier("entries.summary")
                    if showVoided { Text("合计已扣退款，不包含作废记录。").font(.caption).foregroundStyle(.secondary).padding(.bottom, 12) }
                    if rows.isEmpty { ContentUnavailableView(LocalizedStringKey(search.isEmpty ? "从第一笔开始" : "没有找到匹配记录"), systemImage: search.isEmpty ? "square.and.pencil" : "magnifyingglass", description: Text(L10n.text(search.isEmpty ? "选择付款截图，或手动记录今天的消费。" : "试试其他商家、分类或备注关键词。"))) }
                    ForEach(rows) { entry in
                        Button { draft = Draft(entry: entry) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.merchant(entry.merchant)).font(LedgerStyle.labelFont(16)).foregroundStyle(.primary)
                                    if entry.refunded > 0 { Text(L10n.format("已扣除退款 %@", Money.display(entry.refunded))).font(.caption).foregroundStyle(.secondary) }
                                    Text("\(entry.date) · \(L10n.text(Categories.title(entry.category)))\(entry.voidedAt == nil ? "" : L10n.text(" · 已作废"))").font(.caption).foregroundStyle(.secondary)
                                    if let note = entry.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                                Text(Money.display(entry.netAmount)).font(LedgerStyle.amountFont(21)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.65)
                            }.padding(.vertical, 20).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }.buttonStyle(.plain).padding(.horizontal, 28).padding(.bottom, 30)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(LedgerStyle.canvas).scrollDismissesKeyboard(.interactively).toolbar(.hidden, for: .navigationBar)
                .sheet(item: $draft) { EntryEditor(draft: $0, ledger: store.ledger).privacyProtected() }
                .sheet(item: $statement) { StatementEditor(result: $0, ledger: store.ledger).privacyProtected() }
                .onChange(of: statementItem) { _, selected in
                    guard let selected else { return }; busy = true
                    Task {
                        defer { busy = false; statementItem = nil }
                        do {
                            guard let data = try await selected.loadTransferable(type: Data.self), data.count <= 30 * 1024 * 1024 else { throw OCRFailure() }
                            let lines = try await ReceiptOCR.recognizeLines(data)
                            statement = await Task.detached(priority: .userInitiated) { StatementParser.parse(lines) }.value
                        } catch { store.error = error.localizedDescription }
                    }
                }
                .onChange(of: item) { _, selected in
                    guard let selected else { return }
                    busy = true
                    Task {
                        defer { busy = false; item = nil }
                        do {
                            guard let data = try await selected.loadTransferable(type: Data.self), data.count <= 30 * 1024 * 1024 else { throw OCRFailure() }
                            let text = try await ReceiptOCR.recognize(data)
                            let receipt = await Task.detached(priority: .userInitiated) { ReceiptParser.parse(text) }.value
                            draft = Draft(receipt: receipt, text: text)
                        } catch { store.error = error.localizedDescription }
                    }
                }
        }
    }
}
