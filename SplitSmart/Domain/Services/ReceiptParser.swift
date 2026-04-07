import Foundation
import CoreGraphics

/// Pure receipt parsing engine.
///
/// Input:  `[RecognizedLine]`  (from `ReceiptScannerService`)
/// Output: `ParsedReceipt`     (fed into the user-review screen)
///
/// Design principle: be permissive rather than strict.
/// False positives are caught in the review screen; false negatives
/// (silently dropped items) are much worse UX.
public final class ReceiptParser {

    // MARK: - Dependencies

    private let correctionStore: ParserCorrectionStore?

    public init(correctionStore: ParserCorrectionStore? = nil) {
        self.correctionStore = correctionStore
    }

    // MARK: - Compiled regex patterns (allocated once, reused per call)

    /// Price at end of line, preceded by whitespace.
    private static let priceAfterSpace = try! NSRegularExpression(
        pattern: #"\s+(\d{1,4}[.,]\d{2})\s*$"#
    )
    /// Price at end of line preceded by a currency symbol.
    private static let priceAfterCurrency = try! NSRegularExpression(
        pattern: #"[$€£¥₱฿](\d{1,4}[.,]\d{2})\s*$"#
    )
    /// Explicit quantity marker: "2 x", "2x", "2 X", "2×"
    private static let qtyXPattern = try! NSRegularExpression(
        pattern: #"^(\d{1,2})\s*[xX×]\s*"#
    )
    /// Implicit quantity prefix: "3 " at the start of a line followed by letters
    private static let qtyLeadingDigit = try! NSRegularExpression(
        pattern: #"^(\d{1,2})\s+(?=[A-Za-z])"#
    )
    /// Percentage value anywhere in a line: "9%", "9.5 %", "(9%)"
    private static let percentPattern = try! NSRegularExpression(
        pattern: #"(\d{1,2}(?:\.\d{1,3})?)\s*%"#
    )

    // MARK: - Noise keyword sets

    /// Lines containing these words are always skipped (no item or charge data).
    private static let skipWords: Set<String> = [
        "total", "subtotal", "sub-total", "grand total",
        "change", "balance", "amount due", "amount paid",
        "cash", "visa", "mastercard", "amex", "nets",
        "receipt", "invoice", "order",
        "thank", "welcome", "visit", "please",
        "tel", "fax", "www", ".com", "http",
        "table", "server", "cashier", "staff",
        "opening", "closing",
    ]

    /// Lines containing these words carry charge data — parse separately.
    private static let chargeWords: Set<String> = [
        "gst", "vat", "tax",
        "service charge", "service fee", "srv charge", "svc charge", "svc",
    ]

    // MARK: - Public API

    public func parse(_ lines: [RecognizedLine]) -> ParsedReceipt {

        // ── 1. Spatial line grouping (merges same-row columns) ─────────────
        let grouped = groupLines(lines)

        // ── 2. Currency detection (full-receipt scan) ──────────────────────
        let currencyCode = detectCurrency(in: grouped)

        // ── 3. Total/subtotal extraction (pre-pass, before skipWords) ──────
        let (detectedTotal, detectedSubtotal) = extractTotals(from: grouped)

        // ── 4. Main parse loop ─────────────────────────────────────────────
        var items: [ParsedItem] = []
        var charges = DetectedCharges.empty
        var warnings: [ParseWarning] = []
        var appliedDivision = false

        let avgConfidence: Float = grouped.isEmpty ? 0
            : grouped.map(\.confidence).reduce(0, +) / Float(grouped.count)

        if avgConfidence < 0.70 { warnings.append(.lowOCRConfidence) }

        for line in grouped {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text.count >= 3 else { continue }

            let lower = text.lowercased()

            // User-trained skip overrides everything else.
            if let correction = correctionStore?.correction(for: text), correction.shouldSkip {
                continue
            }

            if isChargeLine(lower) {
                mergeCharge(parseChargeLine(text, lower: lower), into: &charges)
                continue
            }

            if isNoiseLine(lower) { continue }

            if let (item, divided) = parseItemLine(text, confidence: line.confidence) {
                // Apply any stored user corrections.
                var corrected = item
                if let correction = correctionStore?.correction(for: text) {
                    if let name  = correction.correctedName     { corrected.name     = name  }
                    if let price = correction.correctedPrice    { corrected.price    = price }
                    if let qty   = correction.correctedQuantity { corrected.quantity = qty   }
                }
                items.append(corrected)
                if divided { appliedDivision = true }
            }
        }

        // ── 5. Derive missing charge percentages from amounts ──────────────
        let subtotal = items.reduce(Decimal.zero) { $0 + $1.lineTotal }
        charges = deriveRates(charges, subtotal: subtotal)

        // ── 6. Total reconciliation (subtotal only — detectedTotal includes charges) ──
        if let reference = detectedSubtotal, subtotal > 0 {
            let diff      = abs(subtotal - reference)
            let threshold = max(Decimal(string: "0.10")!, reference * Decimal(string: "0.03")!)
            if diff > threshold {
                warnings.append(.totalMismatch(computed: subtotal, detected: reference))
            }
        }

        // ── 7. Build remaining warnings ────────────────────────────────────
        if appliedDivision { warnings.append(.quantityDivisionApplied) }
        if items.isEmpty   { warnings.append(.noItemsDetected) }
        if charges.gstPercentage == nil,
           charges.serviceChargePercentage == nil { warnings.append(.noChargesDetected) }

        return ParsedReceipt(
            items: items,
            detectedCharges: charges,
            rawLines: lines,             // keep original ungrouped lines for display
            overallConfidence: avgConfidence,
            warnings: warnings,
            detectedSubtotal: detectedSubtotal,
            detectedTotal: detectedTotal,
            detectedCurrencyCode: currencyCode
        )
    }

    // MARK: - 1. Spatial line grouping

    /// Groups OCR observations that fall on the same horizontal row (e.g. name column + price
    /// column on a two-column receipt layout), then sorts within each group left-to-right and
    /// merges text with a three-space separator so the existing price-at-end regex still fires.
    ///
    /// Falls back to the unmodified input when bounding boxes are unavailable (zero-area),
    /// which happens in unit tests where `boundingBox: .zero` is used.
    private func groupLines(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        guard lines.count > 1 else { return lines }

        // Require at least one non-zero bounding box to proceed.
        guard lines.contains(where: { $0.boundingBox != .zero }) else { return lines }

        // Sort top-to-bottom (Vision Y is bottom-left origin, so higher Y = higher on receipt).
        let sorted = lines.sorted {
            let mid0 = ($0.boundingBox.minY + $0.boundingBox.maxY) / 2
            let mid1 = ($1.boundingBox.minY + $1.boundingBox.maxY) / 2
            return mid0 > mid1
        }

        // Group consecutive lines whose midY values are within ~1% of image height.
        // Typical receipt line height: 1.5%; adjacent rows: ≥1.5% apart.
        let threshold: CGFloat = 0.010

        var groups: [[RecognizedLine]] = []
        var currentGroup: [RecognizedLine] = [sorted[0]]

        for line in sorted.dropFirst() {
            let anchorMidY = (currentGroup[0].boundingBox.minY + currentGroup[0].boundingBox.maxY) / 2
            let lineMidY   = (line.boundingBox.minY + line.boundingBox.maxY) / 2

            if abs(anchorMidY - lineMidY) < threshold {
                currentGroup.append(line)
            } else {
                groups.append(currentGroup)
                currentGroup = [line]
            }
        }
        groups.append(currentGroup)

        return groups.map { group -> RecognizedLine in
            guard group.count > 1 else { return group[0] }
            let byX        = group.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let mergedText = byX.map(\.text).joined(separator: "   ")
            let minConf    = byX.map(\.confidence).min() ?? 0
            let mergedBox  = byX.reduce(CGRect.null) { $0.union($1.boundingBox) }
            return RecognizedLine(text: mergedText, confidence: minConf, boundingBox: mergedBox)
        }
    }

    // MARK: - 2. Currency detection

    private static let isoCurrencyPattern = try! NSRegularExpression(
        pattern: #"\b(SGD|USD|EUR|GBP|MYR|JPY|AUD|HKD|THB|PHP|IDR|CNY|CAD|NZD|CHF|TWD|SEK|NOK|DKK)\b"#,
        options: .caseInsensitive
    )

    /// Scans all lines for an unambiguous currency signal.
    /// Returns an ISO 4217 code, or `nil` when no confident match is found.
    private func detectCurrency(in lines: [RecognizedLine]) -> String? {
        let joined = lines.map(\.text).joined(separator: " ")
        let upper  = joined.uppercased()

        // ISO codes with implicit word-boundary disambiguation via the regex.
        let nsRange = NSRange(joined.startIndex..., in: joined)
        if let match = Self.isoCurrencyPattern.firstMatch(in: joined, range: nsRange),
           let range = Range(match.range(at: 1), in: joined) {
            return joined[range].uppercased()
        }

        // Multi-character currency prefixes (no word-boundary ambiguity).
        let prefixMap: [(String, String)] = [
            ("S$",  "SGD"),
            ("US$", "USD"),
            ("A$",  "AUD"),
            ("HK$", "HKD"),
            ("C$",  "CAD"),
        ]
        for (token, code) in prefixMap where upper.contains(token) {
            return code
        }

        // Unambiguous Unicode currency symbols.
        if joined.contains("€") { return "EUR" }
        if joined.contains("£") { return "GBP" }
        if joined.contains("¥") { return "JPY" }
        if joined.contains("฿") { return "THB" }
        if joined.contains("₱") { return "PHP" }

        // "$" alone is too ambiguous to resolve without more context.
        return nil
    }

    // MARK: - 3. Total / subtotal extraction

    /// Scans lines for printed subtotal and grand-total values.
    /// Runs as a pre-pass so `skipWords` filtering in the main loop doesn't hide these values.
    private func extractTotals(
        from lines: [RecognizedLine]
    ) -> (total: Decimal?, subtotal: Decimal?) {
        var total:    Decimal?
        var subtotal: Decimal?

        for line in lines {
            let lower = line.text.lowercased().trimmingCharacters(in: .whitespaces)
            guard let (_, price) = extractTrailingPrice(from: line.text) else { continue }

            if lower.contains("subtotal") || lower.contains("sub-total") || lower.contains("sub total") {
                subtotal = price
            } else if (lower.hasPrefix("total") || lower.contains("grand total")
                        || lower.contains("amount due") || lower.contains("balance due"))
                        && !lower.contains("subtotal") {
                total = price
            }
        }
        return (total, subtotal)
    }

    // MARK: - Classification

    private func isChargeLine(_ lower: String) -> Bool {
        Self.chargeWords.contains { lower.contains($0) }
    }

    private func isNoiseLine(_ lower: String) -> Bool {
        Self.skipWords.contains { lower.contains($0) }
    }

    // MARK: - Item parsing

    /// Returns (item, priceWasDivided) or nil if the line cannot be parsed as an item.
    private func parseItemLine(
        _ text: String,
        confidence: Float
    ) -> (ParsedItem, Bool)? {
        // Must have a price at the end.
        guard let (nameEnd, rawPrice) = extractTrailingPrice(from: text) else { return nil }

        // Price validation: reject implausibly small values (likely item codes or dates).
        guard rawPrice >= Decimal(string: "0.01")! else { return nil }

        var nameRegion = String(text[text.startIndex..<nameEnd])
            .trimmingCharacters(in: .whitespaces)

        // Strip any stray currency symbol left at the end of the name region.
        nameRegion = nameRegion.replacingOccurrences(
            of: #"[\$€£¥₱฿S]+\s*$"#, with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)

        guard !nameRegion.isEmpty else { return nil }

        // ── Quantity detection ──────────────────────────────────────────
        var quantity  = 1
        var divided   = false
        var cleanName = nameRegion
        let nsRange   = NSRange(nameRegion.startIndex..., in: nameRegion)

        if let m = Self.qtyXPattern.firstMatch(in: nameRegion, range: nsRange),
           let qRange = Range(m.range(at: 1), in: nameRegion),
           let q = Int(nameRegion[qRange]), q > 0, q <= 99 {
            quantity  = q
            divided   = true
            let after = nameRegion.index(nameRegion.startIndex, offsetBy: m.range.length)
            cleanName = String(nameRegion[after...]).trimmingCharacters(in: .whitespaces)

        } else if let m = Self.qtyLeadingDigit.firstMatch(in: nameRegion, range: nsRange),
                  let qRange = Range(m.range(at: 1), in: nameRegion),
                  let q = Int(nameRegion[qRange]), q > 0, q <= 9 {
            quantity  = q
            divided   = true
            let after = nameRegion.index(nameRegion.startIndex, offsetBy: m.range.length)
            cleanName = String(nameRegion[after...]).trimmingCharacters(in: .whitespaces)
        }

        // Unit price
        let unitPrice: Decimal = divided && quantity > 1
            ? (rawPrice / Decimal(quantity)).roundedTo(scale: 2)
            : rawPrice

        // Reject degenerate names.
        cleanName = cleanName
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespaces)

        // Name must start with a letter, be at least 2 chars, and have a valid price.
        guard !cleanName.isEmpty,
              cleanName.count >= 2,
              cleanName.first?.isLetter == true,
              unitPrice > 0 else { return nil }

        // Reject if "name" is all digits — it's likely a product code, not a food item.
        guard !cleanName.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) else { return nil }

        let item = ParsedItem(
            name: cleanName,
            price: unitPrice,
            quantity: quantity,
            lineConfidence: confidence,
            rawLine: text
        )
        return (item, divided)
    }

    // MARK: - Charge line parsing

    private struct ChargeExtraction {
        var isGST: Bool
        var label: String
        var percentage: Decimal?
        var amount: Decimal?
    }

    private func parseChargeLine(_ text: String, lower: String) -> ChargeExtraction {
        let isGST = lower.contains("gst") || lower.contains("vat") || lower.contains("tax")

        let label: String
        if      lower.contains("gst")            { label = "GST" }
        else if lower.contains("vat")            { label = "VAT" }
        else if lower.contains("tax")            { label = "Tax" }
        else if lower.contains("service fee")    { label = "Service Fee" }
        else                                     { label = "Service Charge" }

        let pct    = extractPercentage(from: text)
        let amount = extractTrailingPrice(from: text)?.1

        return ChargeExtraction(isGST: isGST, label: label, percentage: pct, amount: amount)
    }

    private func mergeCharge(_ ext: ChargeExtraction, into charges: inout DetectedCharges) {
        if ext.isGST {
            if charges.gstPercentage == nil { charges.gstPercentage = ext.percentage }
            if charges.gstAmount     == nil { charges.gstAmount     = ext.amount     }
            charges.gstLabel = ext.label
        } else {
            if charges.serviceChargePercentage == nil { charges.serviceChargePercentage = ext.percentage }
            if charges.serviceChargeAmount     == nil { charges.serviceChargeAmount     = ext.amount     }
            charges.serviceLabel = ext.label
        }
    }

    // MARK: - Percentage derivation

    private func deriveRates(_ charges: DetectedCharges, subtotal: Decimal) -> DetectedCharges {
        guard subtotal > 0 else { return charges }
        var updated = charges

        if updated.gstPercentage == nil, let amt = updated.gstAmount, amt > 0 {
            let rate = (amt / subtotal * 100).roundedTo(scale: 1)
            if rate >= 1 && rate <= 30 { updated.gstPercentage = rate }
        }
        if updated.serviceChargePercentage == nil, let amt = updated.serviceChargeAmount, amt > 0 {
            let rate = (amt / subtotal * 100).roundedTo(scale: 1)
            if rate >= 1 && rate <= 25 { updated.serviceChargePercentage = rate }
        }
        return updated
    }

    // MARK: - Extraction helpers

    /// Finds a decimal price at the end of the string.
    /// Returns the index where the price portion starts (for name trimming) and the parsed value.
    private func extractTrailingPrice(from text: String) -> (nameEnd: String.Index, price: Decimal)? {
        let nsRange = NSRange(text.startIndex..., in: text)

        for pattern in [Self.priceAfterCurrency, Self.priceAfterSpace] {
            guard let match        = pattern.firstMatch(in: text, range: nsRange),
                  let captureRange = Range(match.range(at: 1), in: text),
                  let fullRange    = Range(match.range, in: text) else { continue }

            let priceStr = String(text[captureRange]).replacingOccurrences(of: ",", with: ".")
            guard let price = Decimal(string: priceStr, locale: Locale(identifier: "en_US_POSIX")),
                  price > 0, price < 10_000 else { continue }

            return (fullRange.lowerBound, price)
        }
        return nil
    }

    private func extractPercentage(from text: String) -> Decimal? {
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match        = Self.percentPattern.firstMatch(in: text, range: nsRange),
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return Decimal(string: String(text[captureRange]), locale: Locale(identifier: "en_US_POSIX"))
    }
}

// MARK: - Decimal helper

extension Decimal {
    /// Rounds to `scale` decimal places using plain (half-up) rounding.
    func roundedTo(scale: Int) -> Decimal {
        var result = Decimal()
        var input  = self
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}
