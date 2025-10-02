import Foundation
#if os(macOS)
import AppKit
#endif

public class FileOrganizer {
    private let baseDirectory: URL
    private let createSubfolders: Bool

    public init() {
        // No default directory - files stay in their original location
        self.baseDirectory = URL(fileURLWithPath: "")
        self.createSubfolders = false
    }

    public init(baseDirectory: URL, createSubfolders: Bool = true) {
        self.baseDirectory = baseDirectory
        self.createSubfolders = createSubfolders

        // Create base directory if needed
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    public func getTargetURL(from sourceDocument: URL, for newName: String, type: DocumentType) throws -> URL {
        // Keep file in same directory as original
        let targetDirectory = sourceDocument.deletingLastPathComponent()

        // Determine target file path
        var targetURL = targetDirectory.appendingPathComponent(newName)

        // If the new name is the same as original, return different name
        if targetURL.path == sourceDocument.path {
            let nameWithoutExtension = (newName as NSString).deletingPathExtension
            let fileExtension = (newName as NSString).pathExtension
            targetURL = targetDirectory.appendingPathComponent("\(nameWithoutExtension)_processed.\(fileExtension)")
        }

        // Handle duplicates
        var counter = 1
        while FileManager.default.fileExists(atPath: targetURL.path) {
            let nameWithoutExtension = (newName as NSString).deletingPathExtension
            let fileExtension = (newName as NSString).pathExtension
            let newNameWithCounter = "\(nameWithoutExtension)_\(counter).\(fileExtension)"
            targetURL = targetDirectory.appendingPathComponent(newNameWithCounter)
            counter += 1
        }

        return targetURL
    }

    public func file(document: URL, as newName: String, type: DocumentType) throws -> URL {
        // Get the target URL
        let targetURL = try getTargetURL(from: document, for: newName, type: type)

        // If the paths are different, move the file
        if targetURL.path != document.path {
            try FileManager.default.moveItem(at: document, to: targetURL)
        }

        return targetURL
    }

    private func folderName(for type: DocumentType) -> String {
        let year = Calendar.current.component(.year, from: Date())

        switch type {
        case .invoice:
            return "\(year)/Rechnungen"
        case .receipt:
            return "\(year)/Quittungen"
        case .contract:
            return "Verträge"
        case .letter:
            return "\(year)/Briefe"
        case .report:
            return "\(year)/Berichte"
        case .statement:
            return "\(year)/Kontoauszüge"
        case .unknown:
            return "Unsortiert"
        }
    }

    public func openInFinder(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        #endif
    }

    public func getStorageStatistics() -> StorageStatistics {
        var totalFiles = 0
        var totalSize: Int64 = 0
        var filesByType: [DocumentType: Int] = [:]

        let enumerator = FileManager.default.enumerator(
            at: baseDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "pdf" {
                totalFiles += 1

                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let fileSize = attributes[.size] as? NSNumber {
                    totalSize += fileSize.int64Value
                }

                // Determine type from folder structure
                let pathComponents = fileURL.pathComponents
                if pathComponents.contains("Rechnungen") {
                    filesByType[.invoice, default: 0] += 1
                } else if pathComponents.contains("Quittungen") {
                    filesByType[.receipt, default: 0] += 1
                } else if pathComponents.contains("Verträge") {
                    filesByType[.contract, default: 0] += 1
                } else if pathComponents.contains("Briefe") {
                    filesByType[.letter, default: 0] += 1
                } else if pathComponents.contains("Berichte") {
                    filesByType[.report, default: 0] += 1
                } else if pathComponents.contains("Kontoauszüge") {
                    filesByType[.statement, default: 0] += 1
                } else {
                    filesByType[.unknown, default: 0] += 1
                }
            }
        }

        return StorageStatistics(
            totalFiles: totalFiles,
            totalSize: totalSize,
            filesByType: filesByType,
            baseDirectory: baseDirectory
        )
    }
}

public struct StorageStatistics {
    public let totalFiles: Int
    public let totalSize: Int64
    public let filesByType: [DocumentType: Int]
    public let baseDirectory: URL

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
}