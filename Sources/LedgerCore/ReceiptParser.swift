import Foundation

public struct ReceiptResult: Sendable {
    public var amounts: [Int] = []
    public var dates: [String] = []
    public var merchant = ""
    public var explicitUSD = false
    public var blockedReason: String?
    public var fingerprint = ""
    public var orderHash = ""
}

public enum ReceiptParser {
    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
        }
    }
    static func has(_ pattern: String, _ text: String) -> Bool { !matches(pattern, text).isEmpty }
    // Same non-cryptographic fingerprint as the existing Scriptable v2; no raw OCR is persisted.
    public static func fingerprint(_ text: String) -> String {
        var a: UInt32 = 2166136261; var b: UInt32 = 5381
        for scalar in text.unicodeScalars where !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            // JavaScript for-of + charCodeAt(0) uses the first UTF-16 unit for supplementary scalars.
            let code = UInt32(String(scalar).utf16.first!)
            a = (a ^ code) &* 16777619; b = (b &* 33) ^ code
        }
        return String(a, radix: 16) + "-" + String(b, radix: 16)
    }
    public static func parse(_ input: String) -> ReceiptResult {
        let text = input.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: "\r", with: "")
        var result = ReceiptResult(); result.fingerprint = fingerprint(text)
        result.explicitUSD = has(#"\bUSD\b|\bUS\s*\$|美元|美金"#, text)
        if has(#"\b(?:CNY|RMB|HKD|CAD|AUD|SGD|NZD|TWD|EUR|JPY|GBP|KRW|INR|CHF|THB|MYR|PHP|IDR|VND|AED|SAR|MXN|BRL|ZAR)\b|人民币|港币|港元|欧元|日元|英镑|加元|加拿大元|澳元|澳币|新加坡元|新币|台币|韩元|卢比|瑞士法郎|泰铢|[¥￥€£₹₩]|(?:HK|CA|AU|NZ|SG|NT)\s*\$|\b(?:C|A|S)\$"#, text) {
            result.blockedReason = "检测到其他币种或混合币种。本版仅记 USD，不换汇；请改选仅包含美元消费的截图。"
        } else if has(#"退款成功|已退款|已退货|部分退款|退款到账|退款已完成|\bpartial(?:ly)?\s+refund(?:ed)?\b|\brefund\s+amount\s*[:：]?\s*(?:USD|US\$|\$)?\s*[0-9]|退款处理中|退款中|退款金额\s*[:：]?\s*(?:USD|US\$|\$)?\s*[0-9]|(?:交易|订单|支付)(?:状态\s*[:：]?\s*)?(?:已)?(?:撤销|冲正)|已撤销|已冲正|冲正成功|退货成功|\brefunded\b|\brefund\s+(?:completed|successful|pending|processing)\b|\b(?:payment|transaction|order)\s+(?:reversed|voided)\b|\bstatus\s*:\s*(?:refund|reversed|voided)\b"#, text) || has(#"[-−]\s*[0-9][0-9,.]*\s*(?:USD|美元|美金)|\(\s*[0-9][0-9,.]*\s*(?:USD|美元|美金)\s*\)|[-−]\s*(?:US\s*\$|\$|USD|美元)\s*[0-9]|(?:实付|支付金额|交易金额|amount|total)[:：\s]*[-−]\s*[0-9]|(?:USD|US\s*\$|\$|美元)\s*[-−]\s*[0-9]|\(\s*(?:USD|US\$|\$)\s*[0-9]"#, text.replacingOccurrences(of: #"20[0-9]{2}[-/.][0-9]{1,2}[-/.][0-9]{1,2}"#, with: "", options: .regularExpression)) {
            result.blockedReason = "检测到退款、冲正或负金额。本版只记录正向消费，不支持退款冲抵；不要将退款记作新支出。"
        } else if has(#"待支付|支付失败|交易失败|处理中|\b(?:payment|transaction)\s+(?:failed|pending|processing)\b"#, text) {
            result.blockedReason = "支付尚未成功，不能记作已发生消费。"
        }
        let number = #"([0-9][0-9,]*(?:\.[0-9]{1,2})?)(?![0-9.,])"#
        let patterns = [#"(?:\bUSD\b|\bUS\s*\$|美元|美金|\$)\s*"# + number, #"(?:^|[^[0-9].,])"# + number + #"\s*(?:\bUSD\b|美元|美金)"#, #"(?:实付款|实付|支付金额|付款金额|交易金额|消费金额|合计|amount paid|total paid|amount|total)[:：\s]*(?:(?:USD|US\$|美元|\$)\s*)?"# + number]
        for pattern in patterns {
            for hit in matches(pattern, text) {
                if let n = Money.cents(hit[1]), n > 0, !result.amounts.contains(n) { result.amounts.append(n) }
            }
        }
        for hit in matches(#"(20[0-9]{2})[年/.-]([0-9]{1,2})[月/.-]([0-9]{1,2})日?"#, text) {
            let date = String(format: "%@-%02d-%02d", hit[1], Int(hit[2])!, Int(hit[3])!)
            if LedgerDate.valid(date), !result.dates.contains(date) { result.dates.append(date) }
        }
        // English receipts commonly print Oct 25, 2026 or 25 October 2026.
        for pattern in [#"\b[A-Za-z]{3,9}\s+[0-9]{1,2},?\s+20[0-9]{2}\b"#, #"\b[0-9]{1,2}\s+[A-Za-z]{3,9}\s+20[0-9]{2}\b"#] {
            for hit in matches(pattern, text) {
                for format in ["MMM d yyyy", "MMMM d yyyy", "d MMM yyyy", "d MMMM yyyy"] {
                    let f = LedgerDate.formatter(); f.dateFormat = format
                    if let date = f.date(from: hit[0].replacingOccurrences(of: ",", with: "")) {
                        let string = LedgerDate.string(date)
                        if LedgerDate.valid(string), !result.dates.contains(string) { result.dates.append(string) }
                    }
                }
            }
        }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for (i, line) in lines.enumerated() {
            if let hit = matches(#"^(?:商户名称|商户全称|商家|收款方|收款商户|交易商户|商户|merchant(?: name)?|paid to|payee)[:：\s]*(.*)$"#, line).first {
                result.merchant = String((hit[1].isEmpty && i + 1 < lines.count ? lines[i + 1] : hit[1]).prefix(100)); break
            }
        }
        if let hit = matches(#"(?:交易单号|交易流水号|订单号|商户单号|transaction\s*(?:id|number)|order\s*(?:id|number))[:：\s#]*([A-Za-z0-9-]{8,64})"#, text).first { result.orderHash = fingerprint(hit[1]) }
        return result
    }
}
