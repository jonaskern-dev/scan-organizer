import Foundation

public struct AIComponents {
    public let date: String
    public let title: String
    public let type: String
    public let components: [[String: Any]]
    public let confidence: Double
}

public struct Classification {
    public let type: DocumentType
    public let confidence: Double
    public let vendor: String?
    public let amount: Decimal?
    public let date: Date?
    public let details: String
    public let fileName: String
    public let aiComponents: AIComponents
}

public class AIClassifier {
    private let ollamaBaseURL = "http://localhost:11434"
    private let config: AppConfig
    private var visionModel: String {
        // Use configured model, or default if empty
        let model = config.ollamaVisionModel
        return model.isEmpty ? AppConfig.defaultVisionModel.name + ":" + AppConfig.defaultVisionModel.tags.first!.tag : model
    }

    private var textModel: String {
        // Use configured model, or default if empty
        let model = config.ollamaTextModel
        return model.isEmpty ? AppConfig.defaultTextModel.name + ":" + AppConfig.defaultTextModel.tags.first!.tag : model
    }

    public init() {
        self.config = AppConfig.shared
        print("[AIClassifier] Initialized with AppConfig.shared")
        print("[AIClassifier] Vision prompt (first 100): \(String(config.visionPrompt.prefix(100)))")
        print("[AIClassifier] Text prompt (first 100): \(String(config.textPrompt.prefix(100)))")
    }

    public func classify(text: String, image: Data, fileName: String) async throws -> Classification {
        // Get file creation date as fallback
        let fileDate = getFileDate(fileName: fileName)

        // Step 1: Vision AI analysis (Python-compatible)
        let visionResult = try await callVisionAI(image: image, text: text)

        // Extract language from vision response
        let language = extractLanguage(from: visionResult)

        // Step 2: Text AI for structured data extraction (Python-compatible)
        let textResult = try await callTextAI(
            visionDescription: visionResult,
            text: text,
            fileDate: fileDate,
            language: language
        )

        // Parse AI components
        let aiComponents = try parseAIComponents(textResult, fileDate: fileDate)

        // Build filename from components (Python-compatible)
        let generatedFileName = buildFileName(from: aiComponents) + ".pdf"

        // Convert to Classification
        return createClassification(
            from: aiComponents,
            fileName: generatedFileName
        )
    }

    private func callVisionAI(image: Data, text: String) async throws -> String {
        // Use configured vision model
        let model = visionModel

        let base64Image = image.base64EncodedString()
        let textExcerpt = String(text.prefix(800))

        // Use configurable prompt with placeholders
        let visionPrompt = AppConfig.replacePromptPlaceholders(config.visionPrompt, with: [
            "TEXT_EXCERPT": textExcerpt
        ])

        print("=" + String(repeating: "=", count: 59))
        print("OLLAMA VISION ANALYSIS (\(model))")
        print("=" + String(repeating: "=", count: 59))
        print("Using Vision Prompt (first 200 chars):")
        print(String(visionPrompt.prefix(200)))
        print("=" + String(repeating: "=", count: 59))

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

        let response = try await performOllamaRequest(endpoint: "/api/generate", body: requestBody)

        guard let responseText = response["response"] as? String else {
            throw AIError.invalidResponse
        }

        print("Vision AI Response:")
        print(responseText)
        print("=" + String(repeating: "=", count: 59))

        return responseText
    }

    private func callTextAI(visionDescription: String, text: String, fileDate: String, language: String) async throws -> String {
        let textExcerpt = String(text.prefix(1500))

        // Use configurable prompt with placeholders
        let textPrompt = AppConfig.replacePromptPlaceholders(config.textPrompt, with: [
            "VISION_DESCRIPTION": visionDescription,
            "TEXT_EXCERPT": textExcerpt,
            "FILE_DATE": fileDate,
            "LANGUAGE": language
        ])

        print("=" + String(repeating: "=", count: 59))
        print("TEXT AI FILENAME GENERATION")
        print("=" + String(repeating: "=", count: 59))
        print("Using Text Prompt (first 200 chars):")
        print(String(textPrompt.prefix(200)))
        print("=" + String(repeating: "=", count: 59))

        let requestBody: [String: Any] = [
            "model": textModel,
            "prompt": textPrompt,
            "stream": false,
            "options": [
                "temperature": 0.1,
                "num_predict": 300
            ]
        ]

        let response = try await performOllamaRequest(endpoint: "/api/generate", body: requestBody)

        guard let responseText = response["response"] as? String else {
            throw AIError.invalidResponse
        }

        print("Text AI Response:")
        print(responseText)
        print("=" + String(repeating: "=", count: 59))

        return responseText
    }

    private func parseAIComponents(_ jsonString: String, fileDate: String) throws -> AIComponents {
        print("=" + String(repeating: "=", count: 59))
        print("PARSING AI RESPONSE")
        print("=" + String(repeating: "=", count: 59))
        print("Raw response: \(jsonString)")

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
            print("ERROR: Failed to parse JSON, using fallback")
            // Fallback if JSON parsing fails
            return AIComponents(
                date: fileDate,
                title: "Dokument",
                type: "unknown",
                components: [],
                confidence: 0.5
            )
        }

        print("Parsed JSON: \(json)")

        let date = json["date"] as? String ?? fileDate
        let title = json["title"] as? String ?? ""
        let type = json["type"] as? String ?? "unknown"
        let components = json["components"] as? [[String: Any]] ?? []
        let confidence = json["confidence"] as? Double ?? 0.85

        print("Extracted type: \(type)")
        print("=" + String(repeating: "=", count: 59))

        return AIComponents(
            date: date,
            title: title,
            type: type,
            components: components,
            confidence: confidence
        )
    }

    internal func buildFileName(from components: AIComponents) -> String {
        let config = AppConfig.shared
        var filenameParts: [String] = []

        // 1. Date (if enabled)
        if config.filenameIncludeDate {
            let dateStr: String
            if isValidDate(components.date) {
                dateStr = components.date
            } else {
                dateStr = getFileDate(fileName: "")
            }

            // Format date according to config
            let formattedDate = formatDate(dateStr, format: config.filenameDateFormat)
            filenameParts.append(formattedDate)
        }

        // 2. Title (cleaned and formatted)
        if !components.title.isEmpty &&
           !["keine angabe", "keine", "n/a", "unbekannt", "unknown"].contains(components.title.lowercased()) {
            let titleClean = cleanForFilename(components.title, maxLength: 50, separator: config.filenameInternalSeparator)
            if !titleClean.isEmpty {
                filenameParts.append(titleClean)
            }
        }

        // 3. Process components (if enabled)
        if config.filenameIncludeComponents {
            var componentCount = 0
            for comp in components.components.prefix(5) {
                if componentCount >= 3 { break }

                let confidence = comp["confidence"] as? Double ?? 0.5
                if confidence < 0.6 { continue }

                guard let value = comp["value"] else { continue }
                let compStr = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)

                if compStr.isEmpty { continue }

                // Check for amounts
                if let eurStr = extractAmount(from: compStr, separator: config.filenameInternalSeparator) {
                    filenameParts.append(eurStr)
                    componentCount += 1
                } else {
                    // Regular component
                    let compClean = cleanForFilename(compStr, maxLength: 30, separator: config.filenameInternalSeparator)
                    if !compClean.isEmpty && compClean.count > 1 {
                        filenameParts.append(compClean)
                        componentCount += 1
                    }
                }
            }
        }

        // Join filename parts with configured separator
        var filename = filenameParts.joined(separator: config.filenamePartSeparator)

        // Replace German umlauts
        filename = replaceUmlauts(in: filename)

        // Final cleanup with configured separators
        let doublePart = config.filenamePartSeparator + config.filenamePartSeparator
        let doubleInternal = config.filenameInternalSeparator + config.filenameInternalSeparator
        filename = filename.replacingOccurrences(of: doublePart, with: config.filenamePartSeparator)
        filename = filename.replacingOccurrences(of: doubleInternal, with: config.filenameInternalSeparator)

        return filename.isEmpty ? "document" : filename
    }

    private func formatDate(_ dateStr: String, format: String) -> String {
        // Parse the date string (assumed to be in YYYY-MM-DD format)
        let components = dateStr.split(separator: "-").map(String.init)
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]) else {
            return dateStr
        }

        // Replace format placeholders
        var result = format
        result = result.replacingOccurrences(of: "YYYY", with: String(format: "%04d", year))
        result = result.replacingOccurrences(of: "MM", with: String(format: "%02d", month))
        result = result.replacingOccurrences(of: "DD", with: String(format: "%02d", day))

        return result
    }

    private func cleanForFilename(_ text: String, maxLength: Int, separator: String = "-") -> String {
        // Remove special characters and normalize spaces
        var cleaned = text.replacingOccurrences(of: #"\s+"#, with: separator, options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"[^\w\säöüßÄÖÜ-]"#, with: "", options: .regularExpression)

        // Truncate to max length
        if cleaned.count > maxLength {
            cleaned = String(cleaned.prefix(maxLength))
        }

        return cleaned
    }

    private func extractAmount(from text: String, separator: String = "-") -> String? {
        // Check for EUR amounts
        if text.uppercased().contains("EUR") || text.contains("€") {
            if let match = text.range(of: #"\d+[.,]?\d*"#, options: .regularExpression) {
                let amountStr = String(text[match]).replacingOccurrences(of: ",", with: ".")
                if let amount = Double(amountStr), amount >= 10 {
                    return "EUR\(Int(amount * 100))"
                }
            }
        }

        // Check for plain numbers
        if let amount = Double(text.replacingOccurrences(of: ",", with: ".")), amount >= 10 {
            return "EUR\(Int(amount * 100))"
        }

        return nil
    }

    private func replaceUmlauts(in text: String) -> String {
        let umlautMap = [
            "ä": "ae", "Ä": "Ae",
            "ö": "oe", "Ö": "Oe",
            "ü": "ue", "Ü": "Ue",
            "ß": "ss"
        ]

        var result = text
        for (umlaut, replacement) in umlautMap {
            result = result.replacingOccurrences(of: umlaut, with: replacement)
        }
        return result
    }

    private func isValidDate(_ dateStr: String) -> Bool {
        return dateStr.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    internal func createClassification(from components: AIComponents, fileName: String) -> Classification {
        // Use the type directly from AI, try to match with enum
        let docType = DocumentType(rawValue: components.type.lowercased()) ?? .unknown

        // Extract vendor from components (not from title!)
        var vendor: String?
        for comp in components.components {
            if let label = comp["label"] as? String,
               let value = comp["value"] as? String {
                if label.lowercased().contains("vendor") ||
                   label.lowercased().contains("company") ||
                   label.lowercased().contains("from") {
                    vendor = value
                    break
                }
            }
        }

        // Extract amount from components
        var amount: Decimal?
        for comp in components.components {
            if let value = comp["value"] as? String,
               let extractedAmount = extractAmount(from: value) {
                if extractedAmount.hasPrefix("EUR") {
                    let cents = String(extractedAmount.dropFirst(3))
                    if let centsInt = Int(cents) {
                        amount = Decimal(centsInt) / 100
                    }
                }
            }
        }

        // Parse date
        var date: Date?
        if isValidDate(components.date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            date = formatter.date(from: components.date)
        }

        return Classification(
            type: docType,
            confidence: components.confidence,
            vendor: vendor,
            amount: amount,
            date: date,
            details: "AI Analysis Complete",
            fileName: fileName,
            aiComponents: components
        )
    }

    // Removed: findAvailableVisionModel() - now using configured model directly

    internal func performOllamaRequest(endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: ollamaBaseURL + endpoint) else {
            throw AIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 180  // 3 minutes for large images with vision models

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AIError.httpError(httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidJSON
        }

        return json
    }

    internal func extractLanguage(from visionResponse: String) -> String {
        let upperResponse = visionResponse.uppercased()
        for lang in ["GERMAN", "ENGLISH", "FRENCH", "SPANISH", "ITALIAN"] {
            if upperResponse.contains("LANGUAGE: \(lang)") || upperResponse.contains(lang) {
                return lang
            }
        }
        return "UNKNOWN"
    }

    internal func getFileDate(fileName: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

public enum AIError: LocalizedError {
    case noVisionModelAvailable
    case invalidURL
    case invalidResponse
    case invalidJSON
    case httpError(Int)

    public var errorDescription: String? {
        switch self {
        case .noVisionModelAvailable:
            return "No vision model available in Ollama"
        case .invalidURL:
            return "Invalid Ollama URL"
        case .invalidResponse:
            return "Invalid response from Ollama"
        case .invalidJSON:
            return "Invalid JSON in response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}