import SwiftUI
import UniformTypeIdentifiers

@MainActor final class LedgerStore: ObservableObject {
    @Published private(set) var ledger = Ledger()
    @Published var error: String?
    @Published private(set) var ready = false
    let disk: LedgerDisk
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalLedger", isDirectory: true)
        disk = LedgerDisk(url: directory.appendingPathComponent("ledger.json"))
        do { ledger = try disk.load(); ready = true } catch { self.error = "无法读取账本，已停止写入保护数据：\(error.localizedDescription)" }
    }
    func commit(_ next: Ledger) throws {
        guard ready else { throw LedgerError.unavailable }
        try disk.save(next); ledger = next
    }
    func save(_ entry: Entry) throws {
        var next = ledger; try next.upsert(entry); try commit(next)
    }
    func void(_ entry: Entry) {
        do {
            var next = ledger
            guard let index = next.entries.firstIndex(where: { $0.id == entry.id }) else { return }
            next.entries[index].voidedAt = ISO8601DateFormatter().string(from: Date())
            try commit(next)
        } catch { self.error = error.localizedDescription }
    }
    func restore(_ imported: Ledger) throws {
        guard ready else { throw LedgerError.unavailable }
        let merged = try ledger.merging(imported)
        // Durable rollback copy includes both old records and old budgets, before changing anything.
        let previous = disk.url.deletingLastPathComponent().appendingPathComponent("before-restore.json")
        try LedgerDisk(url: previous).save(ledger)
        try commit(merged)
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
