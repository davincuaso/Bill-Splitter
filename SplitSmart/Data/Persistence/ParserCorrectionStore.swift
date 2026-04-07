import Foundation

// MARK: - Correction model

/// Records what a user changed for a specific raw OCR line.
/// Used by `ReceiptParser` to apply learned corrections on future scans.
public struct ParserCorrection: Codable {
    /// Overrides the parsed item name. `nil` = use parser's value.
    public var correctedName: String?
    /// Overrides the parsed unit price. `nil` = use parser's value.
    public var correctedPrice: Decimal?
    /// Overrides the parsed quantity. `nil` = use parser's value.
    public var correctedQuantity: Int?
    /// When `true`, the parser will skip this line entirely on future scans.
    public var shouldSkip: Bool

    public init(
        correctedName: String?     = nil,
        correctedPrice: Decimal?   = nil,
        correctedQuantity: Int?    = nil,
        shouldSkip: Bool           = false
    ) {
        self.correctedName     = correctedName
        self.correctedPrice    = correctedPrice
        self.correctedQuantity = correctedQuantity
        self.shouldSkip        = shouldSkip
    }
}

// MARK: - Store

/// On-device store that persists user corrections to OCR lines.
///
/// The lookup key is the normalized raw OCR text (lowercased, whitespace collapsed),
/// so minor scan-to-scan OCR variance still resolves to the same correction entry.
///
/// All storage is via `UserDefaults` — fully on-device, no network access.
public final class ParserCorrectionStore {

    // MARK: - Storage

    private static let defaultKey = "splitsmart.parser.corrections.v1"

    private let userDefaults: UserDefaults
    private let storageKey: String
    private var corrections: [String: ParserCorrection] = [:]

    // MARK: - Init

    /// - Parameters:
    ///   - userDefaults: Defaults suite to use. Pass a test-specific suite in unit tests.
    ///   - key: Storage key. Override in tests to avoid polluting the real store.
    public init(
        userDefaults: UserDefaults = .standard,
        key: String = ParserCorrectionStore.defaultKey
    ) {
        self.userDefaults = userDefaults
        self.storageKey   = key
        load()
    }

    // MARK: - Public API

    /// Returns the stored correction for `rawLine`, or `nil` if none exists.
    public func correction(for rawLine: String) -> ParserCorrection? {
        corrections[normalize(rawLine)]
    }

    /// Persists a correction for `rawLine`, overwriting any previous entry.
    public func record(_ correction: ParserCorrection, for rawLine: String) {
        let key = normalize(rawLine)
        guard !key.isEmpty else { return }
        corrections[key] = correction
        save()
    }

    /// Removes the stored correction for `rawLine`.
    public func remove(for rawLine: String) {
        corrections.removeValue(forKey: normalize(rawLine))
        save()
    }

    /// Returns the total number of stored corrections.
    public var count: Int { corrections.count }

    /// Wipes all stored corrections.
    public func clearAll() {
        corrections.removeAll()
        userDefaults.removeObject(forKey: storageKey)
    }

    // MARK: - Key normalization

    /// Normalizes text for use as a dictionary key: lowercased, interior whitespace collapsed.
    /// "Chicken  Rice   8.50" → "chicken rice 8.50"
    private func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    // MARK: - Persistence

    private func load() {
        guard
            let data    = userDefaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: ParserCorrection].self, from: data)
        else { return }
        corrections = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(corrections) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
