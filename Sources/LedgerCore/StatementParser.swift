import Foundation

public struct OCRLine: Sendable {
    public var text: String
    public var x: Double
    public var y: Double
    public var height: Double
    public init(text: String, x: Double, y: Double, height: Double) {
        self.text = text; self.x = x; self.y = y; self.height = height
    }
}
public struct StatementRow: Identifiable, Sendable {
    public var id: String
    public var text: String
    public var merchant: String
    public var amount: String
    public var date: String
    public var explicitUSD: Bool
    public var blockedReason: String?
    public var fingerprint: String
}
public struct StatementResult: Identifiable, Sendable {
    public var id = UUID()
    public var rows: [StatementRow]
    public var text: String
    public var notice: String
}
public enum StatementParser {
    // Normalized Vision boxes use bottom-left coordinates. Merge columns only when
    // their vertical centers overlap; never treat the whole image as one receipt.
    public static func parse(_ observations: [OCRLine]) -> StatementResult {
        let ordered = observations.sorted { $0.y > $1.y }
        var groups: [[OCRLine]] = []
        for line in ordered {
            if let last = groups.last, let anchor = last.first,
               abs(anchor.y - line.y) < min(anchor.height, line.height) * 0.55 {
                groups[groups.count - 1].append(line)
            } else { groups.append([line]) }
        }
        let lines = groups.map { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: "  ") }
        let text = lines.joined(separator: "\n")
        let global = ReceiptParser.parse(text)
        let currencyBlocked = global.blockedReason?.contains("币种") == true
        let moneyPattern = #"(?:(?:USD|US\s*\$|\$|美元|美金)\s*[-−+]?\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?(?![0-9.,])|[-−+]?[0-9][0-9,]*\.[0-9]{2}(?![0-9.,])(?:\s*(?:USD|美元|美金))?)"#
        var rows: [StatementRow] = []
        var contextDate = ""
        var previous = ""
        for (index, raw) in lines.enumerated() {
            let line = raw.precomposedStringWithCompatibilityMapping
            let parsed = ReceiptParser.parse(line)
            let hits = ReceiptParser.matches(moneyPattern, line)
            // Relative dates belong to the capture day, never the import day.
            // Clear inherited headings even when the relative label shares a money row.
            if parsed.dates.count > 1 || ReceiptParser.has(#"今天|昨天|前天|明天|今日|昨日|\b(?:today|yesterday|tomorrow)\b"#, line) { contextDate = "" }
            guard !hits.isEmpty else {
                if parsed.dates.count == 1 { contextDate = parsed.dates[0] }
                else if ReceiptParser.has(#"[0-9]{1,2}[月/-][0-9]{1,2}|今天|昨天|today|yesterday"#, line) { contextDate = "" }
                previous = line; continue
            }
            if ReceiptParser.has(#"^\s*(?:合计|总计|总支出|余额|可用额度|账单金额|最低还款|total(?: spent| paid)?|balance|available|minimum due)\s*[:：]?\s*(?:USD|US\$|\$|[0-9])"#, line) { previous = ""; continue }
            var reason = currencyBlocked ? "截图含其他币种，请使用仅包含 USD 的账单。" : parsed.blockedReason
            if ReceiptParser.has(#"退款|退回|收入|转入|还款|\b(?:refund|credit|reversal|deposit|payment received)\b|\+\s*(?:USD|US\$|\$)?\s*[0-9]"#, line) {
                reason = "退款、收入或还款不能记作消费。"
            }
            let signed = hits.contains { ReceiptParser.has(#"[-−+]"#, $0[0]) }
            if signed && reason == nil { reason = "金额带正负号，无法确定收支方向；请单独核对后手动记账。" }
            if hits.count != 1 { reason = "同一行有多个金额，无法确定交易金额；请单独手动记账。" }
            let number = hits.count == 1 ? ReceiptParser.matches(#"[0-9][0-9,]*(?:\.[0-9]{1,2})?"#, hits[0][0]).first?.first ?? "" : ""
            let amount = Money.cents(number).map(Money.decimal) ?? ""
            var merchant = line.replacingOccurrences(of: moneyPattern, with: "", options: [.regularExpression, .caseInsensitive])
            merchant = merchant.replacingOccurrences(of: #"20[0-9]{2}[年/.-][0-9]{1,2}[月/.-][0-9]{1,2}日?|\b[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?\b"#, with: "", options: .regularExpression)
            merchant = merchant.replacingOccurrences(of: #"^(?:商家|商户|merchant|消费|支出|金额|amount)[:：\s]*"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespacesAndNewlines)
            if merchant.isEmpty && ReceiptParser.parse(previous).dates.isEmpty && !ReceiptParser.has(#"USD|美元|账单|明细|statement|transactions"#, previous) { merchant = previous }
            if !parsed.merchant.isEmpty { merchant = parsed.merchant }
            // Full-image + visual-row identity keeps equal-amount rows separate and
            // rejects importing the same image row again, including partial imports.
            let fingerprint = "statement-" + ReceiptParser.fingerprint(text) + "-" + String(index)
            rows.append(StatementRow(id: String(index), text: line, merchant: String(merchant.prefix(100)), amount: amount, date: parsed.dates.count == 1 ? parsed.dates[0] : contextDate, explicitUSD: global.explicitUSD && !currencyBlocked, blockedReason: reason, fingerprint: fingerprint))
            previous = ""
        }
        return StatementResult(rows: rows, text: text, notice: "按图片中的金额行拆分，可能漏行或错配商家。请对照原图核对笔数、日期、金额和收支方向；总额与余额不入账。只支持正向 USD 消费，不能自动换汇。")
    }
}

extension Ledger {
    public func addingBatch(_ entries: [Entry], allowPossibleDuplicates: Bool = false) throws -> Ledger {
        guard !entries.isEmpty, entries.count <= 200 else { throw LedgerError.invalid("请选择 1 至 200 笔消费。") }
        var next = self
        var ids = Set<String>()
        for entry in entries {
            guard ids.insert(entry.id).inserted, !next.entries.contains(where: { $0.id == entry.id }) else { throw LedgerError.conflict }
            if !allowPossibleDuplicates && next.possibleDuplicate(of: entry) { throw LedgerError.invalid("发现同日、同商家、同金额的疑似重复消费，请逐笔核对。") }
            try next.upsert(entry)
        }
        return next
    }
}


public enum StatementDuplicate: Equatable, Sendable {
    case new, suspected, exact
}
extension Ledger {
    public func statementDuplicate(merchant: String, amount: String, date: String, fingerprint: String) -> StatementDuplicate {
        if entries.contains(where: { $0.voidedAt == nil && !fingerprint.isEmpty && $0.fingerprint == fingerprint }) { return .exact }
        guard let cents = Money.cents(amount), LedgerDate.valid(date), !Categories.merchantKey(merchant).isEmpty else { return .new }
        let candidate = Entry(amount: cents, merchant: merchant, date: date, category: "其他")
        return possibleDuplicate(of: candidate) ? .suspected : .new
    }
}
