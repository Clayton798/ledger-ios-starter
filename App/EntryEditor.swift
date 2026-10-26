import SwiftUI

struct EntryEditor: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let draft: Draft
    private let initialValues: [String]
    @State private var leaving = false
    @FocusState private var inputFocused: Bool
    private var dirty: Bool { !blocked && savedMessage == nil && (draft.receipt != nil || [amount, merchant, date, note, category, String(currencyConfirmed)] != initialValues) }
    private func close() { inputFocused = false; if dirty { leaving = true } else { dismiss() } }
    @State private var amount: String
    @State private var merchant: String
    @State private var date: String
    @State private var note: String
    @State private var category: String
    @State private var categoryWasChosen = false
    @State private var currencyConfirmed: Bool
    @State private var error: String?
    @State private var pending: Entry?
    @State private var askVoid = false
    @State private var showRefund = false
    @State private var refundToVoid: String?
    private var currentEntry: Entry? { store.ledger.entries.first { $0.id == draft.entry?.id } }
    @State private var savedMessage: String?
    init(draft: Draft, ledger: Ledger) {
        self.draft = draft
        _note = State(initialValue: draft.entry?.note ?? "")
        let receipt = draft.receipt
        _amount = State(initialValue: draft.entry.map { Money.decimal($0.amount) } ?? (receipt?.amounts.count == 1 ? Money.decimal(receipt!.amounts[0]) : ""))
        _merchant = State(initialValue: draft.entry?.merchant ?? receipt?.merchant ?? "")
        _date = State(initialValue: draft.entry?.date ?? (receipt == nil ? LedgerDate.string(Date()) : (receipt!.dates.count == 1 ? receipt!.dates[0] : "")))
        _category = State(initialValue: draft.entry?.category ?? ledger.suggestedCategory(for: receipt?.merchant ?? ""))
        _currencyConfirmed = State(initialValue: draft.entry != nil || receipt == nil || receipt?.explicitUSD == true)
        initialValues = [_amount.wrappedValue, _merchant.wrappedValue, _date.wrappedValue, _note.wrappedValue, _category.wrappedValue, String(_currencyConfirmed.wrappedValue)]
    }
    var blocked: Bool { draft.receipt?.blockedReason != nil || draft.entry?.voidedAt != nil }
    var body: some View {
        NavigationStack {
            Form {
                if let reason = draft.receipt?.blockedReason { Section("无法保存此截图") { Text(L10n.text(reason)).foregroundStyle(.orange) } }
                if draft.entry?.voidedAt != nil { Text("此记录已作废，保留供备份核对，不计入支出。").foregroundStyle(.secondary) }
                if let receipt = draft.receipt {
                    Section("识别提示") {
                        Text("识别可能有误，请逐项核对。多笔交易请分别截取；多个金额不会相加。")
                        if receipt.amounts.count > 1 {
                            Text("发现多个金额，请选出这一笔的实际支付金额。").foregroundStyle(.orange)
                            ForEach(receipt.amounts, id: \.self) { cents in
                                Button(Money.display(cents)) { amount = Money.decimal(cents) }
                            }
                        } else if receipt.amounts.isEmpty { Text("未识别到金额，请手动输入。").foregroundStyle(.orange) }
                        if receipt.dates.count != 1 { Text("截图日期不明确，请填写实际消费日期。图片里的“今天／昨天”不能按导入当天计算。").foregroundStyle(.orange) }
                        DisclosureGroup("查看识别文字（仅本次显示）") { Text(draft.text).font(.caption).textSelection(.enabled) }
                    }
                }
                Section("消费信息") {
                    if !merchant.isEmpty {
                        Text("已支出 \(amount) USD · \(L10n.merchant(merchant))").font(.subheadline)
                        if L10n.merchant(merchant) != merchant { Text("原商家名：\(merchant)").font(.caption).foregroundStyle(.secondary) }
                    }
                    TextField("金额（USD，例如 12.50）", text: $amount).keyboardType(.decimalPad).focused($inputFocused)
                    TextField("商家", text: $merchant).focused($inputFocused)
                        .onChange(of: merchant) { _, value in
                            if draft.entry == nil && !categoryWasChosen { category = store.ledger.suggestedCategory(for: value) }
                        }
                    TextField("日期 YYYY-MM-DD", text: $date).keyboardType(.numbersAndPunctuation).focused($inputFocused)
                    if LedgerDate.valid(date.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        Text(L10n.format("计入周期：%@", L10n.period(store.ledger.settings.cycleKey(for: date.trimmingCharacters(in: .whitespacesAndNewlines)), settings: store.ledger.settings)))
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("entry.period")
                    }
                    TextField("备注（可选）", text: $note).focused($inputFocused)
                    Picker("分类", selection: Binding(get: { category }, set: { category = $0; categoryWasChosen = true })) { ForEach(store.ledger.visibleCategories(selected: category), id: \.self) { Text(L10n.text(Categories.title($0))).tag($0) } }.accessibilityIdentifier("entry.category").accessibilityValue(L10n.text(Categories.title(category)))
                    Button("按商家建议分类") { categoryWasChosen = false; category = store.ledger.suggestedCategory(for: merchant) }
                    Text(store.ledger.rememberedCategory(for: merchant) == nil ? "保存后会记住此商家的分类，下次自动填好。" : "已参考你上次保存的同名商家分类，仍可修改。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(L10n.text(Categories.guidance)).font(.caption).foregroundStyle(.secondary)
                }.disabled(blocked)
                if !blocked {
                    Section {
                        if draft.receipt != nil && draft.receipt?.explicitUSD != true {
                            Toggle("确认币种为美元 USD", isOn: $currencyConfirmed)
                        } else {
                            Label("美元 USD · 不换汇", systemImage: "dollarsign.circle")
                        }
                        Text("请核对上方信息。点击右上方“确认并保存”即确认这是一笔正向美元消费。")
                            .font(.footnote)
                        Text("仅有 $ 不能确定币种。请对照原付款页面确认；退款请在原消费中单独记录；不支持冲正或其他币种。").font(.caption).foregroundStyle(.secondary)
                    }
                    if let current = currentEntry {
                        Section("退款记录") {
                            LabeledContent("实际支出", value: Money.display(current.netAmount))
                            ForEach(current.refunds ?? []) { refund in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(refund.date + " · " + Money.display(refund.amount))
                                        if let note = refund.note { Text(note).font(.caption) }
                                        if refund.voidedAt != nil { Text("已作废").font(.caption) }
                                    }
                                    Spacer()
                                    if refund.voidedAt == nil { Button("作废退款", role: .destructive) { refundToVoid = refund.id }.font(.caption) }
                                }
                            }
                            Button("记录退款") { showRefund = true }.disabled(current.netAmount == 0)
                            Button("返回账目") { close() }
                        }
                        Section { Button("作废此笔", role: .destructive) { askVoid = true } }
                    }
                }
            }.ledgerCanvas().scrollDismissesKeyboard(.interactively).navigationTitle(draft.entry == nil ? "核对并保存" : "编辑记录")
                .sheet(isPresented: $showRefund) { if let current = currentEntry { RefundEditor(entryID: current.id).privacyProtected() } }
                .alert("作废这笔退款？", isPresented: Binding(get: { refundToVoid != nil }, set: { if !$0 { refundToVoid = nil } })) {
                    Button("取消", role: .cancel) { refundToVoid = nil }
                    Button("作废退款", role: .destructive) {
                        if var current = currentEntry, let index = current.refunds?.firstIndex(where: { $0.id == refundToVoid }) {
                            current.refunds?[index].voidedAt = ISO8601DateFormatter().string(from: Date())
                            do { try store.save(current) } catch { self.error = error.localizedDescription }
                        }
                        refundToVoid = nil
                    }
                } message: { Text("退款记录仍保留，原消费的实际支出会相应恢复。") }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { close() } }
                    if !blocked {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("确认并保存") { inputFocused = false; prepareSave() }.disabled(!currencyConfirmed || !store.ready)
                        }
                    }
                }
                .alert("未保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(L10n.text(error ?? "")) }
                .alert("疑似重复消费", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                    Button("取消", role: .cancel) { pending = nil }
                    Button("确认是另一笔，保存") { if let entry = pending { save(entry) }; pending = nil }
                } message: { Text("同一天已有相同商家、相同金额的记录，请确认确实是另一笔消费。") }
                .alert("确认作废？", isPresented: $askVoid) {
                    Button("取消", role: .cancel) {}
                    Button("作废", role: .destructive) { if let entry = draft.entry { store.void(entry); if store.error == nil { dismiss() } } }
                } message: { Text("原记录仍保留在备份中，但不再计入支出。作废不能代替部分退款记账。") }
                .alert("已保存", isPresented: Binding(get: { savedMessage != nil }, set: { if !$0 { savedMessage = nil; dismiss() } })) {
                    Button("完成") { dismiss() }
                } message: { Text(L10n.text(savedMessage ?? "")) }
        }.modifier(UnsavedChangesGuard(dirty: dirty, requested: $leaving) { dismiss() })
    }
    func prepareSave() {
        guard currencyConfirmed, !blocked else { error = "请确认美元币种；退款或其他币种不能保存。"; return }
        guard let cents = L10n.cents(amount), cents > 0 else { error = "请输入大于 0 的美元金额，最多两位小数。"; return }
        var entry = currentEntry ?? draft.entry ?? Entry(amount: cents, merchant: merchant, date: date, category: category, fingerprint: draft.receipt?.fingerprint ?? "", orderHash: draft.receipt?.orderHash ?? "")
        entry.note = note.isEmpty ? nil : note
        entry.amount = cents; entry.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines); entry.date = date.trimmingCharacters(in: .whitespacesAndNewlines); entry.category = category
        if draft.entry != nil { entry.updatedAt = ISO8601DateFormatter().string(from: Date()) }
        do {
            try entry.validate()
            if store.ledger.duplicate(of: entry) { throw LedgerError.duplicate }
            if store.ledger.possibleDuplicate(of: entry) { pending = entry } else { save(entry) }
        } catch { self.error = error.localizedDescription }
    }
    func save(_ entry: Entry) {
        do {
            try store.save(entry)
            let month = store.ledger.settings.cycleKey(for: entry.date), used = store.ledger.cycleSpent(category: entry.category, cycle: month)
            var message = L10n.format("%@ · %@ · 已花 %@", L10n.period(month, settings: store.ledger.settings), L10n.text(Categories.title(entry.category)), Money.display(used))
            if let limit = store.ledger.settings.limit(entry.category, month: month) {
                message += "\n" + L10n.format("%@ · %@ %@", L10n.text(store.ledger.cycleStatus(category: entry.category, cycle: month)), L10n.text(used > limit ? "超出" : "剩余"), Money.display(abs(limit - used)))
            } else { message += "\n" + L10n.text("尚未设置此分类预算。") }
            savedMessage = message
        } catch { self.error = error.localizedDescription }
    }
}
