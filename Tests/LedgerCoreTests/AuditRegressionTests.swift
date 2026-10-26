import XCTest
@testable import LedgerCore

final class AuditRegressionTests: XCTestCase {
    func testBackupReminderBoundaries() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertFalse(BackupReminder.isDue(lastExport: 0, now: now, hasEntries: false))
        XCTAssertTrue(BackupReminder.isDue(lastExport: 0, now: now, hasEntries: true))
        XCTAssertFalse(BackupReminder.isDue(lastExport: now.timeIntervalSince1970 - 604799, now: now, hasEntries: true))
        XCTAssertTrue(BackupReminder.isDue(lastExport: now.timeIntervalSince1970 - 604800, now: now, hasEntries: true))
        XCTAssertTrue(BackupReminder.isDue(lastExport: now.timeIntervalSince1970 + 10, now: now, hasEntries: true))
    }
    func testTransitionDayCounts() throws {
        var settings = BudgetSettings()
        try settings.schedule(startDay: 1, on: "2026-10-26")
        XCTAssertEqual(settings.cycleDayCount("2026-10"), 31)
        XCTAssertEqual(settings.cycleDayCount("2026-11"), 9)
        XCTAssertEqual(settings.cycleDayCount("2026-12"), 31)
        var natural = BudgetSettings(); natural.cycleStartDay = 1
        XCTAssertEqual(natural.cycleDayCount("2024-02"), 29)
        try natural.schedule(startDay: 22, on: "2026-10-26")
        XCTAssertEqual(natural.cycleDayCount("2026-11"), 51)
    }
    func testSearchAcrossPeriodsAndRefundNetTotal() {
        var ledger = Ledger()
        var old = Entry(amount: 2000, merchant: "Example Market", date: "2026-09-24", category: "居家")
        old.refunds = [Refund(amount: 500, date: "2026-10-01")]
        let current = Entry(amount: 1000, merchant: "Example Market", date: "2026-10-25", category: "居家")
        var voided = Entry(amount: 900, merchant: "Example Market", date: "2026-10-26", category: "居家")
        voided.voidedAt = "2026-10-26"
        ledger.entries = [old, current, voided]
        XCTAssertEqual(ledger.matchingEntries(cycle: "2026-10", query: "market").map(\.id), [current.id])
        let all = ledger.matchingEntries(cycle: nil, query: "  EXAMPLE market  ", includeVoided: true)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(Ledger.netTotal(of: all), 2500)
        XCTAssertEqual(ledger.matchingEntries(cycle: nil, query: "2026-09 20.00").map(\.id), [old.id])
        XCTAssertEqual(ledger.matchingEntries(cycle: nil, query: "épicerie", displayText: { _ in "Épicerie" }).count, 2)
        XCTAssertTrue(ledger.matchingEntries(cycle: nil, query: "missing").isEmpty)
    }
    func testCalendarBoundariesAndLeapYears() {
        XCTAssertTrue(LedgerDate.valid("2000-02-29"))
        XCTAssertFalse(LedgerDate.valid("2100-02-29"))
        XCTAssertFalse(LedgerDate.valid("2026-04-31"))
        XCTAssertFalse(LedgerDate.valid("2026-1-01"))
        XCTAssertEqual(LedgerDate.cycleKey(for: "2000-01-01"), "1999-12")
        XCTAssertTrue(LedgerDate.inCycle("2000-01-01", key: "1999-12"))
        XCTAssertTrue(LedgerDate.inCycle("2100-12-31", key: "2100-12"))
        XCTAssertEqual(LedgerDate.cycleEndExclusive("2100-12"), "2101-01-22")
        XCTAssertEqual(LedgerDate.cycleStart("2024-02", startDay: 31), "2024-02-29")
    }
    func testInvalidCurrentLedgerCannotBeMerged() {
        var ledger = Ledger()
        let entry = Entry(amount: 100, merchant: "Test", date: "2026-10-25", category: Categories.all[0], fingerprint: "", orderHash: "")
        ledger.entries = [entry, entry]
        XCTAssertThrowsError(try ledger.merging(Ledger()))
    }
    func testIncomingPaymentsAreNotPurchases() {
        for source in ["Payment received USD 100.00", "Payment thank you USD 100.00", "Direct deposit USD 100.00", "Refund USD 12.00", "退款 USD 12.00", "还款成功 USD 100.00", "转入 USD 100.00"] {
            XCTAssertNotNil(ReceiptParser.parse(source).blockedReason, source)
        }
        XCTAssertNil(ReceiptParser.parse("Merchant: Credit Coffee\nCredit card purchase\nTotal paid USD 12.00").blockedReason)
    }
    func testTransactionDateDoesNotLeakOldHeadingIntoFollowingRows() {
        let lines = ["2026-10-24", "Cafe USD 5.00", "2026-10-25 Store USD 7.00", "Other USD 8.00"]
        let result = StatementParser.parse(lines.enumerated().map { OCRLine(text: $0.element, x: 0.1, y: 0.95 - Double($0.offset) * 0.08, height: 0.04) })
        XCTAssertEqual(result.rows.map(\.date), ["2026-10-24", "2026-10-25", ""])
    }
    func testInaccessibleLedgerIsNeverTreatedAsNew() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let disk = LedgerDisk(url: folder.appendingPathComponent("ledger.json"))
        try disk.save(Ledger())
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        XCTAssertThrowsError(try disk.load())
    }
    func testFileInsteadOfParentDirectoryIsNotANewLedger() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not a folder".utf8).write(to: file)
        XCTAssertThrowsError(try LedgerDisk(url: file.appendingPathComponent("ledger.json")).load())
    }
}
