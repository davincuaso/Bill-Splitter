import SwiftUI
import UIKit

/// Top-level sheet that manages the full receipt-scanning flow.
///
/// Phases displayed:
///   1. Source selection  — camera / photo library buttons
///   2. Scanning          — spinner while Vision + parser run
///   3. Review            — `ScanReviewView` for editing parsed output
///   4. Failed            — error message with retry
///
/// After the user taps "Import" on the review screen, `onImport` is called
/// with the finalized items, charges, and detected currency code (may be nil),
/// then the sheet dismisses itself.
struct ReceiptScannerSheet: View {
    let onImport: ([BillItem], Charges, String?) -> Void

    @StateObject private var vm = ReceiptScannerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch vm.phase {
                case .source:              sourceView
                case .scanning:            scanningView
                case .review:              reviewView
                case .failed(let msg):     errorView(msg)
                }
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // Present the image picker as a full-screen cover so it overlays the sheet cleanly.
        .fullScreenCover(isPresented: $vm.showImagePicker) {
            ImagePickerView(sourceType: vm.imageSourceType) { image in
                Task { await vm.handleSelectedImage(image) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Source selection

    private var sourceView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(.indigo)
                Text("Scan a Receipt")
                    .font(.title2.bold())
                Text("Point your camera at a receipt or choose a photo. SplitSmart will extract items and taxes automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 40)

            Divider()

            List {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        vm.selectSource(.camera)
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .font(.body.weight(.medium))
                    }
                }

                Button {
                    vm.selectSource(.photoLibrary)
                } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .font(.body.weight(.medium))
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxHeight: 200)

            Spacer()

            Text("For best results: good lighting, receipt flat on a surface.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Scanning indicator

    private var scanningView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.indigo)
            Text("Reading receipt…")
                .font(.headline)
            Text("This usually takes a few seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Review

    @ViewBuilder
    private var reviewView: some View {
        if let receipt = vm.parsedReceipt {
            ScanReviewView(
                parsedReceipt: receipt,
                correctionStore: vm.correctionStore
            ) { items, charges, currencyCode in
                onImport(items, charges, currencyCode)
                dismiss()
            }
        } else {
            errorView("No data was returned. Please try scanning again.")
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.title3.bold())

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                vm.retry()
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)

            Button("Enter Manually") {
                dismiss()
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ReceiptScannerSheet { _, _, _ in }
}
