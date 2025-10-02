import Foundation
import Combine

public enum QueueItemStatus: Equatable {
    case pending
    case processing
    case completed
    case failed(Error)

    public static func == (lhs: QueueItemStatus, rhs: QueueItemStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending), (.processing, .processing), (.completed, .completed):
            return true
        case (.failed, .failed):
            return true // We consider all failed states equal for simplicity
        default:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    public var isFinished: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
        }
    }
}

public class QueueItem: ObservableObject, Identifiable {
    public let id = UUID()
    public let fileURL: URL
    public let fileName: String
    public let fileSize: Int64
    public let addedAt: Date

    @Published public var status: QueueItemStatus = .pending
    @Published public var progress: Double = 0.0
    @Published public var currentStep: String = ""
    @Published public var processingLog: [String] = []
    @Published public var result: ProcessingResult?
    @Published public var processingTime: TimeInterval?
    @Published public var tempImagePath: URL?  // Store temp image for preview
    @Published public var tempOCRText: String?  // Store OCR text during processing
    @Published public var tempVisionAIResponse: String?  // Store Vision AI response during processing
    @Published public var tempTextAIResponse: String?  // Store Text AI response during processing
    @Published public var tempJsonRequests: [String: String] = [:]  // Store JSON requests by type
    @Published public var tempJsonResponses: [String: String] = [:]  // Store JSON responses by type

    public var originalFileExists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public var currentFileURL: URL {
        // Return processed path if available and original doesn't exist, otherwise original
        if let processedPath = result?.document?.processedPath,
           !originalFileExists {
            return processedPath
        }
        return fileURL
    }

    public func addLogEntry(_ message: String) {
        Task { @MainActor in
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            processingLog.append("[\(timestamp)] \(message)")
        }
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
        self.addedAt = Date()

        // Get file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attributes[.size] as? NSNumber {
            self.fileSize = size.int64Value
        } else {
            self.fileSize = 0
        }
    }
}

public class ProcessingQueue: ObservableObject {
    @Published public var items: [QueueItem] = []
    @Published public var isProcessing = false
    @Published public var currentItem: QueueItem?
    @Published public var processedCount = 0
    @Published public var failedCount = 0

    private let processor: PDFProcessor
    private var processingTask: Task<Void, Never>?
    private let maxConcurrentItems = 1 // Sequential processing for now
    private var autoStartEnabled = false // Prevent auto-start until setup complete

    public var pendingItems: [QueueItem] {
        items.filter { $0.status == .pending }
    }

    public var completedItems: [QueueItem] {
        items.filter { $0.status == .completed }
    }

    public var failedItems: [QueueItem] {
        items.filter {
            if case .failed = $0.status { return true }
            return false
        }
    }

    public init() {
        self.processor = PDFProcessor()
    }

    public func addFile(_ url: URL) {
        guard url.pathExtension.lowercased() == "pdf" else { return }

        // Check if already in queue
        if items.contains(where: { $0.fileURL == url }) {
            return
        }

        let item = QueueItem(fileURL: url)
        items.append(item)

        // Start processing if not already running and auto-start is enabled
        if !isProcessing && autoStartEnabled {
            startProcessing()
        }
    }

    public func addFiles(_ urls: [URL]) {
        for url in urls {
            addFile(url)
        }
    }

    public func removeItem(_ item: QueueItem) {
        items.removeAll { $0.id == item.id }
    }

    public func clearCompleted() {
        items.removeAll { $0.status == .completed }
    }

    public func clearAll() {
        stopProcessing()
        items.removeAll()
        processedCount = 0
        failedCount = 0
    }

    public func retryFailed() {
        for item in failedItems {
            item.status = .pending
            item.progress = 0
            item.currentStep = ""
        }

        if !isProcessing {
            startProcessing()
        }
    }

    public func retryItem(_ item: QueueItem) {
        item.status = .pending
        item.progress = 0
        item.currentStep = ""
        item.processingLog.append("--- RETRY ---")

        if !isProcessing {
            startProcessing()
        }
    }

    public func startProcessing() {
        guard !isProcessing else { return }

        autoStartEnabled = true // Enable auto-start for future files
        isProcessing = true

        processingTask = Task {
            await processQueue()
        }
    }

    public func stopProcessing() {
        processingTask?.cancel()
        isProcessing = false
        currentItem = nil
    }

    private func processQueue() async {
        while isProcessing {
            // Check for pending items
            if let nextItem = pendingItems.first {
                await MainActor.run {
                    currentItem = nextItem
                }
                await processItem(nextItem)

                // Small delay between items
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            } else {
                // No items currently, but keep checking for new ones
                await MainActor.run {
                    currentItem = nil
                }

                // Wait a bit before checking again
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

                // Continue looping - don't stop processing
                // This allows adding items while running
            }
        }

        // Only reach here when explicitly stopped
        await MainActor.run {
            currentItem = nil
        }
    }

    private func processItem(_ item: QueueItem) async {
        await MainActor.run {
            item.status = .processing
            item.progress = 0.0
            item.currentStep = "Starting processing..."
            item.processingLog.removeAll()  // Clear old logs
        }

        let startTime = Date()

        do {
            // Create processor with delegate to capture real-time updates
            let processor = PDFProcessorWithStatus(item: item)

            // Process the PDF - all status updates will come through delegate
            let result = try await processor.process(pdfURL: item.fileURL)

            await MainActor.run {
                item.progress = 1.0
                item.currentStep = "Completed"
                item.status = .completed
                item.result = result
                item.processingTime = Date().timeIntervalSince(startTime)

                processedCount += 1
            }

        } catch {
            await MainActor.run {
                item.status = .failed(error)
                item.progress = 0
                item.currentStep = "Error: \(error.localizedDescription)"
                item.addLogEntry("ERROR: \(error.localizedDescription)")
                failedCount += 1
            }
        }
    }
}

// Custom processor that reports status
class PDFProcessorWithStatus: PDFProcessor, ProcessingDelegate {
    private weak var item: QueueItem?
    private var collectingMode: String? = nil  // Track what we're collecting
    private var collectedContent: String = ""  // Accumulate multi-line content

    init(item: QueueItem) {
        self.item = item
        super.init()
        self.delegate = self
    }

    func updateStatus(_ message: String, progress: Double) {
        Task { @MainActor in
            item?.currentStep = message
            item?.progress = progress
        }
    }

    func addLogEntry(_ message: String) {
        // Check for special OCR text markers and don't add them to visible log
        if message.contains("[OCR_TEXT_START]") && message.contains("[OCR_TEXT_END]") {
            // Extract and store OCR text without adding to log
            if let startRange = message.range(of: "[OCR_TEXT_START]"),
               let endRange = message.range(of: "[OCR_TEXT_END]") {
                let ocrText = String(message[startRange.upperBound..<endRange.lowerBound])
                Task { @MainActor in
                    item?.tempOCRText = ocrText
                }
            }
            return // Don't add this to the visible log
        }

        // Check for special PROMPT markers and store as header + content
        if message.contains("[PROMPT_START]") && message.contains("[PROMPT_END]") {
            // Extract and store prompt without markers
            if let startRange = message.range(of: "[PROMPT_START]"),
               let endRange = message.range(of: "[PROMPT_END]") {
                let promptText = String(message[startRange.upperBound..<endRange.lowerBound])
                // Don't add the raw message, the header was already added
                // Instead, just trigger collection mode for the prompt
                Task { @MainActor in
                    // Store the prompt content based on the last header
                    if let lastLog = item?.processingLog.last {
                        if lastLog.contains("Vision AI Prompt:") {
                            item?.tempJsonRequests["visionAIPrompt"] = promptText
                        } else if lastLog.contains("Text AI Prompt:") {
                            item?.tempJsonRequests["textAIPrompt"] = promptText
                        }
                    }
                }
            }
            return // Don't add this to the visible log
        }

        // Add to visible log
        item?.addLogEntry(message)

        // Handle multi-line content collection
        Task { @MainActor in
            if let item = item {
                // Check if we should stop collecting (new section starts)
                if message.contains("===") || message.contains("---") || message.contains("Sending request to") || message.contains("\n>>") {
                    // Save any collected content
                    if let mode = collectingMode, !collectedContent.isEmpty {
                        switch mode {
                        case "visionAIResponse":
                            item.tempVisionAIResponse = collectedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        case "textAIResponse":
                            item.tempTextAIResponse = collectedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        case "visionAIRequest":
                            item.tempJsonRequests["visionAI"] = collectedContent
                        case "textAIRequest":
                            item.tempJsonRequests["textAI"] = collectedContent
                        case "textAIFullResponse":
                            item.tempJsonResponses["textAI"] = collectedContent
                        default:
                            break
                        }
                    }
                    collectingMode = nil
                    collectedContent = ""
                }

                // Check if this starts a new collection mode
                if message.contains("Vision AI Response:") {
                    collectingMode = "visionAIResponse"
                    collectedContent = ""
                    // Extract content from same line if present
                    if let colonIndex = message.firstIndex(of: ":") {
                        let content = String(message[message.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !content.isEmpty {
                            collectedContent = content
                            collectingMode = nil  // Single line, no more collection needed
                            item.tempVisionAIResponse = content
                        }
                    }
                } else if message.contains("Text AI Response:") {
                    collectingMode = "textAIResponse"
                    collectedContent = ""
                    // Extract content from same line if present
                    if let colonIndex = message.firstIndex(of: ":") {
                        let content = String(message[message.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !content.isEmpty {
                            collectedContent = content
                            collectingMode = nil  // Single line, no more collection needed
                            item.tempTextAIResponse = content
                        }
                    }
                } else if message.contains("Vision AI Request JSON:") {
                    collectingMode = "visionAIRequest"
                    collectedContent = ""
                    // Next log entry will be the JSON
                } else if message.contains("Text AI Request JSON:") {
                    collectingMode = "textAIRequest"
                    collectedContent = ""
                    // Next log entry will be the JSON
                } else if message.contains("Text AI Full Response JSON:") {
                    collectingMode = "textAIFullResponse"
                    collectedContent = ""
                    // Next log entry will be the JSON
                }
                // Continue collecting if in collection mode
                else if let _ = collectingMode {
                    if !collectedContent.isEmpty {
                        collectedContent += "\n"
                    }
                    collectedContent += message
                }
            }
        }
    }

    func setTempImage(_ url: URL?) {
        Task { @MainActor in
            item?.tempImagePath = url
        }
    }
}

// MARK: - File Monitoring
extension ProcessingQueue {
    public func startMonitoring(directory: URL) {
        // Monitor directory for new PDFs
        let monitor = DirectoryMonitor(url: directory) { [weak self] newFiles in
            guard let self = self else { return }
            Task { @MainActor in
                self.addFiles(newFiles.filter { $0.pathExtension.lowercased() == "pdf" })
            }
        }
        monitor.start()
    }
}

// Directory Monitor Helper
public class DirectoryMonitor {
    private let url: URL
    private let callback: ([URL]) -> Void
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var lastContents: Set<URL> = []

    public init(url: URL, callback: @escaping ([URL]) -> Void) {
        self.url = url
        self.callback = callback
    }

    public func start() {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor != -1 else { return }

        dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write],
            queue: DispatchQueue.global(qos: .background)
        )

        // Get initial contents
        lastContents = Set(contentsOfDirectory())

        dispatchSource?.setEventHandler { [weak self] in
            self?.directoryDidChange()
        }

        dispatchSource?.setCancelHandler {
            close(descriptor)
        }

        dispatchSource?.resume()
    }

    public func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    private func directoryDidChange() {
        let currentContents = Set(contentsOfDirectory())
        let newFiles = currentContents.subtracting(lastContents)

        if !newFiles.isEmpty {
            callback(Array(newFiles))
        }

        lastContents = currentContents
    }

    private func contentsOfDirectory() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
    }
}