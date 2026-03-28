import XCTest
@testable import Pasha

final class ReceiptParserTests: XCTestCase {

    // MARK: - Amount Extraction

    func testExtractTotalAmount() {
        let lines = ["セブンイレブン 渋谷店", "おにぎり ¥150", "お茶 ¥130", "合計 ¥1,280"]
        let result = ReceiptParser.parse(lines: lines)
        XCTAssertEqual(result.amount, 1280, "Should extract 1280 from '合計 ¥1,280'")
    }

    func testExtractTotalAmountWithTax() {
        let lines = ["商品A ¥1,000", "商品B ¥1,300", "税込合計 ¥2,530"]
        let result = ReceiptParser.parse(lines: lines)
        XCTAssertEqual(result.amount, 2530, "Should extract 2530 from '税込合計 ¥2,530'")
    }

    // MARK: - Date Extraction

    func testExtractDate_YYYYMMDD() {
        let lines = ["2026/03/28", "合計 ¥500"]
        let result = ReceiptParser.parse(lines: lines)
        XCTAssertNotNil(result.date, "Should parse date from '2026/03/28'")

        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month, .day], from: result.date!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 28)
    }

    func testExtractDate_Reiwa() {
        let lines = ["令和8年3月28日", "合計 ¥500"]
        let result = ReceiptParser.parse(lines: lines)
        XCTAssertNotNil(result.date, "Should parse Reiwa date '令和8年3月28日'")

        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month, .day], from: result.date!)
        // 令和8 = 2026
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 28)
    }

    // MARK: - Vendor Extraction

    func testExtractVendor_KnownStore() {
        let lines = ["セブンイレブン 渋谷店", "2026/03/28", "おにぎり ¥150", "合計 ¥150"]
        let result = ReceiptParser.parse(lines: lines)
        XCTAssertEqual(result.vendor, "セブンイレブン 渋谷店")
    }

    // MARK: - Category Guess

    func testGuessCategory_Transport() {
        let lines = ["JR東日本", "乗車券 ¥200", "合計 ¥200"]
        let result = ReceiptParser.parse(lines: lines)
        XCTAssertEqual(result.category, "交通費", "JR東日本 should map to 交通費")
    }

    func testGuessCategory_Food() {
        let lines = ["まるやま食堂", "ランチ弁当 ¥800", "合計 ¥800"]
        let result = ReceiptParser.parse(lines: lines)
        XCTAssertEqual(result.category, "食費", "'ランチ弁当' should map to 食費")
    }

    // MARK: - Edge Cases

    func testEmptyLines() {
        let result = ReceiptParser.parse(lines: [])
        XCTAssertNil(result.amount)
        XCTAssertNil(result.date)
        XCTAssertNil(result.vendor)
        XCTAssertNil(result.category)
    }

    func testAmountWithoutKeyword_FallsBackToLargest() {
        let lines = ["¥300", "¥1,500", "¥200"]
        let result = ReceiptParser.parse(lines: lines)
        XCTAssertEqual(result.amount, 1500, "Without keyword, should pick largest yen amount")
    }
}
