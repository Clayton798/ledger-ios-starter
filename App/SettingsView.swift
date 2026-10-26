import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var importing = false
    @State private var showGuide = false
    @State private var exporting = false
    @State private var document: BackupDocument?
    @State private var incoming: Ledger?
    @State private var notice: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LedgerHeading(title: "设置", subtitle: "PERSONAL PREFERENCES")
                    Divider()
                    EditorialSectionTitle(title: "我的预算", index: "01").padding(.top, 28)
                    NavigationLink { BudgetEditor() } label: {
                        EditorialAction(title: "调整每类能花多少钱", detail: "每月 22 日开始新一期，按自己的节奏安排", symbol: "slider.horizontal.3")
                    }.disabled(!store.ready)
                    Divider()
                    EditorialSectionTitle(title: "保存与找回", index: "02").padding(.top, 30)
                    Button { exportCurrent() } label: {
                        EditorialAction(title: "保存一份账本副本", detail: "留在“文件”里，换手机时也能找回", symbol: "arrow.up.document")
                    }.disabled(!store.ready)
                    Divider()
                    Button { importing = true } label: {
                        EditorialAction(title: "从文件找回账本", detail: "保留现有消费，使用副本中的预算", symbol: "arrow.down.document")
                    }.disabled(!store.ready)
                    Divider()
                    DisclosureGroup("更多找回选项") {
                        Button("找回上次恢复前的账本") { exportPrevious() }.disabled(!store.ready).padding(.vertical, 12)
                        Text("如果恢复的文件选错了，可以先保存恢复前的副本，再用它找回记录。").font(.caption).foregroundStyle(.secondary)
                    }.font(.subheadline).padding(.vertical, 20)
                    if !store.ready {
                        Text("账本暂时无法读取，已停止写入保护记录。请保存原始副本后再尝试重新打开，不要删除 App。").font(.subheadline)
                        Button("导出原始文件副本") {
                            do { document = BackupDocument(data: try Data(contentsOf: store.disk.url)); exporting = true }
                            catch { notice = error.localizedDescription }
                        }.padding(.vertical, 16)
                    }
                    EditorialSectionTitle(title: "关于这本账", index: "03").padding(.top, 16)
                    Button { showGuide = true } label: {
                        EditorialAction(title: "快速上手指南", detail: "从记录第一笔，到整理每一期", symbol: "book")
                    }
                    Divider()
                    DisclosureGroup("隐私与使用范围") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("无需登录，没有广告。截图在手机上识别，不会自动读取银行卡消费。")
                            Text("不保存原截图和识别原文。账本只在这台设备上，不会自动云备份；删除 App 前，请先保存副本。")
                            Text("导出到 iCloud Drive 等位置由你选择，可能触发该服务同步。仅支持正向美元支出，不支持退款冲抵及汇率换算。预算提醒仅在 App 内显示，不限制银行卡消费。")
                        }.font(.caption).foregroundStyle(.secondary).lineSpacing(4).padding(.top, 12)
                    }.font(.subheadline).padding(.vertical, 20)
                    Divider()
                    HStack { LedgerMark(); Spacer(); Text("账本 · 1.9").font(LedgerStyle.englishFont(12)).foregroundStyle(.secondary) }.padding(.top, 24)
                }.buttonStyle(.plain).padding(.horizontal, 28).padding(.bottom, 30)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(LedgerStyle.canvas).toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showGuide) { QuickStartView() }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > Backup.maximumBytes { throw LedgerError.invalid("备份超过 25 MB。") }
                        let parsed = try Backup.decode(Data(contentsOf: url))
                        _ = try store.ledger.merging(parsed)
                        incoming = parsed
                    } catch { notice = "未导入：\(error.localizedDescription)" }
                }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "USD账本备份-\(LedgerDate.string(Date()))") { result in
                    switch result { case .success: notice = "账本副本已保存。换手机时，可以用这个文件找回记录。"; case .failure(let error): notice = error.localizedDescription }
                    document = nil
                }
                .alert("找回这份账本？", isPresented: Binding(get: { incoming != nil }, set: { if !$0 { incoming = nil } })) {
                    Button("取消", role: .cancel) { incoming = nil }
                    Button("找回记录并使用文件中的预算") {
                        if let data = incoming {
                            do { try store.restore(data); notice = "恢复完成，请到周期和明细核对。恢复前的副本可在此导出。" }
                            catch { notice = error.localizedDescription }
                        }
                        incoming = nil
                    }
                } message: {
                    Text("备份包含 \(incoming?.entries.count ?? 0) 条记录（含作废）。已存在的相同记录不会重复添加。你的现有消费会保留，预算会改用文件里的设置。开始前会自动留存一份当前账本。")
                }
                .alert("提示", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(notice ?? "") }
        }
    }
    func exportCurrent() {
        do { document = BackupDocument(data: try Backup.encode(store.ledger)); exporting = true } catch { notice = error.localizedDescription }
    }
    func exportPrevious() {
        do {
            let url = store.disk.url.deletingLastPathComponent().appendingPathComponent("before-restore.json")
            document = BackupDocument(data: try Data(contentsOf: url)); exporting = true
        } catch { notice = "暂无恢复前副本，或副本无法读取。\(error.localizedDescription)" }
    }
}

struct BudgetEditor: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var monthly = false
    @State private var date = LedgerDate.cycleSelection(Date())
    @State private var amounts: [String: String] = [:]
    @State private var notice: String?
    var body: some View {
        Form {
            Section {
                Toggle("仅设置指定周期", isOn: $monthly).onChange(of: monthly) { _, _ in load() }
                if monthly { MonthSelector(date: $date).onChange(of: date) { _, _ in load() } }
                Text("金额单位 USD。留空表示该分类不设预算，0 表示不计划支出。切换周期会重新载入已保存值，请先保存修改。").font(.caption).foregroundStyle(.secondary)
            }
            Section("分类金额") {
                ForEach(store.ledger.visibleCategories(), id: \.self) { category in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(Categories.title(category))
                            Text(Categories.detail(category)).font(.caption).foregroundStyle(.secondary)
                        }
                        TextField("不设预算", text: Binding(get: { amounts[category] ?? "" }, set: { amounts[category] = $0 })).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("budget." + category)
                    }
                }
            }
            Section {
                Text("先填你确定的固定支出，再给吃饭和购物留额度。洗衣可按每周次数估算；订阅按实际账单填写，未确定的先留空。").font(.caption).foregroundStyle(.secondary)
                if monthly {
                    Button("清除本期设置，沿用默认预算", role: .destructive) {
                        var next = store.ledger; next.settings.overrides.removeValue(forKey: LedgerDate.month(date))
                        do { try store.commit(next); load(); notice = "本期已恢复沿用默认预算。" } catch { notice = error.localizedDescription }
                    }
                }
            }
            Text(Categories.guidance).font(.footnote).foregroundStyle(.secondary)
        }.ledgerCanvas().scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { Button("保存预算") { save() }.buttonStyle(.borderedProminent).padding().frame(maxWidth: .infinity).background(.regularMaterial) }
            .navigationTitle("分类预算").onAppear { load() }
            .alert("预算", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(notice ?? "") }
    }
    func load() {
        for category in Categories.all {
            let value = monthly ? store.ledger.settings.limit(category, month: LedgerDate.month(date)) : (store.ledger.settings.budgets[category] ?? nil)
            amounts[category] = value.map(Money.decimal) ?? ""
        }
    }
    func save() {
        do {
            var values: [String: Int?] = [:]
            for category in Categories.all {
                let raw = (amounts[category] ?? "").trimmingCharacters(in: .whitespaces)
                if raw.isEmpty { values[category] = .some(nil) }
                else { guard let cents = Money.cents(raw) else { throw LedgerError.invalid("\(category)：请输入有效金额，最多两位小数。") }; values[category] = .some(cents) }
            }
            var next = store.ledger
            if monthly { next.settings.overrides[LedgerDate.month(date)] = values } else { next.settings.budgets = values }
            try store.commit(next); notice = "预算已保存。"
        } catch { notice = error.localizedDescription }
    }
}
