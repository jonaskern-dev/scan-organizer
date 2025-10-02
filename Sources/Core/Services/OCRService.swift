import Foundation
import Vision
import PDFKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

public struct RecognizedTextWithPosition {
    public let text: String
    public let boundingBox: CGRect // Normalized coordinates (0-1)
    public let confidence: Float
}

public class OCRService {
    private let recognitionLanguages = ["de-DE", "en-US"]
    private let recognitionLevel: VNRequestTextRecognitionLevel = .accurate

    public init() {}

    public func extractText(from pdfURL: URL) async throws -> String {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            throw OCRError.pdfLoadFailed
        }

        var allText = ""
        let pageCount = min(pdfDocument.pageCount, 10) // Process max 10 pages for performance

        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            let pageImage = try renderPageToImage(page)
            let pageText = try await recognizeText(in: pageImage)

            if !pageText.isEmpty {
                if !allText.isEmpty {
                    allText += "\n\n--- Page \(pageIndex + 1) ---\n\n"
                }
                allText += pageText
            }
        }

        return allText
    }

    private func renderPageToImage(_ page: PDFPage) throws -> CGImage {
        let pageRect = page.bounds(for: .mediaBox)

        // Request a high-quality size for OCR
        let maxDimension: CGFloat = 2400
        let scale = min(maxDimension / pageRect.width, maxDimension / pageRect.height)
        let requestedSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

        #if os(macOS)
        // Get thumbnail - this handles rotation correctly!
        // IMPORTANT: Accept whatever size the thumbnail method returns
        let thumbnail = page.thumbnail(of: requestedSize, for: .mediaBox)

        // Convert to CGImage - use nil for proposedRect (like Python)
        guard let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.imageConversionFailed
        }

        return cgImage
        #else
        // iOS implementation
        guard let thumbnail = page.thumbnail(of: requestedSize, for: .mediaBox) else {
            throw OCRError.imageConversionFailed
        }

        guard let cgImage = thumbnail.cgImage else {
            throw OCRError.imageConversionFailed
        }

        return cgImage
        #endif
    }

    // Extract text with position information for OCR layer
    public func extractTextWithPositions(from pdfURL: URL) async throws -> (String, [[RecognizedTextWithPosition]]) {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            throw OCRError.pdfLoadFailed
        }

        var allText = ""
        var pageTextPositions: [[RecognizedTextWithPosition]] = []
        let pageCount = min(pdfDocument.pageCount, 10) // Process max 10 pages

        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            let pageImage = try renderPageToImage(page)
            let (pageText, positions) = try await recognizeTextWithPositions(in: pageImage)

            if !pageText.isEmpty {
                if !allText.isEmpty {
                    allText += "\n\n--- Page \(pageIndex + 1) ---\n\n"
                }
                allText += pageText
            }

            pageTextPositions.append(positions)
        }

        return (allText, pageTextPositions)
    }

    private func recognizeTextWithPositions(in image: CGImage) async throws -> (String, [RecognizedTextWithPosition]) {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: ("", []))
                    return
                }

                // Build text and position data
                var lines: [String] = []
                var positions: [RecognizedTextWithPosition] = []

                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    lines.append(candidate.string)

                    // Store position data (boundingBox is in normalized coordinates 0-1)
                    positions.append(RecognizedTextWithPosition(
                        text: candidate.string,
                        boundingBox: observation.boundingBox,
                        confidence: candidate.confidence
                    ))
                }

                let text = lines.joined(separator: "\n")
                continuation.resume(returning: (text, positions))
            }

            request.recognitionLevel = recognitionLevel
            request.recognitionLanguages = recognitionLanguages
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.minimumTextHeight = 0.0

            let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try requestHandler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.requestFailed(error))
            }
        }
    }

    private func recognizeText(in image: CGImage) async throws -> String {
        let (text, _) = try await recognizeTextWithPositions(in: image)
        return text

    }
}

public enum OCRError: LocalizedError {
    case pdfLoadFailed
    case imageConversionFailed
    case recognitionFailed(Error)
    case requestFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .pdfLoadFailed:
            return "Failed to load PDF document"
        case .imageConversionFailed:
            return "Failed to convert PDF page to image"
        case .recognitionFailed(let error):
            return "Text recognition failed: \(error.localizedDescription)"
        case .requestFailed(let error):
            return "Vision request failed: \(error.localizedDescription)"
        }
    }
}