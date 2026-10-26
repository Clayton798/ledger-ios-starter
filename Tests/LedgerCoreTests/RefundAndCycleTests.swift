import XCTest
@testable import LedgerCore

final class RefundAndCycleTests: XCTestCase {
    func testRefundsReduceOriginalPeriodAndSurviveBackup() throws {
        var ledger = Ledger()
        let entry = Entry(amount: 10000, merchant: "Fictional Store", date: "2026-10-25", category: "购物")
        try ledger.upsert(entry)
        try ledger.addRefund(Refund(amount: 3000, date: "2026-11-25"), to: entry.id)
        XCTAssertEqual(ledger.cycleSpent(cycle: "2026-10"), 7000)
        XCTAssertEqual(ledger.cycleSpent(cycle: "2026-11"), 0)
        XCTAssertEqual(ledger.entries[0].amount, 10000)
        XCTAssertEqual(try Backup.decode(Backup.encode(ledger)), ledger)
        try ledger.addRefund(Refund(amount: 7000, date: "2026-12-01"), to: entry.id)
        XCTAssertEqual(ledger.cycleSpent(cycle: "2026-10"), 0)
        let before = ledger
        XCTAssertThrowsError(try ledger.addRefund(Refund(amount: 1, date: "2026-12-02"), to: entry.id))
        XCTAssertEqual(before, ledger)
    }
    func testRefundValidationAndCorrectionAreAtomic() throws {
        var ledger = Ledger()
        let entry = Entry(amount: 5000, merchant: "Fictional Store", date: "2026-10-25", category: "购物")
        try ledger.upsert(entry)
        XCTAssertThrowsError(try ledger.addRefund(Refund(amount: 100, date: "2026-10-24"), to: entry.id))
        XCTAssertThrowsError(try ledger.addRefund(Refund(amount: -100, date: "2026-10-26"), to: entry.id))
        try ledger.addRefund(Refund(amount: 1000, date: "2026-10-26"), to: entry.id)
        var edited = ledger.entries[0]; edited.amount = 500
        let before = ledger
        XCTAssertThrowsError(try ledger.upsert(edited)); XCTAssertEqual(ledger, before)
        edited = ledger.entries[0]; edited.refunds?[0].voidedAt = "2026-10-26T12:00:00Z"
        try ledger.upsert(edited); XCTAssertEqual(ledger.cycleSpent(cycle: "2026-10"), 5000)
        edited.voidedAt = "2026-10-26T12:00:00Z"; try ledger.upsert(edited)
        XCTAssertThrowsError(try ledger.addRefund(Refund(amount: 1000, date: "2026-10-26"), to: entry.id))
        XCTAssertEqual(ledger.cycleSpent(cycle: "2026-10"), 0)
    }
    func testNewFeaturesRequireNewBackupVersion() throws {
        var ledger = Ledger()
        try ledger.settings.schedule(startDay: 1, on: "2026-10-26")
        XCTAssertThrowsError(try ledger.validate())
        ledger.version = 2; try ledger.validate()
        XCTAssertEqual(try Backup.decode(Backup.encode(ledger)), ledger)
    }
    func testShortTransitionPreservesCurrentAndHistory() throws {
        var settings = BudgetSettings()
        let old = settings
        try settings.schedule(startDay: 1, on: "2026-10-26")
        XCTAssertEqual(settings.cycleLabel("2026-09"), old.cycleLabel("2026-09"))
        XCTAssertEqual(settings.cycleLabel("2026-10"), old.cycleLabel("2026-10"))
        XCTAssertEqual(settings.cycleStart("2026-11"), "2026-11-22")
        XCTAssertEqual(settings.cycleEnd("2026-11"), "2026-12-01")
        XCTAssertEqual(settings.cycleStart("2026-12"), "2026-12-01")
        XCTAssertEqual(settings.cycleKey(for: "2026-11-21"), "2026-10")
        XCTAssertEqual(settings.cycleKey(for: "2026-11-22"), "2026-11")
        XCTAssertEqual(settings.cycleKey(for: "2026-12-01"), "2026-12")
    }
    func testLongTransitionAndPendingReplacement() throws {
        var settings = BudgetSettings(); settings.cycleStartDay = 1
        try settings.schedule(startDay: 22, on: "2026-10-26")
        XCTAssertEqual(settings.cycleStart("2026-11"), "2026-11-01")
        XCTAssertEqual(settings.cycleEnd("2026-11"), "2026-12-22")
        XCTAssertEqual(settings.cycleKey(for: "2026-12-21"), "2026-11")
        try settings.schedule(startDay: 15, on: "2026-10-27")
        XCTAssertEqual(settings.cycleRules?.count, 1)
        XCTAssertEqual(settings.cycleEnd("2026-11"), "2026-12-15")
        let history = settings.cycleLabel("2026-11")
        try settings.schedule(startDay: 1, on: "2026-12-20")
        XCTAssertEqual(settings.cycleLabel("2026-11"), history)
        try settings.validate()
    }
    func testEveryDayBelongsToExactlyOneCycleAcrossLeapAndYearBoundary() throws {
        for original in [1, 22, 28, 29, 30, 31] {
            for target in [1, 22, 28, 29, 30, 31] {
                var settings = BudgetSettings(); settings.cycleStartDay = original
                try settings.schedule(startDay: target, on: "2027-12-26")
                let keys = ["2027-11", "2027-12", "2028-01", "2028-02", "2028-03", "2028-04"]
                var date = LedgerDate.formatter().date(from: "2027-12-01")!
                for _ in 0..<120 {
                    let day = LedgerDate.string(date)
                    let matches = keys.filter { settings.inCycle(day, key: $0) }
                    XCTAssertEqual(matches.count, 1, "\(original) → \(target), \(day)")
                    XCTAssertEqual(matches.first, settings.cycleKey(for: day))
                    date = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: date)!
                }
            }
        }
    }
}
