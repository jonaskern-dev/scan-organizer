import Foundation
import Vision
import PDFKit

public struct OCRComparison {
    public let recommendation: String // "use_apple", "keep_existing", "no_existing"
    public let reason: String
    public let existingScore: Double
    public let appleScore: Double
    public let selectedText: String
}

public class OCRComparisonService {

    public init() {}

    public func compareOCR(pdfURL: URL, appleVisionText: String) -> OCRComparison {
        // Extract existing OCR from PDF
        let existingText = extractExistingOCR(from: pdfURL)

        if existingText.isEmpty || existingText.count < 10 {
            return OCRComparison(
                recommendation: "use_apple",
                reason: "No existing OCR or too short",
                existingScore: 0,
                appleScore: calculateQualityScore(for: appleVisionText),
                selectedText: appleVisionText
            )
        }

        // Calculate quality scores
        let existingScore = calculateQualityScore(for: existingText)
        let appleScore = calculateQualityScore(for: appleVisionText)

        // Apple needs to be 10% better to replace existing
        if appleScore > existingScore * 1.1 {
            return OCRComparison(
                recommendation: "use_apple",
                reason: "Apple OCR is better (score: \(String(format: "%.2f", appleScore)) vs \(String(format: "%.2f", existingScore)))",
                existingScore: existingScore,
                appleScore: appleScore,
                selectedText: appleVisionText
            )
        } else {
            return OCRComparison(
                recommendation: "keep_existing",
                reason: "Existing OCR is sufficient (score: \(String(format: "%.2f", existingScore)) vs \(String(format: "%.2f", appleScore)))",
                existingScore: existingScore,
                appleScore: appleScore,
                selectedText: existingText
            )
        }
    }

    private func extractExistingOCR(from pdfURL: URL) -> String {
        guard let document = PDFDocument(url: pdfURL) else { return "" }

        var fullText = ""
        for pageIndex in 0..<min(document.pageCount, 10) { // Max 10 pages for comparison
            if let page = document.page(at: pageIndex) {
                if let pageText = page.string {
                    fullText += pageText + "\n"
                }
            }
        }

        return fullText
    }

    private func calculateQualityScore(for text: String) -> Double {
        if text.isEmpty { return 0 }

        var score: Double = 0

        // 1. Length score (up to 20 points)
        let lengthScore = min(Double(text.count) / 500.0 * 20, 20)
        score += lengthScore

        // 2. Word count score (up to 20 points)
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let wordScore = min(Double(words.count) / 100.0 * 20, 20)
        score += wordScore

        // 3. Readability score - check for proper spacing (up to 20 points)
        let avgWordLength = Double(text.replacingOccurrences(of: " ", with: "").count) / Double(max(words.count, 1))
        let readabilityScore = avgWordLength > 3 && avgWordLength < 15 ? 20 : 10
        score += Double(readabilityScore)

        // 4. Language detection score (up to 20 points)
        let hasGerman = text.range(of: #"(der|die|das|und|ist|von|mit|für|auf|den|ein|eine)"#,
                                   options: [.regularExpression, .caseInsensitive]) != nil
        let hasEnglish = text.range(of: #"(the|and|for|with|from|this|that|have|will)"#,
                                    options: [.regularExpression, .caseInsensitive]) != nil
        let languageScore = (hasGerman || hasEnglish) ? 20 : 10
        score += Double(languageScore)

        // 5. Structure score - has line breaks and paragraphs (up to 20 points)
        let lineBreaks = text.components(separatedBy: "\n").count
        let structureScore = min(Double(lineBreaks) / 10.0 * 20, 20)
        score += structureScore

        return score // Max 100
    }
}