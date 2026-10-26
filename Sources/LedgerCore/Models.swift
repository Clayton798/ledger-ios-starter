import Foundation

public enum LedgerError: Error, LocalizedError {
    case invalid(String), duplicate, conflict, unavailable
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .duplicate: return "相同截图或单号已经保存，请到明细中编辑原记录。"
        case .conflict: return "相同 ID 存在不同内容。为避免覆盖，未导入任何数据。请先导出当前账本并核对备份。"
        case .unavailable: return "账本读取失败，已停止写入以保护原文件。请先导出诊断副本或恢复有效备份。"
        }
    }
}

public enum Money {
    public static let maximum = 99_999_999_999
    public static func cents(_ input: String) -> Int? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "，", with: ",")
        guard s.range(of: #"^(?:[0-9]{1,9}|[0-9]{1,3}(?:,[0-9]{3}){1,2})(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil else { return nil }
        let parts = s.replacingOccurrences(of: ",", with: "").split(separator: ".")
        guard let whole = Int(parts[0]) else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        return whole * 100 + (Int(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0)
    }
    public static func inputCents(_ input: String, decimalComma: Bool) -> Int? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if decimalComma && value.contains(",") {
            guard value.range(of: #"^[0-9]{1,9},[0-9]{1,2}$"#, options: .regularExpression) != nil else { return nil }
            return cents(value.replacingOccurrences(of: ",", with: "."))
        }
        return cents(value)
    }
    public static func decimal(_ cents: Int) -> String {
        let n = abs(cents)
        return "\(cents < 0 ? "-" : "")\(n / 100).\(String(format: "%02d", n % 100))"
    }
    public static func display(_ cents: Int) -> String { "US$" + decimal(cents) }
}

public enum LedgerDate {
    public static func valid(_ string: String) -> Bool {
        let bytes = Array(string.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              [0,1,2,3,5,6,8,9].allSatisfy({ (48...57).contains(bytes[$0]) }) else { return false }
        let year = Int(bytes[0]-48)*1000 + Int(bytes[1]-48)*100 + Int(bytes[2]-48)*10 + Int(bytes[3]-48)
        let month = Int(bytes[5]-48)*10 + Int(bytes[6]-48)
        let day = Int(bytes[8]-48)*10 + Int(bytes[9]-48)
        return (2000...2100).contains(year) && (1...12).contains(month) && day > 0 && day <= daysInMonth(year: year, month: month)
    }
    static func daysInMonth(year: Int, month: Int) -> Int {
        guard (1...12).contains(month) else { return 0 }
        if month == 2 { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28 }
        return [4,6,9,11].contains(month) ? 30 : 31
    }
    public static func formatter() -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"
        return f
    }
    public static func string(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = formatter(); f.timeZone = timeZone; return f.string(from: date)
    }
    public static func refreshedCycle(selected: String, previousDay: String, currentDay: String, startDay: Int) -> String {
        selected == cycleKey(for: previousDay, startDay: startDay)
            ? cycleKey(for: currentDay, startDay: startDay) : selected
    }
    public static func month(_ date: Date) -> String { String(string(date).prefix(7)) }
    public static func validMonth(_ value: String) -> Bool { valid(value + "-01") || value == "1999-12" || value == "2101-01" }
}

public enum Categories {
    public static let everyday = ["餐饮", "购物", "居家", "理发护理", "洗衣", "交通", "订阅", "其他", "娱乐"]
    public static let legacy = ["医疗", "教育", "旅行"]
    public static let all = everyday + legacy
    public static func title(_ category: String) -> String {
        ["餐饮": "吃饭", "居家": "超市日用", "其他": "零星支出", "娱乐": "社交娱乐"][category] ?? category
    }
    public static func detail(_ category: String) -> String {
        ["餐饮": "食堂加餐、外卖、咖啡、外出吃饭", "购物": "衣服、鞋包、个人购物", "居家": "超市食材、纸巾、清洁与宿舍用品", "理发护理": "理发、个人护理", "洗衣": "洗衣、烘干；按实际次数和单价预留", "交通": "地铁、公交、打车", "订阅": "AI 工具、音乐、云存储等会员，按实际扣款", "其他": "快递邮寄、打印复印、配钥匙、临时维修和应急小物", "娱乐": "聚餐以外的电影、活动和朋友出游"][category] ?? "保留已有记录与预算"
    }
    public static let guidance = "吃饭与超市日用分开；衣服鞋包归购物，理发护理、洗衣和订阅单独记，手机膜或手机壳等临时小额支出归零星。分类都可修改。"
    public static func merchantKey(_ merchant: String) -> String {
        merchant.precomposedStringWithCompatibilityMapping.lowercased()
            .components(separatedBy: .whitespacesAndNewlines).joined()
    }
    public static func suggest(_ merchant: String) -> String {
        let key = merchantKey(merchant)
        if key == "lv" || key.contains("louisvuitton") || key.contains("路易威登") { return "购物" }

        let personalRules = [("洗衣", "洗衣|烘干|laundry|laundromat|washlava|cscpay"), ("理发护理", "理发|剪发|barber|haircut|salon"), ("订阅", "chatgpt|openai|spotify|netflix|icloud|会员|订阅"), ("其他", "手机膜|手机壳|手机配件|screen protector|phone case")]
        if let match = personalRules.first(where: { merchant.range(of: $0.1, options: [.regularExpression, .caseInsensitive]) != nil }) { return match.0 }
        let rules = [("居家", "超市|生鲜|菜场|grocery|whole foods|trader joe|电费|水费|房租|物业|宽带"), ("餐饮", "餐厅|饭|面馆|咖啡|奶茶|瑞幸|星巴克|肯德基|麦当劳|外卖|starbucks|coffee|cafe|restaurant|mcdonald|chipotle"), ("交通", "滴滴|地铁|公交|停车|加油|出租|uber|lyft|subway|parking"), ("购物", "服装|鞋|包|围巾|商场|淘宝|京东|clothing"), ("医疗", "医院|药房|诊所|pharmacy"), ("教育", "课程|学费|书店"), ("旅行", "酒店|机票|航空|hotel"), ("娱乐", "电影|游戏|演出")]
        return rules.first { merchant.range(of: $0.1, options: [.regularExpression, .caseInsensitive]) != nil }?.0 ?? "其他"
    }
}

public struct Refund: Codable, Equatable, Identifiable, Sendable {
    public var id: String = UUID().uuidString
    public var amount: Int
    public var date: String
    public var note: String?
    public var voidedAt: String?
    public init(amount: Int, date: String, note: String? = nil) { self.amount = amount; self.date = date; self.note = note }
}

public struct CycleRule: Codable, Equatable, Sendable {
    public var month: String
    public var startDay: Int
    public var firstStart: String
}

public struct Entry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var amount: Int
    public var merchant: String
    public var date: String
    public var category: String
    public var currency: String = "USD"
    public var fingerprint: String
    public var orderHash: String
    public var createdAt: String
    public var note: String?
    public var updatedAt: String?
    public var voidedAt: String?
    public var refunds: [Refund]? = nil
    public var refunded: Int { (refunds ?? []).filter { $0.voidedAt == nil }.reduce(0) { $0 + $1.amount } }
    public var netAmount: Int { amount - refunded }
    public init(id: String = UUID().uuidString, amount: Int, merchant: String, date: String, category: String, fingerprint: String = "", orderHash: String = "") {
        self.id = id; self.amount = amount; self.merchant = merchant; self.date = date; self.category = category
        self.fingerprint = fingerprint; self.orderHash = orderHash; self.createdAt = ISO8601DateFormatter().string(from: Date())
    }
    public func validate() throws {
        guard !id.isEmpty, id.count <= 128, amount > 0, amount <= Money.maximum, currency == "USD", LedgerDate.valid(date), Categories.all.contains(category), !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, merchant.count <= 100, !createdAt.isEmpty, fingerprint.count <= 256, orderHash.count <= 256, (note?.count ?? 0) <= 500 else { throw LedgerError.invalid("交易字段无效：只接受有效日期、商家、分类和正数 USD 美分。") }
        let items = refunds ?? []
        guard items.count <= 1000, Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ !$0.id.isEmpty && $0.amount > 0 && $0.amount <= amount && LedgerDate.valid($0.date) && $0.date >= date && ($0.note?.count ?? 0) <= 500 }),
              refunded <= amount else { throw LedgerError.invalid("退款日期不能早于消费，累计退款不能超过原金额。") }
    }
}

public struct BudgetSettings: Codable, Equatable, Sendable {
    public var version = 2
    public var currency = "USD"
    public var cycleStartDay: Int? = nil
    public var cycleBudgetsOnly: Bool? = nil
    public var cycleRules: [CycleRule]? = nil
    public var startDay: Int { cycleStartDay ?? 22 }
    public var budgets: [String: Int?] = [:]
    public var overrides: [String: [String: Int?]] = [:]
    public init() {}
    public func limit(_ category: String, month: String) -> Int? {
        if let monthly = overrides[month], monthly.keys.contains(category) { return monthly[category] ?? nil }
        return cycleBudgetsOnly == true ? nil : (budgets[category] ?? nil)
    }
    public func validate() throws {
        let sets = [budgets] + Array(overrides.values)
        guard (2...3).contains(version), currency == "USD", (1...31).contains(startDay), overrides.keys.allSatisfy(LedgerDate.validMonth), sets.allSatisfy({ dict in dict.allSatisfy { Categories.all.contains($0.key) && ($0.value == nil || (0...Money.maximum).contains($0.value!)) } }) else { throw LedgerError.invalid("预算必须是 USD v2，有效月份和非负整数美分。") }
        let rules = cycleRules ?? []
        guard rules.count <= 1200, rules == rules.sorted(by: { $0.month < $1.month }), Set(rules.map(\.month)).count == rules.count else { throw LedgerError.invalid("周期设置无效。") }
        var previous = BudgetSettings(); previous.cycleStartDay = cycleStartDay
        for rule in rules {
            guard LedgerDate.validMonth(rule.month), (1...31).contains(rule.startDay), LedgerDate.valid(rule.firstStart),
                  rule.firstStart == previous.cycleStart(rule.month), rule.firstStart < LedgerDate.cycleStart(LedgerDate.shiftMonth(rule.month, by: 1), startDay: rule.startDay)
            else { throw LedgerError.invalid("周期设置无效。") }
            previous.cycleRules = (previous.cycleRules ?? []) + [rule]
        }
        guard rules.isEmpty || version >= 3 else { throw LedgerError.invalid("周期设置无效。") }
    }
}

public struct Ledger: Codable, Equatable, Sendable {
    public var format = "LocalLedger"
    public var version = 1
    public var currency = "USD"
    public var entries: [Entry] = []
    public var settings = BudgetSettings()
    public init() {}
    public func validate() throws {
        guard format == "LocalLedger", (1...2).contains(version), currency == "USD", entries.count <= 100_000, Set(entries.map(\.id)).count == entries.count else { throw LedgerError.invalid("账本格式、币种或记录数量无效。") }
        guard version >= 2 || (settings.version == 2 && entries.allSatisfy { ($0.refunds ?? []).isEmpty }) else { throw LedgerError.invalid("账本格式、币种或记录数量无效。") }
        try settings.validate(); try entries.forEach { try $0.validate() }
    }
    /// Most recently saved/edited non-void transaction for the exact normalized merchant.
    /// Derived from the ledger, so backup/restore preserves memory without a new schema.
    public func rememberedCategory(for merchant: String) -> String? {
        let key = Categories.merchantKey(MerchantDisplay.name(merchant))
        guard !key.isEmpty else { return nil }
        return entries.enumerated().filter { $0.element.voidedAt == nil && Categories.merchantKey(MerchantDisplay.name($0.element.merchant)) == key }
            .max { lhs, rhs in
                let l = lhs.element.updatedAt ?? lhs.element.createdAt
                let r = rhs.element.updatedAt ?? rhs.element.createdAt
                return l == r ? lhs.offset < rhs.offset : l < r
            }?.element.category
    }
    public func visibleCategories(selected: String? = nil) -> [String] {
        Categories.everyday + Categories.legacy.filter { category in
            category == selected || entries.contains { $0.category == category } ||
            (settings.budgets[category] ?? nil) != nil || settings.overrides.values.contains { ($0[category] ?? nil) != nil }
        }
    }
    public func suggestedCategory(for merchant: String) -> String {
        rememberedCategory(for: merchant) ?? Categories.suggest(merchant)
    }
    public func spent(category: String? = nil, month: String) -> Int {
        entries.filter { $0.voidedAt == nil && $0.date.hasPrefix(month + "-") && (category == nil || $0.category == category) }.reduce(0) { $0 + $1.netAmount }
    }
    public func status(category: String, month: String) -> String {
        guard let limit = settings.limit(category, month: month) else { return "未设预算" }
        let used = spent(category: category, month: month)
        if used > limit { return "已超预算" }
        if used == limit { return "已用完" }
        return used * 5 >= limit * 4 ? "接近预算" : "预算内"
    }
    public func duplicate(of entry: Entry) -> Bool {
        entries.contains { $0.id != entry.id && $0.voidedAt == nil && ((!entry.fingerprint.isEmpty && $0.fingerprint == entry.fingerprint) || (!entry.orderHash.isEmpty && $0.orderHash == entry.orderHash)) }
    }
    public func possibleDuplicate(of entry: Entry) -> Bool {
        entries.contains { $0.id != entry.id && $0.voidedAt == nil && $0.amount == entry.amount && $0.date == entry.date && Categories.merchantKey(MerchantDisplay.name($0.merchant)) == Categories.merchantKey(MerchantDisplay.name(entry.merchant)) }
    }
    public mutating func upsert(_ entry: Entry) throws {
        try entry.validate()
        guard !duplicate(of: entry) else { throw LedgerError.duplicate }
        var next = self
        if !(entry.refunds ?? []).isEmpty { next.version = 2 }
        if let i = next.entries.firstIndex(where: { $0.id == entry.id }) { next.entries[i] = entry } else { next.entries.append(entry) }
        try next.validate(); self = next
    }
    public func merging(_ imported: Ledger) throws -> Ledger {
        try validate(); try imported.validate(); var result = self
        var byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for entry in imported.entries {
            if let existing = byID[entry.id] {
                guard existing == entry else { throw LedgerError.conflict }
            } else {
                // Distinct IDs with matching receipt identities require review, never silently duplicate.
                guard !result.duplicate(of: entry) else { throw LedgerError.duplicate }
                result.entries.append(entry); byID[entry.id] = entry
            }
        }
        result.settings = imported.settings
        result.version = max(version, imported.version)
        try result.validate(); return result
    }
}


extension LedgerDate {
    public static func cycleStart(_ key: String, startDay: Int = 22) -> String {
        guard validMonth(key), (1...31).contains(startDay), let year = Int(key.prefix(4)), let month = Int(key.suffix(2)) else { return "" }
        return key + String(format: "-%02d", min(startDay, daysInMonth(year: year, month: month)))
    }
    public static func cycleKey(for day: String, startDay: Int = 22) -> String {
        guard valid(day), (1...31).contains(startDay) else { return "" }
        let key = String(day.prefix(7))
        if day >= cycleStart(key, startDay: startDay) { return key }
        let first = formatter().date(from: key + "-01")!
        return month(Calendar(identifier: .gregorian).date(byAdding: .month, value: -1, to: first)!)
    }
    public static func cycleSelection(_ date: Date, startDay: Int = 22) -> Date {
        formatter().date(from: cycleStart(cycleKey(for: string(date), startDay: startDay), startDay: startDay)) ?? date
    }
    public static func cycleEndExclusive(_ key: String, startDay: Int = 22) -> String {
        guard validMonth(key), (1...31).contains(startDay), let first = formatter().date(from: key + "-01") else { return "" }
        let next = Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: first)!
        return cycleStart(month(next), startDay: startDay)
    }
    public static func inCycle(_ day: String, key: String, startDay: Int = 22) -> Bool {
        valid(day) && validMonth(key) && (1...31).contains(startDay) && day >= cycleStart(key, startDay: startDay) && day < cycleEndExclusive(key, startDay: startDay)
    }
    public static func cycleLabel(_ key: String, startDay: Int = 22) -> String {
        guard let end = formatter().date(from: cycleEndExclusive(key, startDay: startDay)) else { return key }
        let last = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: end)!
        return cycleStart(key, startDay: startDay) + " 至 " + string(last)
    }
}
extension Ledger {
    // Pin legacy recurring limits to the current cycle once, preserving explicit overrides.
    public func usingIndependentBudgets(on day: String) throws -> Ledger {
        try validate()
        guard LedgerDate.valid(day) else { throw LedgerError.invalid("迁移日期无效。") }
        guard settings.cycleBudgetsOnly != true else { return self }
        var next = self
        let key = settings.cycleKey(for: day)
        var current = settings.overrides[key] ?? [:]
        for (category, value) in settings.budgets where !current.keys.contains(category) { current[category] = .some(value) }
        if !current.isEmpty { next.settings.overrides[key] = current }
        next.settings.budgets = [:]
        next.settings.cycleBudgetsOnly = true
        try next.validate()
        return next
    }
}
extension Ledger {
    public func cycleSpent(category: String? = nil, cycle: String) -> Int {
        entries.filter { $0.voidedAt == nil && settings.inCycle($0.date, key: cycle) && (category == nil || $0.category == category) }.reduce(0) { $0 + $1.netAmount }
    }
    public func cycleStatus(category: String, cycle: String) -> String {
        guard let limit = settings.limit(category, month: cycle) else { return "未设预算" }
        let used = cycleSpent(category: category, cycle: cycle)
        if used > limit { return "已超预算" }
        if used == limit { return "已用完" }
        return used * 5 >= limit * 4 ? "接近预算" : "预算内"
    }
}


public enum MerchantDisplay {
    public static func name(_ original: String) -> String {
        let key = Categories.merchantKey(original)
        switch key {
        case "路易威登", "路易·威登", "louisvuitton", "lv": return "Louis Vuitton"
        case "hashimarket": return "Hashi Market"
        default: return original
        }
    }
}


extension LedgerDate {
    public static func shiftMonth(_ key: String, by offset: Int) -> String {
        guard validMonth(key), let year = Int(key.prefix(4)), let month = Int(key.suffix(2)), (-1200...1200).contains(offset) else { return "" }
        let index = year * 12 + month - 1 + offset
        return String(format: "%04d-%02d", index / 12, index % 12 + 1)
    }
}
extension BudgetSettings {
    public var plannedStartDay: Int { cycleRules?.last?.startDay ?? startDay }
    public func cycleStart(_ key: String) -> String {
        guard let rule = (cycleRules ?? []).last(where: { $0.month <= key }) else { return LedgerDate.cycleStart(key, startDay: startDay) }
        return key == rule.month ? rule.firstStart : LedgerDate.cycleStart(key, startDay: rule.startDay)
    }
    public func cycleEnd(_ key: String) -> String { cycleStart(LedgerDate.shiftMonth(key, by: 1)) }
    public func inCycle(_ day: String, key: String) -> Bool { LedgerDate.valid(day) && LedgerDate.validMonth(key) && day >= cycleStart(key) && day < cycleEnd(key) }
    public func cycleKey(for day: String) -> String {
        guard LedgerDate.valid(day) else { return "" }
        let key = String(day.prefix(7))
        return inCycle(day, key: key) ? key : LedgerDate.shiftMonth(key, by: -1)
    }
    public func selection(_ date: Date) -> Date { LedgerDate.formatter().date(from: cycleKey(for: LedgerDate.string(date)) + "-01") ?? date }
    public func cycleLabel(_ key: String) -> String {
        guard let end = LedgerDate.formatter().date(from: cycleEnd(key)), let last = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: end) else { return key }
        return cycleStart(key) + " 至 " + LedgerDate.string(last)
    }
    public mutating func schedule(startDay day: Int, on today: String) throws {
        guard LedgerDate.valid(today), (1...31).contains(day) else { throw LedgerError.invalid("周期设置无效。") }
        let key = LedgerDate.shiftMonth(cycleKey(for: today), by: 1)
        var next = self
        next.cycleRules = (cycleRules ?? []).filter { $0.month < key }
        let first = next.cycleStart(key)
        next.cycleRules = (next.cycleRules ?? []) + [CycleRule(month: key, startDay: day, firstStart: first)]
        next.version = 3
        try next.validate(); self = next
    }
}
extension Ledger {
    public mutating func addRefund(_ refund: Refund, to id: String) throws {
        guard var entry = entries.first(where: { $0.id == id }), entry.voidedAt == nil else { throw LedgerError.invalid("原消费不存在或已作废。") }
        entry.refunds = (entry.refunds ?? []) + [refund]
        try upsert(entry)
    }
}

extension Ledger {
    /// A nil cycle searches the complete ledger. Voided rows never contribute to totals.
    public func matchingEntries(cycle: String?, query: String, includeVoided: Bool = false,
                                displayText: (Entry) -> String = { _ in "" }) -> [Entry] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return entries.filter { entry in
            guard (cycle == nil || settings.inCycle(entry.date, key: cycle!)),
                  includeVoided || entry.voidedAt == nil else { return false }
            let text = [entry.merchant, MerchantDisplay.name(entry.merchant), entry.note ?? "",
                        Categories.title(entry.category), entry.date, Money.decimal(entry.amount),
                        Money.decimal(entry.netAmount), displayText(entry)].joined(separator: " ")
            return words.allSatisfy { text.localizedCaseInsensitiveContains($0) }
        }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id < $1.id
        }
    }
    public static func netTotal(of entries: [Entry]) -> Int {
        entries.filter { $0.voidedAt == nil }.reduce(0) { $0 + $1.netAmount }
    }
}

extension BudgetSettings {
    public func cycleDayCount(_ key: String) -> Int? {
        let f = LedgerDate.formatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        guard let start = f.date(from: cycleStart(key)), let end = f.date(from: cycleEnd(key)), end > start else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.dateComponents([.day], from: start, to: end).day
    }
}
