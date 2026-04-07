import Vision
import UIKit

// MARK: - Errors

public enum ScannerError: LocalizedError {
    case imageConversionFailed
    case noTextFound
    case recognitionFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Could not read the image. Try selecting a different photo."
        case .noTextFound:
            return "No text was detected. Make sure the receipt is well-lit and in focus."
        case .recognitionFailed(let underlying):
            return "Text recognition failed: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Service

/// Wraps `VNRecognizeTextRequest` to extract ordered text lines from a receipt image.
///
/// - Runs entirely on-device via the Vision framework.
/// - Uses `.accurate` recognition level for maximum correctness.
/// - Returns lines sorted top-to-bottom (Vision's Y-axis is flipped; corrected here).
public final class ReceiptScannerService {

    public init() {}

    /// Scans `image` and returns recognized lines in reading order (top → bottom).
    /// Throws `ScannerError` on failure.
    public func scan(_ image: UIImage) async throws -> [RecognizedLine] {
        guard let cgImage = image.cgImage else {
            throw ScannerError.imageConversionFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: ScannerError.recognitionFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(throwing: ScannerError.noTextFound)
                    return
                }

                // Vision origin is bottom-left; sort descending Y → top-to-bottom reading order.
                let sorted = observations.sorted { $0.boundingBox.minY > $1.boundingBox.minY }

                let lines: [RecognizedLine] = sorted.compactMap { obs in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    return RecognizedLine(
                        text: top.string,
                        confidence: top.confidence,
                        boundingBox: obs.boundingBox
                    )
                }

                continuation.resume(returning: lines)
            }

            // Accuracy over speed — receipt text is dense and character-level correctness matters.
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages   = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: ScannerError.recognitionFailed(error))
            }
        }
    }
}
