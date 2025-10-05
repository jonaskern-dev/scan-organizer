import Foundation
import Vision
import PDFKit
import CoreGraphics
import CoreText
#if os(iOS)
import UIKit
#else
import AppKit
#endif

public protocol ProcessingDelegate: AnyObject {
    func updateStatus(_ message: String, progress: Double)
    func addLogEntry(_ message: String)
    func setTempImage(_ url: URL?)
}

public class PDFProcessor {
    private let ocrService: OCRService
    private let ocrComparison: OCRComparisonService
    private let aiClassifier: AIClassifier
    private let fileOrganizer: FileOrganizer
    private let notificationService = NotificationService.shared

    public weak var delegate: ProcessingDelegate?

    public init() {
        self.ocrService = OCRService()
        self.ocrComparison = OCRComparisonService()
        self.aiClassifier = AIClassifier()
        self.fileOrganizer = FileOrganizer()
    }

    public func process(pdfURL: URL) async throws -> ProcessingResult {
        let startTime = Date()

        DebugLogger.log("Starting PDF processing: \(pdfURL.lastPathComponent)", category: .pdfProcessor)

        // Validate PDF
        guard pdfURL.pathExtension.lowercased() == "pdf" else {
            DebugLogger.error("Invalid file type: \(pdfURL.pathExtension)", category: .pdfProcessor)
            throw ProcessingError.invalidFileType
        }

        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            DebugLogger.error("File not found: \(pdfURL.path)", category: .pdfProcessor)
            throw ProcessingError.fileNotFound
        }

        delegate?.updateStatus("Initializing...", progress: 0.05)
        delegate?.addLogEntry("=== PDF PROCESSING STARTED ===")
        delegate?.addLogEntry("File: \(pdfURL.lastPathComponent)")
        delegate?.addLogEntry("Size: \(getFileSize(url: pdfURL))")

        DebugLogger.debug("PDF validated, size: \(getFileSize(url: pdfURL))", category: .pdfProcessor)

        // Create document
        var document = Document(originalPath: pdfURL)

        // Step 1: Extract text using Vision framework
        delegate?.updateStatus("Extracting text with Apple Vision...", progress: 0.15)
        delegate?.addLogEntry("\n--- STEP 1: OCR WITH APPLE VISION ---")

        let appleVisionText = try await ocrService.extractText(from: pdfURL)
        delegate?.addLogEntry("Apple Vision OCR: \(appleVisionText.count) characters extracted")
        // Send full OCR text in a special format for temp storage
        delegate?.addLogEntry("[OCR_TEXT_START]\(appleVisionText)[OCR_TEXT_END]")
        delegate?.addLogEntry("First 200 characters: \(String(appleVisionText.prefix(200)))...")

        // Step 2: Compare with existing OCR and select best
        delegate?.updateStatus("Comparing OCR quality...", progress: 0.25)
        delegate?.addLogEntry("\n--- STEP 2: OCR COMPARISON ---")

        let ocrComparison = ocrComparison.compareOCR(pdfURL: pdfURL, appleVisionText: appleVisionText)
        let extractedText = ocrComparison.selectedText

        delegate?.addLogEntry("Existing OCR Score: \(String(format: "%.1f", ocrComparison.existingScore))")
        delegate?.addLogEntry("Apple Vision Score: \(String(format: "%.1f", ocrComparison.appleScore))")
        delegate?.addLogEntry("Decision: \(ocrComparison.recommendation) - \(ocrComparison.reason)")
        delegate?.addLogEntry("Selected text: \(extractedText.count) characters")
        // Send selected text for temp storage
        if extractedText != appleVisionText {
            delegate?.addLogEntry("[OCR_TEXT_START]\(extractedText)[OCR_TEXT_END]")
        }

        document.extractedText = extractedText

        // Step 3: Extract first page as image for AI vision analysis
        delegate?.updateStatus("Converting PDF to image...", progress: 0.35)
        delegate?.addLogEntry("\n--- STEP 3: PDF TO IMAGE CONVERSION ---")

        let pageImage = try extractFirstPageImage(from: pdfURL)

        // Save temp image for preview FIRST
        let tempImageURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scan_preview_\(pdfURL.lastPathComponent)_\(UUID().uuidString).png")
        try pageImage.write(to: tempImageURL)
        delegate?.setTempImage(tempImageURL)

        // THEN log it (so the image is already set)
        delegate?.addLogEntry("First page converted: \(pageImage.count / 1024) KB PNG")

        // Step 4: Vision AI Analysis
        delegate?.updateStatus("Starting Vision AI analysis...", progress: 0.45)
        delegate?.addLogEntry("\n--- STEP 4: VISION AI ANALYSIS ---")

        // Create custom classifier that logs
        let loggingClassifier = LoggingAIClassifier(delegate: delegate)

        // This will internally handle Vision AI
        _ = try await loggingClassifier.callVisionAI(
            image: pageImage,
            text: extractedText
        )

        // Step 5: Text AI Analysis
        delegate?.updateStatus("Processing with Text AI...", progress: 0.55)
        delegate?.addLogEntry("\n--- STEP 5: TEXT AI ANALYSIS ---")

        // This will internally handle Text AI
        let classification = try await loggingClassifier.classify(
            text: extractedText,
            image: pageImage,
            fileName: pdfURL.lastPathComponent
        )

        document.documentType = classification.type
        document.aiType = classification.aiComponents.type  // Store original AI type
        document.confidence = classification.confidence
        document.vendor = classification.vendor
        document.amount = classification.amount
        document.date = classification.date

        // Step 6: Generate filename first
        delegate?.updateStatus("Generating filename...", progress: 0.70)
        delegate?.addLogEntry("\n--- STEP 6: GENERATE FILENAME ---")

        let newFileName = classification.fileName
        delegate?.addLogEntry("Generated filename: \(newFileName)")

        // Step 7: Determine target location
        delegate?.updateStatus("Determining target location...", progress: 0.75)
        delegate?.addLogEntry("\n--- STEP 7: DETERMINE TARGET LOCATION ---")

        let targetURL = try fileOrganizer.getTargetURL(
            from: pdfURL,
            for: newFileName,
            type: document.documentType
        )
        delegate?.addLogEntry("Target location: \(targetURL.path)")

        // Step 8: Create searchable PDF directly at target location
        delegate?.updateStatus("Creating searchable PDF...", progress: 0.80)
        delegate?.addLogEntry("\n--- STEP 8: CREATE SEARCHABLE PDF AT TARGET ---")

        delegate?.addLogEntry("Creating new PDF with OCR layer at target location...")
        try await createSearchablePDF(
            originalPDF: pdfURL,
            ocrText: extractedText,
            outputURL: targetURL
        )
        delegate?.addLogEntry("Searchable PDF created successfully at: \(targetURL.lastPathComponent)")

        // Delete original file if different from target
        if pdfURL.path != targetURL.path {
            try? FileManager.default.removeItem(at: pdfURL)
            delegate?.addLogEntry("Original file removed")
        }

        document.processedPath = targetURL
        document.processedAt = Date()

        let processingTime = Date().timeIntervalSince(startTime)

        delegate?.updateStatus("Completed", progress: 1.0)
        delegate?.addLogEntry("\n=== PROCESSING COMPLETED ===")
        delegate?.addLogEntry("New file: \(targetURL.lastPathComponent)")
        // Use aiType if documentType is Unknown
        let displayType = document.documentType == .unknown && document.aiType != nil && !document.aiType!.isEmpty ? document.aiType! : document.documentType.displayName
        delegate?.addLogEntry("Document type: \(displayType)")
        delegate?.addLogEntry("Confidence: \(String(format: "%.1f%%", document.confidence * 100))")
        delegate?.addLogEntry("Processing time: \(String(format: "%.1f", processingTime)) seconds")

        // Send completion notification
        notificationService.sendCompletionReminder(for: document)

        return ProcessingResult(
            success: true,
            document: document,
            processingTime: processingTime
        )
    }

    private func getFileSize(url: URL) -> String {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: fileSize)
        }
        return "unknown"
    }

    private func extractFirstPageImage(from pdfURL: URL) throws -> Data {
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let firstPage = pdfDocument.page(at: 0) else {
            throw ProcessingError.pdfReadError
        }

        let bounds = firstPage.bounds(for: .mediaBox)
        let scale: CGFloat = 1.5 // Good quality, smaller file size for AI processing
        let requestedSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )

        #if os(iOS)
        // Use thumbnail method - handles rotation correctly!
        guard let thumbnail = firstPage.thumbnail(of: requestedSize, for: .mediaBox) else {
            throw ProcessingError.imageConversionError
        }

        guard let pngData = thumbnail.pngData() else {
            throw ProcessingError.imageConversionError
        }
        #else
        // Use thumbnail method - handles rotation correctly!
        // IMPORTANT: Accept whatever size the thumbnail method returns
        let thumbnail = firstPage.thumbnail(of: requestedSize, for: .mediaBox)

        // Convert to PNG data
        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw ProcessingError.imageConversionError
        }
        #endif

        return pngData
    }

    private func createSearchablePDF(originalPDF: URL, ocrText: String, outputURL: URL) async throws {
        guard let pdfDocument = PDFDocument(url: originalPDF) else {
            throw ProcessingError.pdfReadError
        }

        delegate?.addLogEntry("Creating clean PDF from page images with Core Graphics...")

        // Use OCRService to get text with position information for all pages
        let ocrService = OCRService()
        let (_, pageTextPositions) = try await ocrService.extractTextWithPositions(from: originalPDF)

        // Create PDF with Core Graphics for proper text layer directly at target
        try createPDFWithTextLayer(
            from: pdfDocument,
            textPositions: pageTextPositions,
            outputURL: outputURL
        )
    }

    private func createPDFWithTextLayer(from originalDocument: PDFDocument, textPositions: [[RecognizedTextWithPosition]], outputURL: URL) throws {
        // Create new PDF document
        let newPDF = PDFDocument()

        for pageIndex in 0..<originalDocument.pageCount {
            guard let page = originalDocument.page(at: pageIndex) else { continue }

            delegate?.addLogEntry("Processing page \(pageIndex + 1)/\(originalDocument.pageCount)...")

            // Get thumbnail image
            let thumbnail = page.thumbnail(of: CGSize(width: 2400, height: 2400), for: .mediaBox)

            // Create new PDF page from image
            if let newPage = PDFPage(image: thumbnail) {
                newPDF.insert(newPage, at: pageIndex)

                // Check if page already has OCR text from system
                if let existingText = newPage.string, !existingText.isEmpty {
                    delegate?.addLogEntry("Page already contains searchable text (\(existingText.count) characters)")
                } else {
                    delegate?.addLogEntry("No automatic OCR text found in page")
                }

                // TODO: Add our OCR text if needed
                // Currently PDFPage(image:) might add OCR automatically on macOS
            }
        }

        // Write PDF to file
        if !newPDF.write(to: outputURL) {
            throw ProcessingError.pdfCreationError
        }

        delegate?.addLogEntry("PDF created successfully")
    }

    private func renderPageAsHighQualityImage(page: PDFPage, bounds: CGRect) -> NSImage? {
        let scale: CGFloat = 2.0 // High quality for final PDF rendering
        let requestedSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )

        // Use thumbnail method - handles rotation correctly!
        // IMPORTANT: Accept whatever size the thumbnail method returns
        return page.thumbnail(of: requestedSize, for: .mediaBox)
    }

    private func drawInvisibleTextLayer(context: CGContext, positions: [RecognizedTextWithPosition], pageBounds: CGRect, rotation: Int) {
        // Set text rendering mode to invisible (mode 3 = neither fill nor stroke)
        context.setTextDrawingMode(.invisible)

        for position in positions {
            // The OCR coordinates are from the rotated/displayed version
            // Since we're creating the PDF from the thumbnail (already rotated),
            // we can use the coordinates directly

            // Convert normalized coordinates (0-1) to page coordinates
            let textRect = CGRect(
                x: pageBounds.minX + position.boundingBox.minX * pageBounds.width,
                y: pageBounds.minY + position.boundingBox.minY * pageBounds.height,
                width: position.boundingBox.width * pageBounds.width,
                height: position.boundingBox.height * pageBounds.height
            )

            // Calculate appropriate font size based on bounding box
            let fontSize = textRect.height * 0.8

            // Draw invisible text at the correct position
            context.saveGState()

            // Create attributed string with proper font
            let font = NSFont.systemFont(ofSize: fontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.clear // Invisible color
            ]

            let attributedString = NSAttributedString(string: position.text, attributes: attributes)

            // Draw the text at the correct position
            // Note: Core Text works with flipped coordinates
            context.textMatrix = CGAffineTransform.identity
            context.translateBy(x: textRect.minX, y: pageBounds.height - textRect.maxY)

            // Create Core Text line and draw it
            let line = CTLineCreateWithAttributedString(attributedString)
            CTLineDraw(line, context)

            context.restoreGState()
        }

        delegate?.addLogEntry("Added \(positions.count) invisible text regions using Core Graphics")
    }
}

// Custom AI Classifier with detailed logging
class LoggingAIClassifier: AIClassifier {
    private weak var delegate: ProcessingDelegate?

    init(delegate: ProcessingDelegate?) {
        self.delegate = delegate
        super.init()
    }

    override func classify(text: String, image: Data, fileName: String) async throws -> Classification {
        // Get file creation date as fallback
        let fileDate = getFileDate(fileName: fileName)

        delegate?.addLogEntry("\n>> Vision AI Analysis...")

        // Save temp image for preview in logging classifier
        let tempImageURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scan_vision_\(UUID().uuidString).png")
        try? image.write(to: tempImageURL)
        delegate?.setTempImage(tempImageURL)

        // Step 1: Vision AI analysis
        let visionResult = try await callVisionAI(image: image, text: text)

        // Extract language from vision response
        let language = extractLanguage(from: visionResult)
        delegate?.addLogEntry("Detected language: \(language)")

        delegate?.addLogEntry("\n>> Text AI Processing...")

        // Step 2: Text AI for structured data extraction
        let textResult = try await callTextAIWithLogging(
            visionDescription: visionResult,
            text: text,
            fileDate: fileDate,
            language: language
        )

        // Parse AI components
        let aiComponents = try parseAIComponentsWithLogging(textResult, fileDate: fileDate)

        // Build filename from components
        let generatedFileName = buildFileName(from: aiComponents) + ".pdf"

        delegate?.addLogEntry("\n>> Final Results:")
        delegate?.addLogEntry("AI detected type: '\(aiComponents.type)'")
        delegate?.addLogEntry("Title: \(aiComponents.title)")
        delegate?.addLogEntry("Date: \(aiComponents.date)")
        delegate?.addLogEntry("Filename: \(generatedFileName)")

        // Convert to Classification
        return createClassification(
            from: aiComponents,
            fileName: generatedFileName
        )
    }

    func callVisionAI(image: Data, text: String) async throws -> String {
        // Use configured vision model
        let model = AppConfig.shared.ollamaVisionModel

        delegate?.addLogEntry("Using vision model: \(model)")

        let base64Image = image.base64EncodedString()
        let textExcerpt = String(text.prefix(800))

        // Exact prompt from Python
        let visionPrompt = """
        Analyze this document image.

        OCR text excerpt:
        \(textExcerpt)

        Provide:
        1. First state: LANGUAGE: GERMAN or LANGUAGE: ENGLISH etc.
        2. Document type
        3. Main title/heading from document
        4. Primary purpose

        Start your response with the language.
        """

        delegate?.addLogEntry("\nVision AI Prompt:")
        delegate?.addLogEntry("[PROMPT_START]\(visionPrompt)[PROMPT_END]")

        let requestBody: [String: Any] = [
            "model": model,
            "prompt": visionPrompt,
            "images": [base64Image],
            "stream": false,
            "options": [
                "num_predict": 300,
                "temperature": 0.3,
                "top_p": 0.9
            ]
        ]

        // Log full JSON request (without image data)
        var requestForLog = requestBody
        requestForLog["images"] = ["[BASE64_IMAGE_DATA_\(base64Image.count)_BYTES]"]

        if let jsonData = try? JSONSerialization.data(withJSONObject: requestForLog, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            delegate?.addLogEntry("\nVision AI Request JSON:")
            // Send JSON as single block for proper collection
            delegate?.addLogEntry(jsonString)
        }

        delegate?.addLogEntry("Sending request to Ollama Vision AI...")
        let startTime = Date()

        let response = try await performOllamaRequest(endpoint: "/api/generate", body: requestBody)

        let duration = Date().timeIntervalSince(startTime)
        delegate?.addLogEntry("Vision AI response time: \(String(format: "%.1f", duration)) seconds")

        guard let responseText = response["response"] as? String else {
            throw AIError.invalidResponse
        }

        delegate?.addLogEntry("\nVision AI Response:")
        delegate?.addLogEntry(responseText)

        return responseText
    }

    private func callTextAIWithLogging(visionDescription: String, text: String, fileDate: String, language: String) async throws -> String {
        let textExcerpt = String(text.prefix(1500))

        // Exact prompt from Python
        let textPrompt = """
        Analyze document and extract key components.

        Vision AI description:
        \(visionDescription)

        OCR text:
        \(textExcerpt)

        File creation date (fallback): \(fileDate)

        Date rules:
        - If you find "Schuljahr 2024/25" or similar: use "2024-09-01"
        - If you find full date: use it
        - If you find month/year: use first day
        - If you find year only: use YYYY-01-01
        - If no date found: use \(fileDate)

        DOCUMENT LANGUAGE: \(language)

        Return JSON with these fields:
        - date: document date in YYYY-MM-DD format (following rules above)
        - title: main description IN \(language) LANGUAGE - MUST BE NORMALIZED
        - type: document category in English (single word)
        - components: array with max 3 important identifiers FOR THE FILENAME

        CRITICAL for title field:
        - NEVER copy ALL CAPS text directly from document
        - ALWAYS normalize to standard \(language) capitalization
        - Capitalize first letter after each hyphen
        - Keep only real acronyms in uppercase

        Component structure: {"label": "field name", "value": "content", "confidence": 0.0-1.0}

        Confidence scoring:
        - 1.0: Critical for filename (vendor, invoice number, contract partner)
        - 0.8: Very useful (amounts, dates, reference numbers, class names)
        - 0.5: Somewhat useful (secondary details)
        - 0.3: Not useful for filename (repetitive details)

        IMPORTANT:
        - Labels in English
        - Values in document's language
        - No individual times or repetitive details

        Generate complete, valid JSON only:
        """

        delegate?.addLogEntry("\nText AI Prompt:")
        delegate?.addLogEntry("[PROMPT_START]\(textPrompt)[PROMPT_END]")

        let textModel = AppConfig.shared.ollamaTextModel
        let requestBody: [String: Any] = [
            "model": textModel,
            "prompt": textPrompt,
            "stream": false,
            "options": [
                "temperature": 0.1,
                "num_predict": 300
            ]
        ]

        // Log full JSON request
        if let jsonData = try? JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            delegate?.addLogEntry("\nText AI Request JSON:")
            // Send JSON as single block for proper collection
            delegate?.addLogEntry(jsonString)
        }

        delegate?.addLogEntry("Sending request to Text AI (\(textModel))...")
        let startTime = Date()

        let response = try await performOllamaRequest(endpoint: "/api/generate", body: requestBody)

        let duration = Date().timeIntervalSince(startTime)
        delegate?.addLogEntry("Text AI response time: \(String(format: "%.1f", duration)) seconds")

        guard let responseText = response["response"] as? String else {
            throw AIError.invalidResponse
        }

        delegate?.addLogEntry("\nText AI Response:")
        delegate?.addLogEntry(responseText)

        return responseText
    }

    private func parseAIComponentsWithLogging(_ jsonString: String, fileDate: String) throws -> AIComponents {
        delegate?.addLogEntry("\nParse AI JSON Response...")

        // Clean JSON response
        var cleanedJSON = jsonString

        // Remove markdown code blocks if present
        if cleanedJSON.contains("```json") {
            if let match = cleanedJSON.range(of: "```json") {
                cleanedJSON = String(cleanedJSON[match.upperBound...])
                if let endMatch = cleanedJSON.range(of: "```") {
                    cleanedJSON = String(cleanedJSON[..<endMatch.lowerBound])
                }
            }
        } else if cleanedJSON.contains("```") {
            cleanedJSON = cleanedJSON.replacingOccurrences(of: "```", with: "")
        }

        // Try to extract JSON
        if let jsonStart = cleanedJSON.firstIndex(of: "{"),
           let jsonEnd = cleanedJSON.lastIndex(of: "}") {
            cleanedJSON = String(cleanedJSON[jsonStart...jsonEnd])
        }

        guard let data = cleanedJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            delegate?.addLogEntry("ERROR: JSON parsing failed, using fallback")
            return AIComponents(
                date: fileDate,
                title: "Document",
                type: "unknown",
                components: [],
                confidence: 0.5
            )
        }

        let date = json["date"] as? String ?? fileDate
        let title = json["title"] as? String ?? ""
        let type = json["type"] as? String ?? "unknown"
        let components = json["components"] as? [[String: Any]] ?? []

        // Calculate confidence based on multiple factors
        var confidenceScore = 0.0
        var confidenceFactors = 0

        // Factor 1: Document type detection (30% weight)
        if type != "unknown" && type != "Document" {
            confidenceScore += 0.30
        } else {
            confidenceScore += 0.10
        }
        confidenceFactors += 1

        // Factor 2: Title quality (20% weight)
        if !title.isEmpty && title != "Document" && title.count > 5 {
            confidenceScore += 0.20
        } else if !title.isEmpty {
            confidenceScore += 0.10
        }
        confidenceFactors += 1

        // Factor 3: Date extraction (20% weight)
        if date != fileDate && date != "" {
            confidenceScore += 0.20  // Found specific date
        } else {
            confidenceScore += 0.05  // Using fallback date
        }
        confidenceFactors += 1

        // Factor 4: Components quality (30% weight)
        let highConfidenceComponents = components.filter { component in
            if let conf = component["confidence"] as? Double {
                return conf >= 0.8
            }
            return false
        }

        if highConfidenceComponents.count >= 2 {
            confidenceScore += 0.30
        } else if highConfidenceComponents.count == 1 {
            confidenceScore += 0.20
        } else if components.count > 0 {
            confidenceScore += 0.10
        }
        confidenceFactors += 1

        let calculatedConfidence = min(confidenceScore, 1.0)

        delegate?.addLogEntry("Extracted data from JSON:")
        delegate?.addLogEntry("- Type: \(type)")
        delegate?.addLogEntry("- Title: \(title)")
        delegate?.addLogEntry("- Date: \(date)")
        delegate?.addLogEntry("- Components: \(components.count) items")
        delegate?.addLogEntry("- Calculated confidence: \(String(format: "%.1f%%", calculatedConfidence * 100))")

        return AIComponents(
            date: date,
            title: title,
            type: type,
            components: components,
            confidence: calculatedConfidence
        )
    }
}

public enum ProcessingError: LocalizedError {
    case invalidFileType
    case fileNotFound
    case pdfReadError
    case imageConversionError
    case ocrFailed
    case classificationFailed
    case pdfCreationError

    public var errorDescription: String? {
        switch self {
        case .invalidFileType:
            return "Invalid file type. Only PDF files are supported."
        case .fileNotFound:
            return "File not found."
        case .pdfReadError:
            return "Failed to read PDF file."
        case .imageConversionError:
            return "Failed to convert PDF page to image."
        case .ocrFailed:
            return "OCR text extraction failed."
        case .classificationFailed:
            return "Document classification failed."
        case .pdfCreationError:
            return "Failed to create PDF document."
        }
    }
}