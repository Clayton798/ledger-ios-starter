import XCTest
import UIKit

final class LocalLedgerUITests: XCTestCase {
    @MainActor func testBundledEditorialFont() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.staticTexts["overview.spent"].waitForExistence(timeout: 8))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "宋体排版首页"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["分析"].tap()
        XCTAssertTrue(app.buttons["环形"].waitForExistence(timeout: 5))
        let chart = XCTAttachment(screenshot: app.screenshot()); chart.name = "宋体分类分析"; chart.lifetime = .keepAlways; add(chart)
    }

    @MainActor func testSharedCycleAndLaunch() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["周期"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["本地账本"].exists)
        app.buttons["周期"].tap()
        app.buttons["上一期"].tap()
        let period = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]{4}-[0-9]{2}-22 至 [0-9]{4}-[0-9]{2}-21")).firstMatch
        XCTAssertTrue(period.exists)
        let selected = period.label
        app.buttons["分析"].tap()
        XCTAssertTrue(app.staticTexts[selected].exists)
        app.buttons["记账"].tap()
        XCTAssertTrue(app.staticTexts[selected].exists)
        app.buttons["下一期"].tap()
        app.buttons["周期"].tap()
        XCTAssertFalse(app.staticTexts[selected].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["手动记一笔"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["opening.cover"].exists)
    }

    @MainActor func testSimpleSettingsAndLegacyChart() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-spendingChartStyle", "饼图"]
        app.launch(); app.buttons["分析"].tap()
        XCTAssertFalse(app.buttons["饼图"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["spending.categories"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["设置"].tap()
        for _ in 0..<3 {
            if app.buttons["保存一份账本副本"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["保存一份账本副本"].exists)
        XCTAssertTrue(app.buttons["从文件找回账本"].exists)
        XCTAssertFalse(app.buttons["导出完整 JSON 备份"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "简约设置"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testEditorialOverviewEntryAccess() throws {
        let app = XCUIApplication(); app.launch(); app.buttons["周期"].tap()
        XCTAssertTrue(app.staticTexts["overview.spent"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "正式私人账簿首页"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["手动记一笔"].tap()
        XCTAssertTrue(app.textFields["金额（USD，例如 12.50）"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
        for _ in 0..<5 {
            if app.buttons["查看分类预算"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["查看分类预算"].tap()
        XCTAssertTrue(app.navigationBars["预算与剩余"].waitForExistence(timeout: 5))
    }

    @MainActor func testGuideAndSearch() throws {
        let app = XCUIApplication(); app.launch()
        app.buttons["设置"].tap()
        app.buttons["快速上手指南"].tap()
        XCTAssertTrue(app.staticTexts["生活有数，\n花钱有度。"].waitForExistence(timeout: 5))
        let guide = XCTAttachment(screenshot: app.screenshot()); guide.name = "新版上手指南"; guide.lifetime = .keepAlways; add(guide)
        app.buttons["完成"].tap()
        app.buttons["记账"].tap()
        app.swipeDown()
        let search = app.textFields["entries.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("NoSuchMerchant987654")
        XCTAssertTrue(app.staticTexts["没有找到匹配记录"].waitForExistence(timeout: 5))
    }

    @MainActor func testOnDeviceVisionOCR() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 900)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 900))
            let lines = ["Payment successful", "Merchant: Example Cafe", "Amount paid: USD 12.34", "2026-10-25", "Transaction ID: TEST12345678", "Request refund"]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 60, y: 60 + index * 110), withAttributes: [.font: UIFont.systemFont(ofSize: 42), .foregroundColor: UIColor.black])
            }
        }
        let text = try await ReceiptOCR.recognize(XCTUnwrap(image.pngData()))
        let receipt = ReceiptParser.parse(text)
        XCTAssertEqual(receipt.amounts, [1234], text)
        XCTAssertEqual(receipt.merchant, "Example Cafe", text)
        XCTAssertEqual(receipt.dates, ["2026-10-25"], text)
        XCTAssertTrue(receipt.explicitUSD); XCTAssertNil(receipt.blockedReason)
        let attachment = XCTAttachment(image: image); attachment.name = "虚构OCR测试图"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testChineseVisionOCR() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 900)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 900))
            let lines = ["支付成功", "商户名称：示例咖啡", "实付：USD 12.34", "2026-10-25", "交易单号：TEST12345678", "申请退款"]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 60, y: 60 + index * 110), withAttributes: [.font: UIFont.systemFont(ofSize: 42), .foregroundColor: UIColor.black])
            }
        }
        let text = try await ReceiptOCR.recognize(XCTUnwrap(image.pngData()))
        let receipt = ReceiptParser.parse(text)
        XCTAssertEqual(receipt.amounts, [1234], text)
        XCTAssertEqual(receipt.merchant, "示例咖啡", text)
        XCTAssertEqual(receipt.dates, ["2026-10-25"], text)
        XCTAssertTrue(receipt.explicitUSD); XCTAssertNil(receipt.blockedReason)
        let attachment = XCTAttachment(image: image); attachment.name = "虚构中文OCR测试图"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testManualEntryPersistenceAndVoid() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["overview.spent"].waitForExistence(timeout: 15))
        app.buttons["记账"].tap()
        app.buttons["手动记一笔"].tap()
        let merchant = "虚构UI测试-" + String(UUID().uuidString.prefix(6))
        let amount = app.textFields["金额（USD，例如 12.50）"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap(); amount.typeText("12.34")
        let field = app.textFields["商家"]
        field.tap(); field.typeText(merchant)
        app.swipeUp()
        XCTAssertFalse(app.switches["确认币种为美元 USD"].exists)
        XCTAssertTrue(app.buttons["确认并保存"].isEnabled)
        app.buttons["确认并保存"].tap()
        XCTAssertTrue(app.alerts["已保存"].waitForExistence(timeout: 5))
        app.alerts.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts[merchant].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "保存虚构消费"; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launch(); app.buttons["记账"].tap()
        XCTAssertTrue(app.staticTexts[merchant].waitForExistence(timeout: 5))
        app.staticTexts[merchant].tap(); app.swipeUp()
        app.buttons["作废此笔"].tap()
        app.alerts.buttons["作废"].tap()
        XCTAssertFalse(app.staticTexts[merchant].exists)
        app.switches["显示已作废"].switches.firstMatch.tap()
        XCTAssertTrue(app.staticTexts[merchant].exists)
    }

    @MainActor func testMerchantCategoryMemory() throws {
        let app = XCUIApplication(); app.launch(); app.buttons["记账"].tap()
        let merchant = "Memory Store " + String(UUID().uuidString.prefix(6))
        app.buttons["手动记一笔"].tap()
        let amount = app.textFields["金额（USD，例如 12.50）"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); amount.tap(); amount.typeText("7.25")
        app.textFields["商家"].tap(); app.textFields["商家"].typeText(merchant)
        app.buttons["entry.category"].tap(); app.buttons["超市日用"].tap()
        app.swipeUp(); app.buttons["确认并保存"].tap()
        XCTAssertTrue(app.alerts["已保存"].waitForExistence(timeout: 5)); app.alerts.buttons["完成"].tap()
        app.terminate(); app.launch(); app.buttons["记账"].tap(); app.buttons["手动记一笔"].tap()
        app.textFields["商家"].tap(); app.textFields["商家"].typeText(merchant)
        XCTAssertEqual(app.buttons["entry.category"].value as? String, "超市日用")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "自动记住商家分类"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["关闭"].tap()
    }

    @MainActor func testStudentBudgetSettings() throws {
        let app = XCUIApplication(); app.launch(); app.buttons["设置"].tap()
        app.buttons["调整每类能花多少钱"].tap()
        XCTAssertTrue(app.navigationBars["分类预算"].waitForExistence(timeout: 5))
        let laundry = app.textFields["budget.洗衣"]
        for _ in 0..<5 { if laundry.isHittable { break }; app.swipeUp() }
        app.swipeUp()
        laundry.tap()
        if let old = laundry.value as? String, old != "不设预算" { laundry.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        laundry.typeText("16")
        for _ in 0..<5 { if app.buttons["保存预算"].isHittable { break }; app.swipeUp() }
        app.buttons["保存预算"].tap()
        XCTAssertTrue(app.alerts["预算"].waitForExistence(timeout: 5))
        app.alerts.buttons["知道了"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "预算设置"; shot.lifetime = .keepAlways; add(shot)
    }
}


extension LocalLedgerUITests {
    @MainActor func testStatementVisionRows() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
            for (index, line) in ["USD Transactions", "2026-10-25", "Example Cafe     12.34", "Louis Vuitton     55.00", "Total USD 67.34"].enumerated() {
                (line as NSString).draw(at: CGPoint(x: 60, y: 60 + index * 140), withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black])
            }
        }
        let lines = try await ReceiptOCR.recognizeLines(XCTUnwrap(image.pngData()))
        let result = StatementParser.parse(lines)
        XCTAssertEqual(result.rows.count, 2, result.text)
        XCTAssertEqual(result.rows.map(\.amount), ["12.34", "55.00"], result.text)
        XCTAssertEqual(result.rows.map(\.merchant), ["Example Cafe", "Louis Vuitton"], result.text)
        XCTAssertTrue(result.rows.allSatisfy { $0.date == "2026-10-25" && $0.explicitUSD && $0.blockedReason == nil }, result.text)
        let shot = XCTAttachment(image: image); shot.name = "虚构多笔账单"; shot.lifetime = .keepAlways; add(shot)
    }
}


extension LocalLedgerUITests {
    @MainActor func testStatementPhotoReview() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LOCAL_LEDGER_PHOTO_FIXTURE"] == "initial", "Requires a dedicated simulator seeded with the original synthetic statement photo and no prior copies of those transactions.")
        let app = XCUIApplication(); app.launch(); app.buttons["记账"].tap()
        app.buttons["识别账单列表（多笔）"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5) || app.buttons["取消"].exists)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["正在加载…"].firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 30), .completed)
        let photo = app.images.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "PXGGridLayout-Info", "Screenshot")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10)); photo.tap()
        XCTAssertTrue(app.navigationBars["账单批量核对"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["保存所选 2 笔"].exists)
        XCTAssertFalse(app.buttons["保存所选 2 笔"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "多笔账单核对"; shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<5 { if app.switches["已逐笔核对，所选均为美元支出"].isHittable { break }; app.swipeUp() }
        app.switches["已逐笔核对，所选均为美元支出"].switches.firstMatch.tap()
        app.buttons["确认保存所选消费"].tap()
        XCTAssertTrue(app.alerts["已保存所选消费"].waitForExistence(timeout: 5))
        app.alerts.buttons["完成"].tap()
        app.terminate(); app.launch(); app.buttons["记账"].tap()
        XCTAssertTrue(app.staticTexts["Louis Vuitton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Example Cafe"].exists)
    }
}


extension LocalLedgerUITests {
    // Seed the synthetic overlapping statement as the newest simulator photo
    // after testStatementPhotoReview has saved the original two rows.
    @MainActor func testOverlappingStatementReview() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LOCAL_LEDGER_PHOTO_FIXTURE"] == "overlap", "Requires the original two synthetic transactions and the overlapping statement as the newest simulator photo.")
        let app = XCUIApplication(); app.launch(); app.buttons["记账"].tap()
        app.buttons["识别账单列表（多笔）"].tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 20)); photo.tap()
        XCTAssertTrue(app.navigationBars["账单批量核对"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["保存所选 1 笔"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "疑似已记过")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "重叠账单默认跳过旧消费"; shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<8 { if app.switches["已逐笔核对，所选均为美元支出"].isHittable { break }; app.swipeUp() }
        app.switches["已逐笔核对，所选均为美元支出"].switches.firstMatch.tap()
        app.buttons["确认保存所选消费"].tap()
        XCTAssertTrue(app.alerts["已保存所选消费"].waitForExistence(timeout: 5)); app.alerts.buttons["完成"].tap()
        app.buttons["识别账单列表（多笔）"].tap()
        XCTAssertTrue(photo.waitForExistence(timeout: 15)); photo.tap()
        XCTAssertTrue(app.navigationBars["账单批量核对"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["保存所选 0 笔"].exists)
        XCTAssertFalse(app.buttons["保存所选 0 笔"].isEnabled)
        app.buttons["关闭"].tap()
    }
}

extension LocalLedgerUITests {
    @MainActor func testSpendingChartModes() throws {
        let app = XCUIApplication(); app.launch(); app.buttons["分析"].tap()
        let pie = app.buttons["环形"]
        for _ in 0..<4 { if pie.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(pie.waitForExistence(timeout: 5))
        for style in ["环形", "条形", "趋势"] {
            app.buttons[style].tap()
            let identifier = style == "趋势" ? "spending.trend" : "spending.categories"
            XCTAssertTrue(app.descendants(matching: .any)[identifier].firstMatch.waitForExistence(timeout: 5))
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "支出图表-" + style; shot.lifetime = .keepAlways; add(shot)
        }
        app.terminate(); app.launch(); app.buttons["分析"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["spending.trend"].firstMatch.waitForExistence(timeout: 5))
    }
}
