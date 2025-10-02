import Foundation

public struct Document: Codable {
    public let id: UUID
    public let originalPath: URL
    public var processedPath: URL?
    public var documentType: DocumentType
    public var aiType: String?  // The original type from AI
    public var confidence: Double
    public var extractedText: String
    public var vendor: String?
    public var amount: Decimal?
    public var date: Date?
    public let createdAt: Date
    public var processedAt: Date?

    // Metadata is not directly codable due to Any type, handle separately
    public var metadata: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case id, originalPath, processedPath, documentType, aiType, confidence
        case extractedText, vendor, amount, date, createdAt, processedAt, metadata
    }

    public init(originalPath: URL) {
        self.id = UUID()
        self.originalPath = originalPath
        self.documentType = .unknown
        self.aiType = nil
        self.confidence = 0.0
        self.extractedText = ""
        self.vendor = nil
        self.amount = nil
        self.date = nil
        self.metadata = [:]
        self.createdAt = Date()
        self.processedAt = nil
    }
}

public enum DocumentType: String, CaseIterable, Codable {
    case invoice = "invoice"
    case receipt = "receipt"
    case contract = "contract"
    case letter = "letter"
    case report = "report"
    case statement = "statement"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .invoice: return "Invoice"
        case .receipt: return "Receipt"
        case .contract: return "Contract"
        case .letter: return "Letter"
        case .report: return "Report"
        case .statement: return "Statement"
        case .unknown: return "Unknown"
        }
    }
}

public struct ProcessingResult: Codable {
    public let success: Bool
    public let document: Document?
    public let errorDescription: String?
    public let processingTime: TimeInterval

    public init(success: Bool, document: Document? = nil, error: Error? = nil, processingTime: TimeInterval = 0) {
        self.success = success
        self.document = document
        self.errorDescription = error?.localizedDescription
        self.processingTime = processingTime
    }

    public var error: Error? {
        return nil // Error is not reconstructible from string, only for display
    }
}