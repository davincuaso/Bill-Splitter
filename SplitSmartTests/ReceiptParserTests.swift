import XCTest
@testable import SplitSmart

final class ReceiptParserTests: XCTestCase {

    private let parser = ReceiptParser()

    // MARK: - Helpers

    private func lines(_ strings: [String], confidence: Float = 0.95) -> [RecognizedLine] {
        strings.map { RecognizedLine(text: $0, confidence: confidence, boundingBox: .zero) }
    }

    // MARK: - Basic item detection

    func test_simpleItem_extractsNameAndPrice() {
        let result = parser.parse(lines(["Fried Rice    8.50"]))
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].name,  "Fried Rice")
        XCTAssertEqual(result.items[0].price, Decimal(string: "8.50")!)
        XCTAssertEqual(result.items[0].quantity, 1)
    }

    func test_multipleItems_allExtracted() {
        let input = [
            "Chicken Satay   12.00",
            "Nasi Goreng      9.50",
            "Teh Tarik        2.80",
        ]
        let result = parser.parse(lines(input))
        XCTAssertEqual(result.items.count, 3)
    }

    // MARK: - Quantity: "N x" pattern

    func test_qtyX_dividesPriceByQuantity() {
        // "2 x Beer 12.00" → qty=2, unitPrice=6.00, lineTotal=12.00
        let result = parser.parse(lines(["2 x Beer    12.00"]))
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].quantity, 2)
        XCTAssertEqual(result.items[0].price,    Decimal(string: "6.00")!)
        XCTAssertEqual(result.items[0].lineTotal, 12)
    }

    func test_qtyX_uppercase_divides() {
        let result = parser.parse(lines(["3 X Satay    9.00"]))
        XCTAssertEqual(result.items[0].quantity, 3)
        XCTAssertEqual(result.items[0].price,    Decimal(string: "3.00")!)
    }

    // MARK: - Quantity: leading digit pattern

    func test_leadingDigit_divides() {
        // "3 Fried Rice 24.00" → qty=3, unitPrice=8.00
        let result = parser.parse(lines(["3 Fried Rice    24.00"]))
        XCTAssertEqual(result.items[0].quantity, 3)
        XCTAssertEqual(result.items[0].price,    Decimal(string: "8.00")!)
    }

    func test_leadingOne_nochange() {
        // "1 Laksa 8.50" → qty=1, price=8.50 (dividing by 1 is a no-op)
        let result = parser.parse(lines(["1 Laksa    8.50"]))
        XCTAssertEqual(result.items[0].quantity, 1)
        XCTAssertEqual(result.items[0].price,    Decimal(string: "8.50")!)
    }

    // MARK: - Noise filtering

    func test_totalLine_skipped() {
        let result = parser.parse(lines(["Total    45.56"]))
        XCTAssertTrue(result.items.isEmpty)
    }

    func test_subtotalLine_skipped() {
        let result = parser.parse(lines(["Subtotal    38.00"]))
        XCTAssertTrue(result.items.isEmpty)
    }

    func test_thankYouLine_skipped() {
        let result = parser.parse(lines(["Thank you for dining with us"]))
        XCTAssertTrue(result.items.isEmpty)
    }

    func test_changeAndCash_skipped() {
        let input = ["Cash    50.00", "Change   4.44"]
        let result = parser.parse(lines(input))
        XCTAssertTrue(result.items.isEmpty)
    }

    // MARK: - Charge detection: percentage on line

    func test_gst_withPercentage_extracted() {
        let result = parser.parse(lines(["GST 9%    3.76"]))
        XCTAssertEqual(result.detectedCharges.gstPercentage, 9)
        XCTAssertTrue(result.items.isEmpty)
    }

    func test_serviceCharge_withPercentage_extracted() {
        let result = parser.parse(lines(["Service Charge 10%    5.82"]))
        XCTAssertEqual(result.detectedCharges.serviceChargePercentage, 10)
        XCTAssertTrue(result.items.isEmpty)
    }

    func test_vat_label_recognized() {
        let result = parser.parse(lines(["VAT 20%    16.00"]))
        XCTAssertEqual(result.detectedCharges.gstPercentage, 20)
        XCTAssertEqual(result.detectedCharges.gstLabel, "VAT")
    }

    // MARK: - Charge derivation from amounts

    func test_gstAmountOnly_derivesPercentage() {
        // Subtotal = $100, GST = $9 → derived rate should be ~9%
        let input = [
            "Food item    100.00",
            "GST    9.00",
            "Total    109.00",
        ]
        let result = parser.parse(lines(input))
        XCTAssertNotNil(result.detectedCharges.gstPercentage)
        // Allow ±1% tolerance for rounding during derivation
        let rate = result.detectedCharges.gstPercentage!
        XCTAssertTrue(rate >= 8 && rate <= 10, "Expected ~9%, got \(rate)")
    }

    // MARK: - Full Singapore receipt

    func test_singaporeReceipt_fullParse() {
        let receipt = [
            "HAWKER CENTRE TABLE 5",
            "--------------------------------",
            "1 Nasi Lemak          8.50",
            "2 x Teh Tarik         5.20",
            "Char Kway Teow        9.50",
            "3 Tiger Beer         21.00",
            "Chicken Wings        14.00",
            "--------------------------------",
            "Subtotal             58.20",
            "Service Charge 10%    5.82",
            "GST 9%                5.77",
            "TOTAL                69.79",
            "--------------------------------",
            "Thank you! Please come again.",
        ]
        let result = parser.parse(lines(receipt))

        XCTAssertEqual(result.items.count, 5, "Expected 5 items")
        XCTAssertEqual(result.detectedCharges.gstPercentage, 9)
        XCTAssertEqual(result.detectedCharges.serviceChargePercentage, 10)
        XCTAssertFalse(result.warnings.contains(.noItemsDetected))
        XCTAssertFalse(result.warnings.contains(.noChargesDetected))

        // Nasi Lemak: qty=1, price=8.50
        let nasiLemak = result.items.first { $0.name.lowercased().contains("nasi") }
        XCTAssertNotNil(nasiLemak)
        XCTAssertEqual(nasiLemak?.price,    Decimal(string: "8.50")!)
        XCTAssertEqual(nasiLemak?.quantity, 1)

        // Teh Tarik: qty=2, unit price=2.60
        let tehTarik = result.items.first { $0.name.lowercased().contains("teh") }
        XCTAssertNotNil(tehTarik)
        XCTAssertEqual(tehTarik?.quantity, 2)
        XCTAssertEqual(tehTarik?.price,    Decimal(string: "2.60")!)

        // Tiger Beer: qty=3, unit price=7.00
        let beer = result.items.first { $0.name.lowercased().contains("beer") }
        XCTAssertNotNil(beer)
        XCTAssertEqual(beer?.quantity, 3)
        XCTAssertEqual(beer?.price,    Decimal(string: "7.00")!)
    }

    // MARK: - Low confidence warning

    func test_lowConfidence_warningEmitted() {
        let lowConfidenceLines = lines(["Fried Rice    8.50"], confidence: 0.50)
        let result = parser.parse(lowConfidenceLines)
        XCTAssertTrue(result.warnings.contains(.lowOCRConfidence))
    }

    func test_highConfidence_noWarning() {
        let result = parser.parse(lines(["Fried Rice    8.50"], confidence: 0.95))
        XCTAssertFalse(result.warnings.contains(.lowOCRConfidence))
    }

    // MARK: - Empty input

    func test_emptyInput_noItemsWarning() {
        let result = parser.parse([])
        XCTAssertTrue(result.warnings.contains(.noItemsDetected))
        XCTAssertTrue(result.items.isEmpty)
    }

    // MARK: - Comma decimal (European format)

    func test_europeanCommaDecimal_parsed() {
        let result = parser.parse(lines(["Steak    24,50"]))
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].price, Decimal(string: "24.50")!)
    }

    // MARK: - Currency symbols

    func test_dollarSignInLine_parsed() {
        let result = parser.parse(lines(["Beer $6.00"]))
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].price, Decimal(string: "6.00")!)
    }

    // MARK: - Smart line grouping

    func test_sameRowColumns_mergedIntoItem() {
        // Two-column layout: name on left, price on right, same Y position.
        let nameLine  = RecognizedLine(text: "Chicken Rice", confidence: 0.95,
                                       boundingBox: CGRect(x: 0.0, y: 0.80, width: 0.45, height: 0.015))
        let priceLine = RecognizedLine(text: "8.50",         confidence: 0.95,
                                       boundingBox: CGRect(x: 0.70, y: 0.80, width: 0.25, height: 0.015))
        let result = parser.parse([nameLine, priceLine])
        XCTAssertEqual(result.items.count, 1, "Same-row columns should merge into one item")
        XCTAssertEqual(result.items[0].name, "Chicken Rice")
        XCTAssertEqual(result.items[0].price, Decimal(string: "8.50")!)
    }

    func test_differentRows_notMerged() {
        // Two items on separate rows — should yield two separate items.
        let row1Name  = RecognizedLine(text: "Chicken Rice", confidence: 0.95,
                                       boundingBox: CGRect(x: 0.0,  y: 0.80, width: 0.45, height: 0.015))
        let row1Price = RecognizedLine(text: "8.50",         confidence: 0.95,
                                       boundingBox: CGRect(x: 0.70, y: 0.80, width: 0.25, height: 0.015))
        let row2Name  = RecognizedLine(text: "Laksa",        confidence: 0.95,
                                       boundingBox: CGRect(x: 0.0,  y: 0.76, width: 0.30, height: 0.015))
        let row2Price = RecognizedLine(text: "7.00",         confidence: 0.95,
                                       boundingBox: CGRect(x: 0.70, y: 0.76, width: 0.25, height: 0.015))
        let result = parser.parse([row1Name, row1Price, row2Name, row2Price])
        XCTAssertEqual(result.items.count, 2, "Rows at different Y positions should not merge")
    }

    func test_zeroBoundingBox_groupingSkipped() {
        // Existing test-suite behavior: boundingBox: .zero → spatial grouping is skipped.
        let result = parser.parse(lines(["Nasi Lemak    8.50", "Laksa    7.00"]))
        XCTAssertEqual(result.items.count, 2)
    }

    // MARK: - Total reconciliation

    func test_subtotalMismatch_warningEmitted() {
        // Parser finds 2 items summing to 17.00, but receipt prints Subtotal 20.00.
        let input = [
            "Item A    10.00",
            "Item B     7.00",
            "Subtotal  20.00",
        ]
        let result = parser.parse(lines(input))
        let hasMismatch = result.warnings.contains {
            if case .totalMismatch = $0 { return true }
            return false
        }
        XCTAssertTrue(hasMismatch, "Expected totalMismatch warning when items don't add up to printed subtotal")
    }

    func test_subtotalMatch_noMismatchWarning() {
        let input = [
            "Chicken Rice    8.50",
            "Nasi Goreng     9.50",
            "Subtotal       18.00",
        ]
        let result = parser.parse(lines(input))
        let hasMismatch = result.warnings.contains {
            if case .totalMismatch = $0 { return true }
            return false
        }
        XCTAssertFalse(hasMismatch, "No mismatch warning expected when subtotals match")
    }

    func test_detectedSubtotal_stored() {
        let input = [
            "Chicken Rice    8.50",
            "Subtotal        8.50",
            "Total           9.27",
        ]
        let result = parser.parse(lines(input))
        XCTAssertEqual(result.detectedSubtotal, Decimal(string: "8.50")!)
        XCTAssertEqual(result.detectedTotal,    Decimal(string: "9.27")!)
    }

    func test_totalOnly_noSubtotalMismatchCheck() {
        // A grand total without a subtotal line should NOT trigger a mismatch warning,
        // because the total includes charges (items ≠ total is expected).
        let input = [
            "Food item    100.00",
            "GST            9.00",
            "Total        109.00",
        ]
        let result = parser.parse(lines(input))
        let hasMismatch = result.warnings.contains {
            if case .totalMismatch = $0 { return true }
            return false
        }
        XCTAssertFalse(hasMismatch, "No mismatch when only a grand total (not subtotal) is printed")
    }

    // MARK: - Multi-currency detection

    func test_detectCurrency_SGD() {
        let result = parser.parse(lines(["SGD", "Chicken Rice    8.50"]))
        XCTAssertEqual(result.detectedCurrencyCode, "SGD")
    }

    func test_detectCurrency_USD() {
        let result = parser.parse(lines(["USD", "Burger    12.00"]))
        XCTAssertEqual(result.detectedCurrencyCode, "USD")
    }

    func test_detectCurrency_EUR_symbol() {
        let result = parser.parse(lines(["Steak €24.50"]))
        XCTAssertEqual(result.detectedCurrencyCode, "EUR")
    }

    func test_detectCurrency_GBP_symbol() {
        let result = parser.parse(lines(["Fish & Chips £8.50"]))
        XCTAssertEqual(result.detectedCurrencyCode, "GBP")
    }

    func test_detectCurrency_nil_whenAmbiguous() {
        // "$" alone is ambiguous — should not resolve to a specific code.
        let result = parser.parse(lines(["Burger $12.00"]))
        XCTAssertNil(result.detectedCurrencyCode)
    }

    // MARK: - ML-lite correction store

    func test_correctionStore_skipLine() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = ParserCorrectionStore(userDefaults: defaults)
        store.record(ParserCorrection(shouldSkip: true), for: "Fried Rice    8.50")

        let correctedParser = ReceiptParser(correctionStore: store)
        let result = correctedParser.parse(lines(["Fried Rice    8.50"]))
        XCTAssertTrue(result.items.isEmpty, "Line marked shouldSkip must not appear as an item")
    }

    func test_correctionStore_nameOverride() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = ParserCorrectionStore(userDefaults: defaults)
        // User previously corrected "Freid Rice" (OCR typo) to "Fried Rice".
        store.record(ParserCorrection(correctedName: "Fried Rice"), for: "Freid Rice    8.50")

        let correctedParser = ReceiptParser(correctionStore: store)
        let result = correctedParser.parse(lines(["Freid Rice    8.50"]))
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].name, "Fried Rice")
    }

    func test_correctionStore_priceOverride() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = ParserCorrectionStore(userDefaults: defaults)
        // User corrected the parsed price from 8.50 to 9.50.
        store.record(
            ParserCorrection(correctedPrice: Decimal(string: "9.50")!),
            for: "Chicken Rice    8.50"
        )

        let correctedParser = ReceiptParser(correctionStore: store)
        let result = correctedParser.parse(lines(["Chicken Rice    8.50"]))
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].price, Decimal(string: "9.50")!)
    }

    func test_correctionStore_normalizesWhitespace() {
        // Key with extra spaces should match a line with collapsed spaces.
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = ParserCorrectionStore(userDefaults: defaults)
        store.record(ParserCorrection(shouldSkip: true), for: "Fried  Rice    8.50")  // extra space

        let correctedParser = ReceiptParser(correctionStore: store)
        let result = correctedParser.parse(lines(["Fried Rice    8.50"]))  // single space
        XCTAssertTrue(result.items.isEmpty, "Normalized key should match regardless of whitespace differences")
    }
}
