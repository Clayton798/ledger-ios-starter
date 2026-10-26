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
    public static func decimal(_ cents: Int) -> String {
        let n = abs(cents)
        return "\(cents < 0 ? "-" : "")\(n / 100).\(String(format: "%02d", n % 100))"
    }
    public static func display(_ cents: Int) -> String { "US$" + decimal(cents) }
}

public enum LedgerDate {
    public static func valid(_ string: String) -> Bool {
        guard string.range(of: #"^20[0-9]{2}-[0-9]{2}-[0-9]{2}$|^2100-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return false }
        let f = formatter(); f.isLenient = false
        return f.date(from: string).map { f.string(from: $0) == string } ?? false
    }
    public static func formatter() -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"
        return f
    }
    public static func string(_ date: Date) -> String { formatter().string(from: date) }
    public static func month(_ date: Date) -> String { String(string(date).prefix(7)) }
    public static func validMonth(_ value: String) -> Bool { valid(value + "-01") }
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
    public init(id: String = UUID().uuidString, amount: Int, merchant: String, date: String, category: String, fingerprint: String = "", orderHash: String = "") {
        self.id = id; self.amount = amount; self.merchant = merchant; self.date = date; self.category = category
        self.fingerprint = fingerprint; self.orderHash = orderHash; self.createdAt = ISO8601DateFormatter().string(from: Date())
    }
    public func validate() throws {
        guard !id.isEmpty, id.count <= 128, amount > 0, amount <= Money.maximum, currency == "USD", LedgerDate.valid(date), Categories.all.contains(category), !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, merchant.count <= 100, !createdAt.isEmpty, fingerprint.count <= 256, orderHash.count <= 256, (note?.count ?? 0) <= 500 else { throw LedgerError.invalid("交易字段无效：只接受有效日期、商家、分类和正数 USD 美分。") }
    }
}

public struct BudgetSettings: Codable, Equatable, Sendable {
    public var version = 2
    public var currency = "USD"
    public var budgets: [String: Int?] = [:]
    public var overrides: [String: [String: Int?]] = [:]
    public init() {}
    public func limit(_ category: String, month: String) -> Int? {
        if let monthly = overrides[month], monthly.keys.contains(category) { return monthly[category] ?? nil }
        return budgets[category] ?? nil
    }
    public func validate() throws {
        let sets = [budgets] + Array(overrides.values)
        guard version == 2, currency == "USD", overrides.keys.allSatisfy(LedgerDate.validMonth), sets.allSatisfy({ dict in dict.allSatisfy { Categories.all.contains($0.key) && ($0.value == nil || (0...Money.maximum).contains($0.value!)) } }) else { throw LedgerError.invalid("预算必须是 USD v2，有效月份和非负整数美分。") }
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
        guard format == "LocalLedger", version == 1, currency == "USD", entries.count <= 100_000, Set(entries.map(\.id)).count == entries.count else { throw LedgerError.invalid("账本格式、币种或记录数量无效。") }
        try settings.validate(); try entries.forEach { try $0.validate() }
    }
    /// Most recently saved/edited non-void transaction for the exact normalized merchant.
    /// Derived from the ledger, so backup/restore preserves memory without a new schema.
    public func rememberedCategory(for merchant: String) -> String? {
        let key = Categories.merchantKey(merchant)
        guard !key.isEmpty else { return nil }
        return entries.enumerated().filter { $0.element.voidedAt == nil && Categories.merchantKey($0.element.merchant) == key }
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
        entries.filter { $0.voidedAt == nil && $0.date.hasPrefix(month + "-") && (category == nil || $0.category == category) }.reduce(0) { $0 + $1.amount }
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
        entries.contains { $0.id != entry.id && $0.voidedAt == nil && $0.amount == entry.amount && $0.date == entry.date && Categories.merchantKey($0.merchant) == Categories.merchantKey(entry.merchant) }
    }
    public mutating func upsert(_ entry: Entry) throws {
        try entry.validate()
        guard !duplicate(of: entry) else { throw LedgerError.duplicate }
        if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = entry } else { entries.append(entry) }
        try validate()
    }
    public func merging(_ imported: Ledger) throws -> Ledger {
        try imported.validate(); var result = self
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
        try result.validate(); return result
    }
}


extension LedgerDate {
    public static func cycleKey(for day: String) -> String {
        guard valid(day), let date = formatter().date(from: day) else { return "" }
        if Int(day.suffix(2))! >= 22 { return String(day.prefix(7)) }
        let previous = Calendar(identifier: .gregorian).date(byAdding: .month, value: -1, to: date)!
        return month(previous)
    }
    public static func cycleSelection(_ date: Date) -> Date { formatter().date(from: cycleKey(for: string(date)) + "-22") ?? date }
    public static func cycleEndExclusive(_ key: String) -> String {
        guard let start = formatter().date(from: key + "-22"), validMonth(key) else { return "" }
        return string(Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: start)!)
    }
    public static func inCycle(_ day: String, key: String) -> Bool {
        valid(day) && validMonth(key) && day >= key + "-22" && day < cycleEndExclusive(key)
    }
    public static func cycleLabel(_ key: String) -> String {
        let end = cycleEndExclusive(key)
        guard !end.isEmpty else { return key }
        return key + "-22 至 " + String(end.prefix(7)) + "-21"
    }
}
extension Ledger {
    public func cycleSpent(category: String? = nil, cycle: String) -> Int {
        entries.filter { $0.voidedAt == nil && LedgerDate.inCycle($0.date, key: cycle) && (category == nil || $0.category == category) }.reduce(0) { $0 + $1.amount }
    }
    public func cycleStatus(category: String, cycle: String) -> String {
        guard let limit = settings.limit(category, month: cycle) else { return "未设预算" }
        let used = cycleSpent(category: category, cycle: cycle)
        if used > limit { return "已超预算" }
        if used == limit { return "已用完" }
        return used * 5 >= limit * 4 ? "接近预算" : "预算内"
    }
}
