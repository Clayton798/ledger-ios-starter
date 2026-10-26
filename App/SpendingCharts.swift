import SwiftUI
import Charts

struct SpendingSlice: Identifiable {
    var id: String
    var cents: Int
}
private struct SpendingDay: Identifiable {
    var id: String
    var date: Date
    var cents: Int
}
func spendingSlices(_ ledger: Ledger, cycle: String) -> [SpendingSlice] {
    ledger.visibleCategories().map { SpendingSlice(id: $0, cents: ledger.cycleSpent(category: $0, cycle: cycle)) }
        .filter { $0.cents > 0 }.sorted { $0.cents == $1.cents ? $0.id < $1.id : $0.cents > $1.cents }
}
struct SpendingRing: View {
    let slices: [SpendingSlice]
    let total: Int
    var compact = false
    var body: some View {
        Chart(slices) { slice in
            SectorMark(angle: .value("美分", slice.cents), innerRadius: .ratio(0.88), angularInset: 2)
                .foregroundStyle(LedgerStyle.category(slice.id))
                .accessibilityLabel(L10n.text(Categories.title(slice.id))).accessibilityValue(Money.display(slice.cents))
        }.chartLegend(.hidden)
            .overlay {
                VStack(spacing: 8) {
                    Text(L10n.text(compact ? "消费分类" : "本期支出")).font(.caption).foregroundStyle(.secondary)
                    Text(compact ? String(format: "%02d", slices.count) : Money.decimal(total))
                        .font(LedgerStyle.amountFont(compact ? 34 : 32)).lineLimit(1).minimumScaleFactor(0.6)
                    if !compact { Text("USD").font(.caption2).tracking(2).foregroundStyle(.secondary) }
                }.frame(maxWidth: compact ? 100 : 175).allowsHitTesting(false)
            }
    }
}
struct SpendingOverview: View {
    let ledger: Ledger
    let cycle: String
    var slices: [SpendingSlice] { spendingSlices(ledger, cycle: cycle) }
    var total: Int { ledger.cycleSpent(cycle: cycle) }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                SpendingRing(slices: slices, total: total, compact: true).frame(width: 145, height: 145)
                legend.frame(minWidth: 120)
            }
            VStack(alignment: .leading, spacing: 20) {
                SpendingRing(slices: slices, total: total, compact: true).frame(height: 175)
                legend
            }
        }
    }
    private var legend: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(slices.prefix(3)) { slice in
                HStack(spacing: 10) {
                    Rectangle().fill(LedgerStyle.category(slice.id)).frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text(Categories.title(slice.id))).font(LedgerStyle.labelFont(16))
                        Text(String(format: "%.1f%%", Double(slice.cents) / Double(max(1, total)) * 100))
                            .font(LedgerStyle.amountFont(19)).foregroundStyle(.secondary)
                    }
                }.accessibilityElement(children: .combine)
            }
            if slices.count > 3 { Text("另有 \(slices.count - 3) 类 · 在分析中查看").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
struct SpendingCharts: View {
    @EnvironmentObject private var store: LedgerStore
    let ledger: Ledger
    let cycle: String
    @AppStorage("spendingChartStyle") private var savedStyle = "环形"
    private var style: String {
        get { styles.contains(savedStyle) ? savedStyle : "环形" }
        nonmutating set { savedStyle = newValue }
    }
    private let styles = ["环形", "条形", "趋势"]
    private var total: Int { ledger.cycleSpent(cycle: cycle) }
    private var slices: [SpendingSlice] { spendingSlices(ledger, cycle: cycle) }
    private var days: [SpendingDay] {
        let rows = ledger.entries.filter { $0.voidedAt == nil && ledger.settings.inCycle($0.date, key: cycle) }
        let sums = Dictionary(grouping: rows, by: \.date).mapValues { $0.reduce(0) { $0 + $1.netAmount } }
        let end = ledger.settings.cycleEnd(cycle)
        let today = store.today
        let cutoff = max(today, rows.map(\.date).max() ?? today)
        guard var day = LedgerDate.formatter().date(from: ledger.settings.cycleStart(cycle)) else { return [] }
        var result: [SpendingDay] = []
        for _ in 0..<62 {
            let key = LedgerDate.string(day)
            guard key < end && key <= cutoff else { break }
            result.append(SpendingDay(id: key, date: day, cents: sums[key] ?? 0))
            day = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }
    var body: some View {
        HStack(spacing: 28) {
            ForEach(styles, id: \.self) { value in
                Button { style = value } label: {
                    VStack(spacing: 10) {
                        Text(LocalizedStringKey(value)).font(LedgerStyle.labelFont(16)).foregroundStyle(style == value ? .primary : .secondary)
                        Rectangle().fill(style == value ? LedgerStyle.accent : .clear).frame(height: 1)
                    }.padding(.vertical, 8)
                }.buttonStyle(.plain).accessibilityAddTraits(style == value ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }.accessibilityIdentifier("spending.chartStyle")
            .onAppear { if !styles.contains(savedStyle) { savedStyle = "环形" } }
        if style == "趋势" {
            Chart(days) { day in
                LineMark(x: .value("日期", day.date), y: .value("美元", Double(day.cents) / 100)).foregroundStyle(.teal)
                PointMark(x: .value("日期", day.date), y: .value("美元", Double(day.cents) / 100)).foregroundStyle(.teal)
                    .accessibilityLabel(day.id).accessibilityValue(Money.display(day.cents))
            }
            .chartYAxisLabel("USD / 天")
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
            .frame(height: 260).accessibilityIdentifier("spending.trend")
            Text("每日支出，非累计；未消费的日期显示为 0。显示到今天或已有记录的最后一天。").font(.caption).foregroundStyle(.secondary)
        } else if style == "环形" {
            SpendingRing(slices: slices, total: total).frame(height: 225).padding(.vertical, 12)
                .accessibilityIdentifier("spending.categories")
        }
        VStack(spacing: 0) {
            ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                Divider()
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", index + 1)).font(LedgerStyle.amountFont(15)).foregroundStyle(.secondary)
                        Rectangle().fill(LedgerStyle.category(slice.id)).frame(width: 3, height: 28)
                        Text(L10n.text(Categories.title(slice.id))).font(LedgerStyle.labelFont(16))
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(Money.decimal(slice.cents)).font(LedgerStyle.amountFont(24)).lineLimit(1).minimumScaleFactor(0.6)
                            Text(String(format: "%.1f%%", Double(slice.cents) / Double(max(1, total)) * 100)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityElement(children: .combine)
                    if style == "条形" {
                        GeometryReader { g in
                            Rectangle().fill(LedgerStyle.rule.opacity(0.35))
                            Rectangle().fill(LedgerStyle.category(slice.id))
                                .frame(width: g.size.width * Double(slice.cents) / Double(max(1, slices.first?.cents ?? 1)))
                        }.frame(height: 3).accessibilityHidden(true)
                    }
                }.padding(.vertical, 17)
            }
        }.accessibilityIdentifier(style == "条形" ? "spending.categories" : "spending.details")
        Text("按本期已保存支出计算 · USD").font(.caption).foregroundStyle(.secondary)
    }
}
