import Foundation

public enum Backup {
    public static let maximumBytes = 25 * 1024 * 1024
    public static func encode(_ ledger: Ledger) throws -> Data {
        try ledger.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ledger)
    }
    public static func decode(_ data: Data) throws -> Ledger {
        guard data.count <= maximumBytes else { throw LedgerError.invalid("备份超过 25 MB，请分开整理。") }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        if header.format == "LocalLedger" {
            let ledger = try decoder.decode(Ledger.self, from: data); try ledger.validate(); return ledger
        }
        guard header.format == nil, header.version == 2, header.currency == "USD" else { throw LedgerError.invalid("只接受本 App 备份或 Scriptable USD v2 备份；人民币备份不能导入。") }
        let old = try decoder.decode(Legacy.self, from: data)
        try old.settings.validate()
        var ledger = Ledger(); ledger.settings = old.settings
        var voids: [String: String] = [:]
        for (name, row) in old.files {
            guard name.range(of: #"^(txn-|void-)[A-Fa-f0-9-]+\.json$"#, options: .regularExpression) != nil, name == "\(name.hasPrefix("txn-") ? "txn" : "void")-\(row.id).json" else { throw LedgerError.invalid("Scriptable 备份文件名与 ID 不一致。") }
            if name.hasPrefix("void-") {
                guard let date = row.voidedAt, !date.isEmpty else { throw LedgerError.invalid("作废记录缺少时间。") }
                voids[row.id] = date
            } else {
                guard let amount = row.amount, let merchant = row.merchant, let date = row.date, let category = row.category, let createdAt = row.createdAt, row.currency == "USD" else { throw LedgerError.invalid("备份交易缺字段或混入其他币种。") }
                var entry = Entry(id: row.id, amount: amount, merchant: merchant, date: date, category: category, fingerprint: row.fingerprint ?? "", orderHash: row.orderHash ?? "")
                entry.createdAt = createdAt; ledger.entries.append(entry)
            }
        }
        guard Set(voids.keys).isSubset(of: Set(ledger.entries.map(\.id))) else { throw LedgerError.invalid("作废记录找不到原交易，备份可能不完整。") }
        for i in ledger.entries.indices { ledger.entries[i].voidedAt = voids[ledger.entries[i].id] }
        try ledger.validate(); return ledger
    }
    private struct Header: Decodable { let format: String?; let version: Int; let currency: String }
    private struct Legacy: Decodable { let settings: BudgetSettings; let files: [String: LegacyRow] }
    private struct LegacyRow: Decodable {
        let id: String; let amount: Int?; let merchant: String?; let date: String?; let category: String?; let currency: String?
        let fingerprint: String?; let orderHash: String?; let createdAt: String?; let voidedAt: String?
    }
}

/// A complete validated snapshot is atomically replaced. A write failure never updates the UI state.
public struct LedgerDisk {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Ledger {
        let data: Data
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Backup.maximumBytes else { throw LedgerError.invalid("备份超过 25 MB，请分开整理。") }
            data = try Data(contentsOf: url)
        } catch {
            let failure = error as NSError
            let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError
            // fileExists is also false for protected/inaccessible files. Only ENOENT
            // (a genuinely absent path) is a new ledger, never EACCES or ENOTDIR.
            if (failure.domain == NSPOSIXErrorDomain && failure.code == Int(ENOENT)) ||
                (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoSuchFileError &&
                 (underlying == nil || (underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(ENOENT)))) { return Ledger() }
            throw error
        }
        let ledger = try Backup.decode(data)
        #if os(iOS)
        var folder = url.deletingLastPathComponent()
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
        return ledger
    }
    public func save(_ ledger: Ledger) throws {
        let data = try Backup.encode(ledger)
        guard data.count <= Backup.maximumBytes else { throw LedgerError.invalid("账本达到本版 25 MB 上限，未保存。") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var folder = url.deletingLastPathComponent()
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }
}

public enum BackupReminder {
    public static func isDue(lastExport: TimeInterval, now: Date, hasEntries: Bool) -> Bool {
        guard hasEntries else { return false }
        guard lastExport.isFinite, lastExport > 0, lastExport <= now.timeIntervalSince1970 else { return true }
        return now.timeIntervalSince1970 - lastExport >= 7 * 24 * 60 * 60
    }
}
