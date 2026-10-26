import SwiftUI

private struct BatchEditRow: Identifiable {
    var id: String
    var source: StatementRow
    var selected: Bool
    var merchant: String
    var amount: String
    var date: String
    var category: String
}
struct StatementEditor: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let result: StatementResult
    @State private var rows: [BatchEditRow]
    @State private var confirmed = false
    @State private var error: String?
    @State private var saved = false
    @State private var allowDuplicates = false
    init(result: StatementResult, ledger: Ledger) {
        self.result = result
        _rows = State(initialValue: result.rows.map { row in
            BatchEditRow(id: row.id, source: row, selected: row.blockedReason == nil && ledger.statementDuplicate(merchant: row.merchant, amount: row.amount, date: row.date, fingerprint: row.fingerprint) == .new, merchant: row.merchant, amount: row.amount, date: row.date, category: ledger.suggestedCategory(for: row.merchant))
        })
    }
    var count: Int { rows.filter(\.selected).count }
    var body: some View {
        NavigationStack {
            Form {
                Section("识别到 \(rows.count) 条金额行，选择 \(count) 笔") {
                    Text(result.notice).font(.footnote)
                    if rows.isEmpty { Text("未找到可拆分的金额行，请换一张清晰账单图或手动记账。").foregroundStyle(.orange) }
                    DisclosureGroup("查看整张图片识别文字") { Text(result.text).font(.caption).textSelection(.enabled) }
                }
                ForEach($rows) { $row in
                    Section {
                        Text(row.source.text).font(.caption).foregroundStyle(.secondary)
                        let duplicate = store.ledger.statementDuplicate(merchant: row.merchant, amount: row.amount, date: row.date, fingerprint: row.source.fingerprint)
                        if duplicate == .exact {
                            Label("这张截图的此条消费已经保存，本次跳过。", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                        } else if let reason = row.source.blockedReason {
                            Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        } else {
                            if duplicate == .suspected {
                                Label("疑似已记过：日期、商家和金额相同。默认不选；若确实是另一笔，请勾选并在下方允许同额消费。", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                            }
                            Toggle("计入这笔", isOn: $row.selected)
                            TextField("商家", text: $row.merchant)
                            TextField("金额 USD", text: $row.amount).keyboardType(.decimalPad)
                            TextField("日期 YYYY-MM-DD", text: $row.date).keyboardType(.numbersAndPunctuation)
                            Picker("分类", selection: $row.category) { ForEach(store.ledger.visibleCategories(selected: row.category), id: \.self) { Text(Categories.title($0)).tag($0) } }
                            Button("按商家建议分类") { row.category = store.ledger.suggestedCategory(for: row.merchant) }
                            if !row.source.explicitUSD { Text("此图没有明确 USD 标识，请核对实际币种。").foregroundStyle(.orange).font(.caption) }
                        }
                    }
                }
                Section {
                    Toggle("已逐笔核对，所选均为美元支出", isOn: $confirmed)
                    Toggle("允许同日同商家同金额的不同消费", isOn: $allowDuplicates)
                    Text("一次保存全部所选记录；任何一笔校验失败都不会写入。相同截图行重复导入仍会被阻止。").font(.caption)
                    Button("确认保存所选消费") { save() }.disabled(!confirmed || count == 0 || !store.ready)
                }
            }.ledgerCanvas().scrollDismissesKeyboard(.interactively)
                .navigationTitle("账单批量核对")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存所选 \(count) 笔") { save() }.disabled(!confirmed || count == 0 || !store.ready) }
                }
                .alert("未保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
                .alert("已保存所选消费", isPresented: $saved) { Button("完成") { dismiss() } } message: { Text("已保存 \(count) 笔消费，可在对应月份查看。") }
        }
    }
    private func save() {
        guard confirmed else { return }
        do {
            let entries = try rows.filter(\.selected).map { row -> Entry in
                guard row.source.blockedReason == nil, let amount = Money.cents(row.amount), amount > 0 else { throw LedgerError.invalid("请检查所选金额。") }
                return Entry(amount: amount, merchant: row.merchant.trimmingCharacters(in: .whitespacesAndNewlines), date: row.date.trimmingCharacters(in: .whitespacesAndNewlines), category: row.category, fingerprint: row.source.fingerprint)
            }
            let next = try store.ledger.addingBatch(entries, allowPossibleDuplicates: allowDuplicates)
            try store.commit(next); saved = true
        } catch { self.error = error.localizedDescription }
    }
}
