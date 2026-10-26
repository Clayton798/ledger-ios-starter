import SwiftUI

struct LedgerHeading: View {
    var title = "账本"
    var subtitle = "PERSONAL LEDGER"
    var add: (() -> Void)?
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 9) {
                Text(LocalizedStringKey(title)).font(LedgerStyle.headingFont(23)).tracking(2)
                Text(LocalizedStringKey(subtitle)).font(LedgerStyle.englishFont(10)).tracking(2).foregroundStyle(.secondary)
            }
            Spacer()
            if let add {
                Button(action: add) { Image(systemName: "plus").font(.system(size: 21, weight: .ultraLight)).frame(width: 44, height: 44).overlay(Circle().stroke(LedgerStyle.rule, lineWidth: 0.6)) }
                    .accessibilityLabel("手动记一笔").foregroundStyle(.primary)
            }
        }.padding(.top, 16).padding(.bottom, 22)
    }
}
struct EditorialSectionTitle: View {
    let title: String
    let index: String
    var body: some View {
        HStack {
            Text(LocalizedStringKey(title)).font(LedgerStyle.labelFont(17)).tracking(1)
            Spacer()
            Text(index).font(LedgerStyle.amountFont(15)).foregroundStyle(LedgerStyle.accent)
        }
    }
}
struct DashboardView: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var date: Date
    @State private var showBudget = false
    @State private var draft: Draft?
    var cycle: String { LedgerDate.month(date) }
    var spent: Int { store.ledger.cycleSpent(cycle: cycle) }
    var categories: [String] { store.ledger.visibleCategories() }
    var limits: [Int] { categories.compactMap { store.ledger.settings.limit($0, month: cycle) } }
    var completeBudget: Bool { !limits.isEmpty && limits.count == categories.count }
    var budget: Int { limits.reduce(0, +) }
    var recent: [Entry] {
        Array(store.ledger.entries.filter { $0.voidedAt == nil && store.ledger.settings.inCycle($0.date, key: cycle) }
            .sorted { $0.date == $1.date ? $0.createdAt > $1.createdAt : $0.date > $1.date }.prefix(3))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LedgerHeading(add: store.ready ? { draft = Draft() } : nil)
                    Divider()
                    MonthSelector(date: $date).padding(.vertical, 22)
                    if store.ready {
                        summary.padding(.top, 12)
                    } else {
                        ContentUnavailableView("账本暂时无法读取", systemImage: "lock.shield", description: Text("已停止写入保护记录。请到设置保存原始文件副本，再尝试重新打开。"))
                    }
                    EditorialSectionTitle(title: "支出构成", index: "01").padding(.top, 38)
                    if spent > 0 {
                        SpendingOverview(ledger: store.ledger, cycle: cycle).padding(.top, 24)
                    } else {
                        Text("从第一笔开始。选择付款截图，或手动记录消费。")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 26)
                    }
                    EditorialSectionTitle(title: "最近记录", index: "02").padding(.top, 32)
                    ForEach(recent) { entry in
                        Button { draft = Draft(entry: entry) } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(L10n.merchant(entry.merchant)).font(LedgerStyle.labelFont(16)).lineLimit(2)
                                    if entry.refunded > 0 { Text(L10n.format("已扣除退款 %@", Money.display(entry.refunded))).font(.caption).foregroundStyle(.secondary) }
                                    Text("\(entry.date) · \(L10n.text(Categories.title(entry.category)))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 12)
                                Text(Money.decimal(entry.netAmount)).font(LedgerStyle.amountFont(23)).lineLimit(1).minimumScaleFactor(0.7)
                            }.padding(.vertical, 18).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                    if recent.isEmpty { Text("本期还没有记录").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20) }
                    NavigationLink { BudgetDetails(date: $date) } label: {
                        HStack { Text("查看分类预算"); Spacer(); Image(systemName: "arrow.right") }.font(.subheadline).padding(.vertical, 24)
                    }
                }.padding(.horizontal, 28).padding(.bottom, 12).frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }.background(LedgerStyle.canvas).toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showBudget) { NavigationStack { BudgetEditor(initialDate: date) }.privacyProtected() }
                .sheet(item: $draft) { EntryEditor(draft: $0, ledger: store.ledger).privacyProtected() }
        }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("本期已花").font(LedgerStyle.labelFont(15)).tracking(1).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(Money.decimal(spent)).font(LedgerStyle.amountFont(50)).lineLimit(1).minimumScaleFactor(0.45)
                    .accessibilityIdentifier("overview.spent")
                Text("USD").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 10)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text(completeBudget ? "本期预算" : "已设分类预算")).font(.caption).foregroundStyle(.secondary)
                    Text(L10n.text(limits.isEmpty ? "未设置" : Money.decimal(budget))).font(LedgerStyle.amountFont(23))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text(L10n.text(completeBudget ? (spent > budget ? "已超出" : "预算剩余") : "预算设置")).font(.caption).foregroundStyle(.secondary)
                    if completeBudget {
                        Text(Money.decimal(abs(budget - spent))).font(LedgerStyle.amountFont(23)).foregroundStyle(spent > budget ? .orange : .primary)
                            .accessibilityIdentifier("overview.remaining")
                    } else {
                        Button("完善预算") { showBudget = true }.font(.subheadline)
                    }
                }
            }.padding(.top, 26)
            Text("仅按已记录消费估算，已扣退款；不是银行卡余额。漏记消费会让剩余额度偏高。")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 12).accessibilityIdentifier("overview.basis")
            if completeBudget {
                GeometryReader { g in
                    Rectangle().fill(LedgerStyle.rule.opacity(0.5))
                    Rectangle().fill(spent > budget ? .orange : LedgerStyle.accent)
                        .frame(width: g.size.width * min(1, Double(spent) / Double(max(1, budget))))
                }.frame(height: 2).padding(.top, 16).accessibilityHidden(true)
            } else {
                Text("未设预算的分类不计入上方合计。").font(.caption2).foregroundStyle(.secondary).padding(.top, 12)
            }
        }
    }
}
struct AnalysisView: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var date: Date
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LedgerHeading(title: "支出构成", subtitle: "SPENDING JOURNAL")
                    Divider()
                    MonthSelector(date: $date)
                    if store.ledger.cycleSpent(cycle: LedgerDate.month(date)) > 0 {
                        SpendingCharts(ledger: store.ledger, cycle: LedgerDate.month(date))
                    } else {
                        ContentUnavailableView("本期还没有支出", systemImage: "chart.bar.xaxis", description: Text("保存消费后，就能在这里查看分类和趋势。"))
                    }
                }.padding(.horizontal, 28).padding(.bottom, 30).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(LedgerStyle.canvas).toolbar(.hidden, for: .navigationBar)
        }
    }
}
struct BudgetDetails: View {
    @State private var showBudget = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LedgerStore
    @Binding var date: Date
    var body: some View {
        List {
            MonthSelector(date: $date)
            ForEach(store.ledger.visibleCategories(), id: \.self) { BudgetRow(category: $0, month: LedgerDate.month(date)) }
            Button("调整分类预算") { showBudget = true }
        }.listStyle(.plain).ledgerCanvas().safeAreaInset(edge: .top) { Button("返回") { dismiss() }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 8).background(LedgerStyle.canvas) }.navigationTitle("预算与剩余").sheet(isPresented: $showBudget) { NavigationStack { BudgetEditor(initialDate: date) }.privacyProtected() }
    }
}
