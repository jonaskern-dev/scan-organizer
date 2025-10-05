import Foundation

/// Centralized debug logging system with category-based filtering
public enum DebugLogger {

    public enum Category: String {
        case resourceMonitor = "ResourceMonitor"
        case pdfProcessor = "PDFProcessor"
        case aiClassifier = "AIClassifier"
        case ocrService = "OCRService"
        case fileOrganizer = "FileOrganizer"
        case notificationService = "NotificationService"
        case general = "General"
    }

    /// Log a debug message if the category is enabled
    public static func log(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        let config = AppConfig.shared

        // Check if debug is globally enabled
        guard config.debugEnabled else { return }

        // Check if specific category is enabled
        let categoryEnabled: Bool
        switch category {
        case .resourceMonitor:
            categoryEnabled = config.debugResourceMonitor
        case .pdfProcessor:
            categoryEnabled = config.debugPDFProcessor
        case .aiClassifier:
            categoryEnabled = config.debugAIClassifier
        case .ocrService:
            categoryEnabled = config.debugOCRService
        case .fileOrganizer:
            categoryEnabled = config.debugFileOrganizer
        case .notificationService:
            categoryEnabled = config.debugNotificationService
        case .general:
            categoryEnabled = true
        }

        guard categoryEnabled else { return }

        // Format: [Category] message
        print("[\(category.rawValue)] \(message)")
    }

    /// Log with additional context (file, function, line)
    public static func debug(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        let config = AppConfig.shared
        guard config.debugEnabled else { return }

        let categoryEnabled: Bool
        switch category {
        case .resourceMonitor:
            categoryEnabled = config.debugResourceMonitor
        case .pdfProcessor:
            categoryEnabled = config.debugPDFProcessor
        case .aiClassifier:
            categoryEnabled = config.debugAIClassifier
        case .ocrService:
            categoryEnabled = config.debugOCRService
        case .fileOrganizer:
            categoryEnabled = config.debugFileOrganizer
        case .notificationService:
            categoryEnabled = config.debugNotificationService
        case .general:
            categoryEnabled = true
        }

        guard categoryEnabled else { return }

        let fileName = (file as NSString).lastPathComponent
        print("[\(category.rawValue)] [\(fileName):\(line)] \(function) - \(message)")
    }

    /// Log an error (always shown if debug enabled, regardless of category)
    public static func error(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        let config = AppConfig.shared
        guard config.debugEnabled else { return }

        let fileName = (file as NSString).lastPathComponent
        print("[\(category.rawValue)] ERROR [\(fileName):\(line)] \(function) - \(message)")
    }

    /// Log a warning (always shown if debug enabled, regardless of category)
    public static func warning(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        let config = AppConfig.shared
        guard config.debugEnabled else { return }

        let fileName = (file as NSString).lastPathComponent
        print("[\(category.rawValue)] WARNING [\(fileName):\(line)] \(function) - \(message)")
    }
}
