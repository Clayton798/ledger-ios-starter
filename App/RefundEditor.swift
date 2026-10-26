import SwiftUI

struct RefundEditor: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let entryID: String
    @State private var amount = ""
    @State private var date = LedgerDate.string(Date())
    @State private var note = ""
    @State private var error: String?
    @State private var confirm = false
    @FocusState private var inputFocused: Bool
    private var entry: Entry? { store.ledger.entries.first { $0.id == entryID } }
    var body: some View {
        NavigationStack {
            Form {
                if let entry {
                    Section {
                        Text(L10n.merchant(entry.merchant)).font(LedgerStyle.labelFont(22))
                        LabeledContent("原消费", value: Money.display(entry.amount))
                        LabeledContent("已退款", value: Money.display(entry.refunded))
                        LabeledContent("可退款", value: Money.display(entry.netAmount))
                        Text(L10n.format("这笔退款将减少 %@ 的支出。", L10n.period(store.ledger.settings.cycleKey(for: entry.date), settings: store.ledger.settings)))
                            .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("refund.affectedPeriod")
                    }
                    Section("本次退款") {
                        TextField("金额（USD，例如 12.50）", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("refund.amount").focused($inputFocused)
                        Button("退还全部剩余金额") { amount = Money.decimal(entry.netAmount) }
                        TextField("日期（YYYY-MM-DD）", text: $date).accessibilityIdentifier("refund.date").focused($inputFocused)
                        TextField("备注（可选）", text: $note).focused($inputFocused)
                        Text("退款抵扣原消费所属周期，保留实际退款日期，不计为收入。仅记录已经到账的退款。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.ledgerCanvas().navigationTitle("记录退款")
                .safeAreaInset(edge: .top) {
                    HStack {
                        Button("取消") { dismiss() }
                        Spacer()
                        Button("确认并保存") { inputFocused = false; confirm = true }
                            .disabled(entry == nil || entry?.netAmount == 0)
                    }.padding(.horizontal, 24).padding(.vertical, 12).background(LedgerStyle.canvas)
                }
                .alert("确认退款已到账？", isPresented: $confirm) {
                    Button("取消", role: .cancel) {}
                    Button("保存退款") { save() }
                } message: { Text("保存后将减少原消费所属周期的支出。") }
                .alert("未保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(L10n.text(error ?? "")) }
        }
    }
    private func save() {
        do {
            guard let cents = L10n.cents(amount), cents > 0 else { throw LedgerError.invalid("请输入大于 0 的美元金额，最多两位小数。") }
            let day = date.trimmingCharacters(in: .whitespacesAndNewlines)
            guard day <= LedgerDate.string(Date()) else { throw LedgerError.invalid("退款日期不能是未来日期。") }
            var next = store.ledger
            try next.addRefund(Refund(amount: cents, date: day, note: note.isEmpty ? nil : note), to: entryID)
            try store.commit(next); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
