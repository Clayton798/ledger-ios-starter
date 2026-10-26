import XCTest
@testable import LedgerCore

final class LedgerCoreTests: XCTestCase {
    let sample = "支付成功\n商户名称：示例咖啡\n实付：USD 28.50\n交易时间：2026-10-25 15:32:01\n交易单号：202610251234567890"
    func entry(_ amount: Int = 2850) -> Entry { Entry(id: "ABCD-1234", amount: amount, merchant: "示例咖啡", date: "2026-10-25", category: "餐饮") }
    func legacy(currency: String = "USD") -> Data {
        Data("""
        {"version":2,"currency":"\(currency)","settings":{"version":2,"currency":"USD","budgets":{"餐饮":10000},"overrides":{"2026-10":{"餐饮":null}}},"files":{"txn-ABCD-1234.json":{"id":"ABCD-1234","currency":"USD","amount":2850,"merchant":"虚构测试商家","date":"2026-10-25","category":"餐饮","createdAt":"2026-10-25T12:00:00Z"},"void-ABCD-1234.json":{"id":"ABCD-1234","voidedAt":"2026-10-25T13:00:00Z"}}}
        """.utf8)
    }
    func testExactCentsAndFormatting() {
        XCTAssertEqual(Money.cents("0.10")! + Money.cents("0.20")!, 30)
        XCTAssertEqual(Money.cents("1,234.56"), 123456)
        XCTAssertEqual(Money.cents("0"), 0)
        XCTAssertEqual(Money.cents("999999999.99"), Money.maximum)
        XCTAssertEqual(Money.decimal(105), "1.05")
        XCTAssertEqual(Money.display(-105), "US$-1.05")
    }
    func testInvalidMoney() {
        for s in ["-1", "1.005", "NaN", "1,2.50", "1e3", "", "1000000000", "１２"] { XCTAssertNil(Money.cents(s), s) }
    }
    func testDates() {
        XCTAssertTrue(LedgerDate.valid("2024-02-29")); XCTAssertFalse(LedgerDate.valid("2026-02-29"))
        XCTAssertFalse(LedgerDate.valid("2026-13-01")); XCTAssertFalse(LedgerDate.valid("1999-12-31"))
        XCTAssertFalse(LedgerDate.valid("2026-2-03"))
    }
    func testBasicReceipt() {
        let r = ReceiptParser.parse(sample)
        XCTAssertEqual(r.amounts, [2850]); XCTAssertEqual(r.dates, ["2026-10-25"])
        XCTAssertEqual(r.merchant, "示例咖啡"); XCTAssertTrue(r.explicitUSD); XCTAssertNil(r.blockedReason)
        XCTAssertFalse(r.orderHash.isEmpty)
    }
    func testMoneyFormats() {
        for s in ["USD 28.50", "US$28.50", "美元28.50", "$28.50", "28.50 USD", "28.50美元", "实付：28.50", "Total paid: 28.50", "ＵＳＤ ２８．５０"] {
            XCTAssertEqual(ReceiptParser.parse(s).amounts, [2850], s)
        }
    }
    func testPrecisionNotTruncated() { XCTAssertEqual(ReceiptParser.parse("USD 1.005").amounts, []) }
    func testMultipleAmountsStaySeparate() { XCTAssertEqual(ReceiptParser.parse(sample + "\n原价 US$32.00").amounts, [2850, 3200]) }
    func testBareDollarNeedsConfirmation() { XCTAssertFalse(ReceiptParser.parse("$12.00").explicitUSD) }
    func testOtherCurrenciesBlocked() {
        for s in ["CAD", "AUD", "CNY", "RMB", "HKD", "SGD", "EUR", "JPY", "GBP", "HK$", "CA$", "A$", "S$", "人民币", "欧元", "¥", "€"] { XCTAssertNotNil(ReceiptParser.parse(sample + "\n" + s + " 9.00").blockedReason, s) }
    }
    func testRefundButtonsAllowed() {
        for s in ["退款", "申请退款", "退款政策", "Refund", "Request refund", "Refund policy"] { XCTAssertNil(ReceiptParser.parse(sample + "\n" + s).blockedReason, s) }
    }
    func testRealRefundsBlocked() {
        for s in ["退款成功", "已退款", "退款中", "交易状态：已撤销", "冲正成功", "Refund completed", "Payment reversed", "Status: refunded", "退款金额：USD 0.50", "部分退款", "Partial refund", "Refund amount: $0.50"] { XCTAssertNotNil(ReceiptParser.parse(sample + "\n" + s).blockedReason, s) }
    }
    func testNegativeAndPendingBlocked() {
        for s in ["-$28.50", "-28.50 USD", "(28.50 USD)", "USD -28.50", "实付：-28.50", "(USD 28.50)", "支付失败", "Payment pending"] { XCTAssertNotNil(ReceiptParser.parse(s).blockedReason, s) }
    }
    func testHyphensInOrderAreNotNegative() { XCTAssertNil(ReceiptParser.parse(sample + "\nOrder ID: AB-123456789").blockedReason) }
    func testEnglishAndChineseDates() {
        for s in ["Oct 25, 2026", "25 October 2026", "2026年10月25日", "2026/10/25"] { XCTAssertEqual(ReceiptParser.parse(s).dates, ["2026-10-25"], s) }
        XCTAssertEqual(ReceiptParser.parse("10/11/2026").dates, []) // ambiguous date: manual confirmation
    }
    func testMultiDateAndMissingFields() {
        XCTAssertEqual(ReceiptParser.parse(sample + "\n2026-10-24").dates.count, 2)
        XCTAssertTrue(ReceiptParser.parse("无法识别").amounts.isEmpty)
    }
    func testCategoryHabits() {
        XCTAssertEqual(Categories.suggest("示例超市"), "居家")
        XCTAssertEqual(Categories.suggest("示例咖啡"), "餐饮")
        XCTAssertEqual(Categories.suggest("围巾服装店"), "购物")
        XCTAssertEqual(Categories.suggest("Uber"), "交通")
    }
    func testLuxuryMerchantAliases() {
        for name in ["路易威登", "Louis Vuitton", "LOUIS VUITTON Store", "LV", "ｌｖ"] {
            XCTAssertEqual(Categories.suggest(name), "购物", name)
        }
        XCTAssertEqual(Categories.suggest("Silver Cafe"), "餐饮")
    }
    func testRememberedCategoryOverridesDefault() throws {
        var ledger = Ledger(); var a = entry(); a.merchant = "Louis Vuitton"; a.category = "旅行"
        try ledger.upsert(a)
        XCTAssertEqual(ledger.suggestedCategory(for: "  LOUIS   VUITTON  "), "旅行")
        XCTAssertEqual(ledger.suggestedCategory(for: "Different Merchant"), "其他")
    }
    func testLatestEditAndVoidDriveMemory() throws {
        var ledger = Ledger(); var first = entry(); first.createdAt = "2026-10-01T00:00:00Z"; first.category = "居家"
        var second = entry(); second.id = "ABCD-5678"; second.createdAt = "2026-10-02T00:00:00Z"; second.category = "购物"
        ledger.entries = [first, second]
        XCTAssertEqual(ledger.rememberedCategory(for: first.merchant), "购物")
        ledger.entries[0].updatedAt = "2026-10-03T00:00:00Z"
        XCTAssertEqual(ledger.rememberedCategory(for: first.merchant), "居家")
        ledger.entries[0].voidedAt = "2026-10-04T00:00:00Z"
        XCTAssertEqual(ledger.rememberedCategory(for: first.merchant), "购物")
        ledger.entries[1].voidedAt = "2026-10-04T00:00:00Z"
        XCTAssertNil(ledger.rememberedCategory(for: first.merchant))
    }
    func testMerchantMemorySurvivesBackupAndDisk() throws {
        var ledger = Ledger(); var a = entry(); a.merchant = "Example Store"; a.category = "居家"; ledger.entries = [a]
        let decoded = try Backup.decode(Backup.encode(ledger))
        XCTAssertEqual(decoded.suggestedCategory(for: "example store"), "居家")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = LedgerDisk(url: folder.appendingPathComponent("ledger.json")); try disk.save(decoded)
        XCTAssertEqual(try disk.load().suggestedCategory(for: "Example Store"), "居家")
    }
    func testFingerprintWhitespaceStable() { XCTAssertEqual(ReceiptParser.fingerprint(sample), ReceiptParser.fingerprint(sample.replacingOccurrences(of: "\n", with: "  "))) }
    func testBudgetMonthAndVoid() throws {
        var ledger = Ledger(); var a = entry(8000); ledger.entries = [a]
        ledger.settings.budgets["餐饮"] = 10000
        XCTAssertEqual(ledger.status(category: "餐饮", month: "2026-10"), "接近预算")
        XCTAssertEqual(ledger.spent(month: "2026-09"), 0)
        ledger.settings.budgets["餐饮"] = 8000
        XCTAssertEqual(ledger.status(category: "餐饮", month: "2026-10"), "已用完")
        ledger.settings.budgets["餐饮"] = 7000
        XCTAssertEqual(ledger.status(category: "餐饮", month: "2026-10"), "已超预算")
        a.voidedAt = "2026-10-25T00:00:00Z"; ledger.entries = [a]
        XCTAssertEqual(ledger.spent(month: "2026-10"), 0)
    }
    func testZeroAndNullBudget() throws {
        var ledger = Ledger(); ledger.entries = [entry()]; ledger.settings.budgets["餐饮"] = 0
        XCTAssertEqual(ledger.status(category: "餐饮", month: "2026-10"), "已超预算")
        ledger.settings.overrides["2026-10"] = ["餐饮": nil]
        XCTAssertNil(ledger.settings.limit("餐饮", month: "2026-10"))
        XCTAssertEqual(try Backup.decode(Backup.encode(ledger)), ledger)
    }
    func testNativeBackupRoundTrip() throws {
        var ledger = Ledger(); ledger.entries = [entry()]
        XCTAssertEqual(try Backup.decode(Backup.encode(ledger)), ledger)
    }
    func testLegacyImportAndVoid() throws {
        let ledger = try Backup.decode(legacy())
        XCTAssertEqual(ledger.entries.count, 1); XCTAssertNotNil(ledger.entries[0].voidedAt)
        XCTAssertEqual(ledger.spent(month: "2026-10"), 0)
        XCTAssertEqual(ledger.settings.limit("餐饮", month: "2026-09"), 10000)
        XCTAssertNil(ledger.settings.limit("餐饮", month: "2026-10"))
    }
    func testRejectLegacyWrongCurrency() { XCTAssertThrowsError(try Backup.decode(legacy(currency: "CNY"))) }
    func testRejectCorruptAndOversizeBackups() {
        XCTAssertThrowsError(try Backup.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try Backup.decode(Data(repeating: 32, count: Backup.maximumBytes + 1)))
        let invalid = String(data: legacy(), encoding: .utf8)!.replacingOccurrences(of: "txn-ABCD-1234.json", with: "../txn-ABCD-1234.json")
        XCTAssertThrowsError(try Backup.decode(Data(invalid.utf8)))
    }
    func testDuplicateAndEdit() throws {
        var ledger = Ledger(); var a = entry(); a.fingerprint = "receipt"; try ledger.upsert(a)
        var b = a; b.id = "ABCD-5678"
        XCTAssertThrowsError(try ledger.upsert(b))
        a.amount = 3000; try ledger.upsert(a)
        XCTAssertEqual(ledger.entries.count, 1); XCTAssertEqual(ledger.spent(month: "2026-10"), 3000)
        b.fingerprint = ""; b.amount = 3000
        XCTAssertTrue(ledger.possibleDuplicate(of: b))
    }
    func testIdempotentImportAndConflict() throws {
        var ledger = Ledger(); ledger.entries = [entry()]
        XCTAssertEqual(try ledger.merging(ledger), ledger)
        var changed = ledger; changed.entries[0].amount += 1
        XCTAssertThrowsError(try ledger.merging(changed)); XCTAssertEqual(ledger.entries[0].amount, 2850)
    }
    func testValidation() {
        var ledger = Ledger(); var a = entry(); a.currency = "CNY"; ledger.entries = [a]
        XCTAssertThrowsError(try ledger.validate())
        ledger.entries = [entry(), entry()]; XCTAssertThrowsError(try ledger.validate())
        ledger.entries = []; ledger.settings.budgets["餐饮"] = -1; XCTAssertThrowsError(try ledger.validate())
    }
    func testAtomicPersistenceAndFailedValidation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = LedgerDisk(url: folder.appendingPathComponent("ledger.json"))
        XCTAssertTrue(try disk.load().entries.isEmpty)
        var ledger = Ledger(); ledger.entries = [entry()]; try disk.save(ledger)
        XCTAssertEqual(try disk.load(), ledger)
        var bad = ledger; bad.entries[0].amount = -1; XCTAssertThrowsError(try disk.save(bad))
        XCTAssertEqual(try disk.load(), ledger)
        try Data("broken".utf8).write(to: disk.url); XCTAssertThrowsError(try disk.load())
    }
}


extension LedgerCoreTests {
    func statement(_ lines: [String]) -> StatementResult {
        StatementParser.parse(lines.enumerated().map { OCRLine(text: $0.element, x: 0.1, y: 0.95 - Double($0.offset) * 0.07, height: 0.04) })
    }
    func testStatementRowsAndRepeatedAmounts() {
        let result = statement(["USD transactions", "2026-10-25", "Example Cafe 12.34", "Louis Vuitton 12.34", "Total USD 24.68", "Balance USD 100.00"])
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows.map(\.amount), ["12.34", "12.34"])
        XCTAssertEqual(result.rows.map(\.merchant), ["Example Cafe", "Louis Vuitton"])
        XCTAssertTrue(result.rows.allSatisfy { $0.date == "2026-10-25" && $0.explicitUSD && $0.blockedReason == nil })
        XCTAssertNotEqual(result.rows[0].fingerprint, result.rows[1].fingerprint)
    }
    func testStatementGeometryJoinsColumns() {
        let r = StatementParser.parse([
            OCRLine(text: "USD 9.25", x: 0.8, y: 0.7, height: 0.04),
            OCRLine(text: "Coffee Shop", x: 0.1, y: 0.704, height: 0.04),
            OCRLine(text: "2026-10-25", x: 0.1, y: 0.9, height: 0.04)])
        XCTAssertEqual(r.rows.count, 1); XCTAssertEqual(r.rows[0].merchant, "Coffee Shop")
        XCTAssertEqual(r.rows[0].amount, "9.25")
    }
    func testStatementBlocksCreditsSignedAmountsAndMixedCurrency() {
        for line in ["Refund USD 12.34", "Income +12.34", "Cafe -12.34", "Cafe USD 12.34 USD 15.00", "Cafe CAD 12.34"] {
            let r = statement([line]); XCTAssertEqual(r.rows.count, 1)
            XCTAssertNotNil(r.rows.first?.blockedReason, line)
        }
        XCTAssertFalse(statement(["Cafe $12.34"]).rows[0].explicitUSD)
        XCTAssertEqual(statement(["Total Wine USD 12.34"]).rows.count, 1)
    }
    func testStatementDatesNotInvented() {
        let r = statement(["Cafe USD 12.34", "2026-10-24 Shop USD 9.00", "Store USD 5.00"])
        XCTAssertEqual(r.rows.map(\.date), ["", "2026-10-24", ""])
        XCTAssertEqual(statement(["2026-10-24", "10/23", "Cafe 12.34"]).rows[0].date, "")
    }
    func testBatchAtomicValidationAndDuplicateImport() throws {
        let a = Entry(amount: 1234, merchant: "Cafe", date: "2026-10-25", category: "餐饮", fingerprint: "row-a")
        let b = Entry(amount: 725, merchant: "Store", date: "2026-10-25", category: "购物", fingerprint: "row-b")
        let original = Ledger()
        let saved = try original.addingBatch([a,b]); XCTAssertEqual(saved.entries.count, 2)
        XCTAssertThrowsError(try saved.addingBatch([a,b]))
        var bad = b; bad.date = "invalid"
        XCTAssertThrowsError(try original.addingBatch([a,bad])); XCTAssertTrue(original.entries.isEmpty)
        var duplicate = a; duplicate.id = UUID().uuidString
        XCTAssertThrowsError(try saved.addingBatch([duplicate], allowPossibleDuplicates: true))
    }
    func testBatchPossibleDuplicateRequiresExplicitOverride() throws {
        let a = Entry(amount: 1234, merchant: "Cafe", date: "2026-10-25", category: "餐饮", fingerprint: "row-a")
        let b = Entry(amount: 1234, merchant: "Cafe", date: "2026-10-25", category: "餐饮", fingerprint: "row-b")
        XCTAssertThrowsError(try Ledger().addingBatch([a,b]))
        XCTAssertEqual(try Ledger().addingBatch([a,b], allowPossibleDuplicates: true).entries.count, 2)
    }
}


extension LedgerCoreTests {
    func testStudentCategoriesAndLegacyCompatibility() throws {
        XCTAssertFalse(Ledger().visibleCategories().contains("教育"))
        XCTAssertTrue(Ledger().visibleCategories().contains("洗衣"))
        XCTAssertEqual(Categories.title("居家"), "超市日用")
        for (name, expected) in [("ChatGPT", "订阅"), ("Campus Laundry", "洗衣"), ("Barber Shop", "理发护理"), ("手机壳", "其他")] {
            XCTAssertEqual(Categories.suggest(name), expected)
        }
        var ledger = Ledger(); ledger.entries = [Entry(amount: 1000, merchant: "Old School", date: "2026-10-25", category: "教育")]
        ledger.settings.budgets["医疗"] = 2000
        XCTAssertTrue(ledger.visibleCategories().contains("教育")); XCTAssertTrue(ledger.visibleCategories().contains("医疗"))
        let restored = try Backup.decode(Backup.encode(ledger)); XCTAssertEqual(restored, ledger)
        XCTAssertEqual(restored.entries[0].category, "教育")
    }
}


extension LedgerCoreTests {
    func testOverlappingScreenshotsDefaultDuplicateAssessment() throws {
        var ledger = Ledger()
        ledger.entries = [Entry(amount: 1234, merchant: "Example Cafe", date: "2026-10-25", category: "餐饮", fingerprint: "old-image-row")]
        XCTAssertEqual(ledger.statementDuplicate(merchant: "EXAMPLE  CAFE", amount: "12.34", date: "2026-10-25", fingerprint: "new-image-row"), .suspected)
        XCTAssertEqual(ledger.statementDuplicate(merchant: "Example Cafe", amount: "12.34", date: "2026-10-26", fingerprint: "new-image-row"), .new)
        XCTAssertEqual(ledger.statementDuplicate(merchant: "OCR changed", amount: "12.34", date: "2026-10-25", fingerprint: "old-image-row"), .exact)
        ledger.entries[0].voidedAt = "2026-10-26T00:00:00Z"
        XCTAssertEqual(ledger.statementDuplicate(merchant: "Example Cafe", amount: "12.34", date: "2026-10-25", fingerprint: "old-image-row"), .new)
    }
}


extension LedgerCoreTests {
    func testTwentySecondCycleBoundaries() {
        XCTAssertEqual(LedgerDate.cycleKey(for: "2026-10-21"), "2026-09")
        XCTAssertEqual(LedgerDate.cycleKey(for: "2026-10-22"), "2026-10")
        XCTAssertEqual(LedgerDate.cycleKey(for: "2027-01-01"), "2026-12")
        XCTAssertTrue(LedgerDate.inCycle("2026-11-21", key: "2026-10"))
        XCTAssertFalse(LedgerDate.inCycle("2026-11-22", key: "2026-10"))
        XCTAssertTrue(LedgerDate.inCycle("2028-02-29", key: "2028-02"))
    }
    func testCycleSpendAndEstimatedDateNoteRoundTrip() throws {
        var ledger = Ledger()
        for date in ["2026-10-21", "2026-10-22", "2026-11-21", "2026-11-22"] {
            var row = Entry(amount: 100, merchant: "Example", date: date, category: "其他")
            row.note = "日期为用户授权的估计日期"
            ledger.entries.append(row)
        }
        XCTAssertEqual(ledger.cycleSpent(cycle: "2026-10"), 200)
        ledger.settings.budgets["其他"] = 250
        XCTAssertEqual(ledger.cycleStatus(category: "其他", cycle: "2026-10"), "接近预算")
        XCTAssertEqual(try Backup.decode(Backup.encode(ledger)), ledger)
    }
}

extension LedgerCoreTests {
    func testEnglishBankStatementReviewBoundaries() {
        let r = statement(["Bank of America", "Oct 25, 2026", "Example Cafe $12.34", "Example Market $5.67", "Payment received $18.01"])
        XCTAssertEqual(r.rows.count, 3)
        XCTAssertEqual(r.rows[0].merchant, "Example Cafe")
        XCTAssertEqual(r.rows[0].date, "2026-10-25")
        XCTAssertEqual(r.rows[0].amount, "12.34")
        XCTAssertFalse(r.rows[0].explicitUSD)
        XCTAssertNil(r.rows[0].blockedReason)
        XCTAssertNotNil(r.rows[2].blockedReason)
        let ambiguous = statement(["10/11/2026", "Example Cafe $12.34"])
        XCTAssertEqual(ambiguous.rows[0].date, "")
    }
}
