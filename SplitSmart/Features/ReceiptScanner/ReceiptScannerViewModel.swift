import SwiftUI
import UIKit

/// Drives the full receipt-scanning flow:
///   source selection → image capture → OCR → parsing → user review
///
/// Owned by `ReceiptScannerSheet` as a `@StateObject`.
@MainActor
final class ReceiptScannerViewModel: ObservableObject {

    // MARK: - Phase

    enum Phase: Equatable {
        /// Waiting for the user to choose camera or photo library.
        case source
        /// Vision request is running — show a progress indicator.
        case scanning
        /// Parsing succeeded — show the review screen.
        case review
        /// Something went wrong — show an error message with a retry option.
        case failed(String)

        // Equatable conformance: failures are equal regardless of message.
        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.source, .source), (.scanning, .scanning), (.review, .review): return true
            case (.failed, .failed): return true
            default: return false
            }
        }
    }

    // MARK: - Published state

    @Published private(set) var phase: Phase = .source
    @Published private(set) var parsedReceipt: ParsedReceipt?
    @Published var showImagePicker = false
    @Published var imageSourceType: UIImagePickerController.SourceType = .camera

    // MARK: - Dependencies

    private let scanner = ReceiptScannerService()

    /// Shared correction store — also passed to `ScanReviewView` so edits are written back.
    let correctionStore = ParserCorrectionStore()

    private lazy var parser = ReceiptParser(correctionStore: correctionStore)

    // MARK: - Actions

    /// Opens the image picker for the chosen source.
    func selectSource(_ type: UIImagePickerController.SourceType) {
        imageSourceType = type
        showImagePicker = true
    }

    /// Called by `ImagePickerView` after the user picks or captures an image.
    func handleSelectedImage(_ image: UIImage) async {
        phase = .scanning
        parsedReceipt = nil

        do {
            let lines   = try await scanner.scan(image)
            let receipt = parser.parse(lines)
            parsedReceipt = receipt
            phase = .review
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Returns to the source-selection screen so the user can try again.
    func retry() {
        parsedReceipt = nil
        phase = .source
    }
}
