import Foundation
import CoreGraphics

// MARK: - OCR output

/// One recognized line from Vision, preserving confidence and position.
public struct RecognizedLine: Sendable {
    /// The recognized text string.
    public let text: String
    /// Vision's confidence for this observation (0–1).
    public let confidence: Float
    /// Normalized bounding box in Vision coordinates (origin bottom-left, Y flipped).
    public let boundingBox: CGRect
}

// MARK: - Parser output

/// All structured data extracted from a scanned receipt.
/// Produced by `ReceiptParser`; consumed by `ScanReviewView` and ultimately
/// converted into `[BillItem]` + `Charges` via `BillViewModel.applyParsedReceipt`.
public struct ParsedReceipt: Sendable {
    public var items: [ParsedItem]
    public var detectedCharges: DetectedCharges
    /// The raw OCR output — kept for debugging and the optional confidence overlay.
    public let rawLines: [RecognizedLine]
    /// Mean confidence across all recognized lines (0–1).
    public let overallConfidence: Float
    /// Non-fatal issues the parser noticed.
    public var warnings: [ParseWarning]

    /// The printed subtotal (before charges) found on the receipt, if any.
    public var detectedSubtotal: Decimal? = nil
    /// The printed grand total (after charges) found on the receipt, if any.
    public var detectedTotal: Decimal? = nil
    /// ISO 4217 currency code detected from the receipt text (e.g. "SGD", "USD"). `nil` if ambiguous.
    public var detectedCurrencyCode: String? = nil

    public var hasLowConfidence: Bool { overallConfidence < 0.70 }
}

// MARK: - Parsed item

/// One receipt line interpreted as a purchasable item.
public struct ParsedItem: Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Unit price (lineTotal / quantity).
    public var price: Decimal
    public var quantity: Int
    /// Vision confidence of the originating line (0–1).
    public let lineConfidence: Float
    /// The raw OCR string for display in the review screen.
    public let rawLine: String

    public var lineTotal: Decimal { price * Decimal(quantity) }

    public init(
        id: UUID = UUID(),
        name: String,
        price: Decimal,
        quantity: Int,
        lineConfidence: Float,
        rawLine: String
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.quantity = quantity
        self.lineConfidence = lineConfidence
        self.rawLine = rawLine
    }
}

// MARK: - Detected charges

/// Tax and service-charge data extracted from the receipt.
/// Optional values indicate the receipt was ambiguous on that field.
public struct DetectedCharges: Sendable {
    /// Detected percentage (e.g. 9 for "GST 9%"). `nil` if not found.
    public var gstPercentage: Decimal?
    /// Detected percentage (e.g. 10 for "Service Charge 10%"). `nil` if not found.
    public var serviceChargePercentage: Decimal?
    /// The label as it appeared on the receipt ("GST", "VAT", "Tax").
    public var gstLabel: String
    /// The label as it appeared on the receipt ("Service Charge", "SVC").
    public var serviceLabel: String
    /// Detected amount (used to derive percentage when the rate wasn't printed).
    public var gstAmount: Decimal?
    public var serviceChargeAmount: Decimal?

    public static let empty = DetectedCharges(
        gstPercentage: nil,
        serviceChargePercentage: nil,
        gstLabel: "GST",
        serviceLabel: "Service Charge",
        gstAmount: nil,
        serviceChargeAmount: nil
    )
}

// MARK: - Warnings

public enum ParseWarning: Equatable, Hashable, Sendable {
    case lowOCRConfidence
    case noItemsDetected
    case noChargesDetected
    /// Prices were divided by quantity to obtain unit prices.
    case quantityDivisionApplied
    /// The sum of parsed items doesn't match the printed subtotal within tolerance.
    case totalMismatch(computed: Decimal, detected: Decimal)
}
