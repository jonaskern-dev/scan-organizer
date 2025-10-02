import AppIntents
import Foundation
import AppKit

@available(macOS 14.0, *)
struct ProcessPDFIntent: AppIntent {
    static var title: LocalizedStringResource = "Process with Scan Organizer"
    static var description: IntentDescription? = IntentDescription("Add PDF files to Scan Organizer queue for processing")

    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = true

    @Parameter(title: "PDF Files")
    var files: [IntentFile]

    init() {}

    init(files: [IntentFile]) {
        self.files = files
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Get file URLs from IntentFile
        let fileURLs = files.compactMap { $0.fileURL }

        // Filter for PDF files only
        let pdfURLs = fileURLs.filter { url in
            url.pathExtension.lowercased() == "pdf"
        }

        guard !pdfURLs.isEmpty else {
            throw ProcessPDFError.noPDFFiles
        }

        // Create a custom URL scheme to send files to the main app
        // Format: scanorganizer://process?files=file1,file2,file3
        let encodedPaths = pdfURLs.map { $0.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "" }
        let filesParam = encodedPaths.joined(separator: ",")

        if let url = URL(string: "scanorganizer://process?files=\(filesParam)") {
            // Open the URL which will trigger the main app
            NSWorkspace.shared.open(url)
        }

        // Alternative: Write to queue file for the main app to pick up
        let queueDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ScanOrganizer")
        let queueFile = queueDir.appendingPathComponent("queue.txt")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)

        // Append paths to queue file
        let paths = pdfURLs.map { $0.path }.joined(separator: "\n") + "\n"

        if FileManager.default.fileExists(atPath: queueFile.path) {
            if let handle = try? FileHandle(forWritingTo: queueFile) {
                handle.seekToEndOfFile()
                handle.write(paths.data(using: .utf8) ?? Data())
                handle.closeFile()
            }
        } else {
            try? paths.write(to: queueFile, atomically: true, encoding: .utf8)
        }

        return .result(
            dialog: IntentDialog("Added \(pdfURLs.count) PDF file(s) to Scan Organizer queue")
        )
    }
}

@available(macOS 14.0, *)
enum ProcessPDFError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noPDFFiles

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noPDFFiles:
            return "No PDF files selected"
        }
    }
}

@available(macOS 14.0, *)
struct ScanOrganizerAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ProcessPDFIntent(),
            phrases: [
                "Process with \(.applicationName)",
                "Add to \(.applicationName) queue"
            ],
            shortTitle: "Process PDFs",
            systemImageName: "doc.text.viewfinder"
        )
    }
}
