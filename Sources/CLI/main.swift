import Foundation
import ArgumentParser
import ScanOrganizerCore

@available(macOS 10.15, *)
struct ScanOrganizer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "PDF Scan Organizer - Intelligent document processing",
        version: "1.0.7",
        subcommands: [Process.self, Watch.self, Queue.self, Stats.self]
    )
}

// MARK: - Process Command
struct Process: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Process a single PDF file"
    )

    @Argument(help: "Path to PDF file")
    var pdfPath: String

    @Option(name: .shortAndLong, help: "Processing mode (auto, quick, full)")
    var mode: String = "auto"

    @Flag(name: .shortAndLong, help: "Output result as JSON")
    var json: Bool = false

    func run() async throws {
        let url = URL(fileURLWithPath: pdfPath)
        let processor = PDFProcessor()

        do {
            let result = try await processor.process(pdfURL: url)

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                if let data = try? encoder.encode(result),
                   let string = String(data: data, encoding: .utf8) {
                    print(string)
                }
            } else {
                if result.success {
                    print("[OK] Processed: \(url.lastPathComponent)")
                    if let doc = result.document {
                        print("  Type: \(doc.documentType.displayName) (\(Int(doc.confidence * 100))% confidence)")
                        if let vendor = doc.vendor {
                            print("  Vendor: \(vendor)")
                        }
                        if let amount = doc.amount {
                            print("  Amount: \(amount)")
                        }
                        if let newPath = doc.processedPath {
                            print("  New path: \(newPath.path)")
                        }
                    }
                } else if let error = result.error {
                    print("[FAILED] \(url.lastPathComponent)")
                    print("  Error: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Processing failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

// MARK: - Watch Command
struct Watch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Watch a folder for new PDFs"
    )

    @Argument(help: "Directory to watch")
    var directory: String

    @Option(name: .shortAndLong, help: "Check interval in seconds")
    var interval: Int = 2

    func run() async throws {
        let url = URL(fileURLWithPath: directory)
        let queue = ProcessingQueue()

        print("Watching: \(url.path)")
        print("Check interval: \(interval)s")
        print("Press Ctrl+C to stop\n")

        queue.startMonitoring(directory: url)
        queue.startProcessing()

        // Keep running until interrupted
        try await Task.sleep(nanoseconds: UInt64.max)
    }
}

// MARK: - Queue Command
struct Queue: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Process PDFs in a queue"
    )

    @Argument(help: "PDF files to process", completion: .file(extensions: ["pdf"]))
    var files: [String]

    @Flag(name: .shortAndLong, help: "Show progress")
    var progress: Bool = false

    func run() async throws {
        let queue = ProcessingQueue()

        // Add all files to queue
        for filePath in files {
            let url = URL(fileURLWithPath: filePath)
            queue.addFile(url)
        }

        print("Processing \(files.count) files...")

        // Start processing
        queue.startProcessing()

        // Monitor progress
        while queue.isProcessing {
            if progress {
                let pending = queue.pendingItems.count
                let completed = queue.completedItems.count
                let failed = queue.failedItems.count
                print("\rPending: \(pending) | Completed: \(completed) | Failed: \(failed)", terminator: "")
                fflush(stdout)
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        if progress {
            print() // New line after progress
        }

        // Show summary
        print("\nProcessing complete:")
        print("  Successful: \(queue.processedCount)")
        print("  Failed: \(queue.failedCount)")

        // Show failures
        for item in queue.failedItems {
            if case .failed(let error) = item.status {
                print("  - \(item.fileName): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Stats Command
struct Stats: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show processing statistics"
    )

    func run() throws {
        let organizer = FileOrganizer()
        let stats = organizer.getStorageStatistics()

        print("\n=== PDF Scanner Statistics ===\n")
        print("Total files: \(stats.totalFiles)")
        print("Total size: \(stats.formattedSize)")
        print("Storage location: \(stats.baseDirectory.path)")

        if !stats.filesByType.isEmpty {
            print("\nBy document type:")
            for (type, count) in stats.filesByType.sorted(by: { $0.value > $1.value }) {
                print("  \(type.displayName): \(count)")
            }
        }
    }
}

// Run the command
ScanOrganizer.main()