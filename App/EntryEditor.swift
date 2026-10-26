import SwiftUI

struct EntryEditor: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let draft: Draft
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
                    TextField("金额（USD，例如 12.50）", text: $amount).keyboardType(.decimalPad)
                    TextField("商家", text: $merchant)
                        .onChange(of: merchant) { _, value in
                            if draft.entry == nil && !categoryWasChosen { category = store.ledger.suggestedCategory(for: value) }
                        }
                    TextField("日期 YYYY-MM-DD", text: $date).keyboardType(.numbersAndPunctuation)
                    TextField("备注（可选）", text: $note)
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
                        Text("仅有 $ 不能确定币种。请对照原付款页面确认；本版不记退款、冲正或其他币种。").font(.caption).foregroundStyle(.secondary)
                    }
                    if draft.entry != nil { Section { Button("作废此笔", role: .destructive) { askVoid = true } } }
                }
            }.ledgerCanvas().scrollDismissesKeyboard(.interactively).navigationTitle(draft.entry == nil ? "核对并保存" : "编辑记录")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                    if !blocked {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("确认并保存") { prepareSave() }.disabled(!currencyConfirmed || !store.ready)
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
        }
    }
    func prepareSave() {
        guard currencyConfirmed, !blocked else { error = "请确认美元币种；退款或其他币种不能保存。"; return }
        guard let cents = L10n.cents(amount), cents > 0 else { error = "请输入大于 0 的美元金额，最多两位小数。"; return }
        var entry = draft.entry ?? Entry(amount: cents, merchant: merchant, date: date, category: category, fingerprint: draft.receipt?.fingerprint ?? "", orderHash: draft.receipt?.orderHash ?? "")
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
            let month = LedgerDate.cycleKey(for: entry.date, startDay: store.ledger.settings.startDay), used = store.ledger.cycleSpent(category: entry.category, cycle: month)
            var message = L10n.format("%@ · %@ · 已花 %@", L10n.period(month, startDay: store.ledger.settings.startDay), L10n.text(Categories.title(entry.category)), Money.display(used))
            if let limit = store.ledger.settings.limit(entry.category, month: month) {
                message += "\n" + L10n.format("%@ · %@ %@", L10n.text(store.ledger.cycleStatus(category: entry.category, cycle: month)), L10n.text(used > limit ? "超出" : "剩余"), Money.display(abs(limit - used)))
            } else { message += "\n" + L10n.text("尚未设置此分类预算。") }
            savedMessage = message
        } catch { self.error = error.localizedDescription }
    }
}
