import SwiftUI
import ScanOrganizerCore
import ScanOrganizerAppIntents
import AppKit
import PDFKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var queue: ProcessingQueue?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.pathExtension.lowercased() == "pdf" {
                queue?.addFile(url)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @objc func processFiles(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return
        }

        for url in fileURLs where url.pathExtension.lowercased() == "pdf" {
            queue?.addFile(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register for file open events
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )

        // Register custom URL scheme handler
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Register Services menu handler
        NSApplication.shared.servicesProvider = self
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        // Handle scanorganizer:// URL scheme
        if url.scheme == "scanorganizer" && url.host == "process" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let filesParam = components.queryItems?.first(where: { $0.name == "files" })?.value {
                let paths = filesParam.split(separator: ",").compactMap { path -> URL? in
                    guard let decodedPath = String(path).removingPercentEncoding else { return nil }
                    return URL(fileURLWithPath: decodedPath)
                }

                for fileURL in paths {
                    if fileURL.pathExtension.lowercased() == "pdf" {
                        queue?.addFile(fileURL)
                    }
                }
            }
        }
    }

    @objc func handleOpenEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let appleEventDescriptor = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else {
            return
        }

        let numberOfItems = appleEventDescriptor.numberOfItems
        if numberOfItems > 0 {
            for index in 1...numberOfItems {
                if let itemDescriptor = appleEventDescriptor.atIndex(index) {
                    if let path = itemDescriptor.stringValue,
                       let fileURL = URL(string: path) ?? URL(fileURLWithPath: path) as URL? {
                        if fileURL.pathExtension.lowercased() == "pdf" {
                            queue?.addFile(fileURL)
                        }
                    }
                }
            }
        }
    }
}

@main
struct ScanOrganizerApp: App {
    @StateObject private var queue = ProcessingQueue()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var queueWatcher: Timer?
    @State private var setupComplete = false
    @State private var recheckSetup = false
    private let notificationDelegate = NotificationDelegate()

    init() {
        // Set up the app delegate's queue reference
        // Setup notification delegate and categories
        #if os(macOS)
        UNUserNotificationCenter.current().delegate = notificationDelegate
        NotificationService.shared.setupNotificationCategories()
        #endif
    }

    var body: some Scene {
        Window("Scan Organizer", id: "main") {
            ContentView()
                .environmentObject(queue)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    appDelegate.queue = queue

                    // Allow queue to accept files, but don't process yet
                    startQueueWatcher()

                    // Check first run setup - blocks processing until complete
                    performSetupCheck()

                    // Listen for recheck notification from ConfigView
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("RecheckSetup"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        recheckSetup = true
                    }
                }
                .onChange(of: recheckSetup) {
                    if recheckSetup {
                        recheckSetup = false
                        setupComplete = false
                        performSetupCheck()
                    }
                }
                .overlay {
                    if !setupComplete {
                        ZStack {
                            Color.black.opacity(0.5)
                            VStack(spacing: 20) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Checking system requirements...")
                                    .foregroundColor(.white)
                            }
                        }
                        .ignoresSafeArea()
                    }
                }
                .onDisappear {
                    queueWatcher?.invalidate()
                }
                .onOpenURL { url in
                    if url.pathExtension.lowercased() == "pdf" {
                        queue.addFile(url)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Files...") {
                    openFileDialog()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    private func performSetupCheck() {
        FirstRunSetup.shared.checkAndRunSetup { success in
            setupComplete = success
            if success {
                // Setup complete, start processing
                queue.startProcessing()
                handleCommandLineFiles()
            }
            // Note: If user quits setup window, app will terminate via window delegate
        }
    }

    private func handleCommandLineFiles() {
        // Handle files passed as arguments
        for arg in CommandLine.arguments.dropFirst() {
            if arg.hasSuffix(".pdf") {
                queue.addFile(URL(fileURLWithPath: arg))
            }
        }
    }

    private func startQueueWatcher() {
        let queueDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ScanOrganizer")
        let queueFile = queueDir.appendingPathComponent("queue.txt")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)

        // Watch for changes to queue file
        queueWatcher = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if FileManager.default.fileExists(atPath: queueFile.path) {
                if let contents = try? String(contentsOf: queueFile, encoding: .utf8) {
                    let files = contents.split(separator: "\n")
                    for file in files {
                        let path = String(file).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !path.isEmpty {
                            let url = URL(fileURLWithPath: path)
                            if url.pathExtension.lowercased() == "pdf" {
                                queue.addFile(url)
                            }
                        }
                    }
                    // Clear the queue file after processing
                    try? "".write(to: queueFile, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Choose PDF files to process"
        panel.prompt = "Open"

        if panel.runModal() == .OK {
            queue.addFiles(panel.urls)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var queue: ProcessingQueue
    @State private var isDragging = false
    @State private var selectedItem: QueueItem?
    @StateObject private var resourceMonitor = ResourceMonitor()
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Resource Monitor Bar (subtle, at the top)
            ResourceBarView(monitor: resourceMonitor)
                .frame(height: 24)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            // Main content with custom split view
            CustomSplitView(initialSplitRatio: 0.33) {
                // Left: Queue List
                QueueListView(selectedItem: $selectedItem, isDragging: $isDragging)
            } right: {
                // Right: Details
                if let item = selectedItem {
                    ItemDetailView(item: item)
                } else {
                    EmptyDetailView()
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: queue.currentItem?.id) {
            // Auto-select the currently processing item
            if let current = queue.currentItem {
                selectedItem = current
            }
        }
        .onAppear {
            resourceMonitor.startMonitoring(interval: 0.5)  // Update every 500ms

            // Listen for "OpenSettings" notification from setup window
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("OpenSettings"),
                object: nil,
                queue: .main
            ) { _ in
                showingSettings = true
            }
        }
        .onDisappear {
            resourceMonitor.stopMonitoring()
        }
        .sheet(isPresented: $showingSettings) {
            ConfigView()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var acceptedFiles = false

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                acceptedFiles = true
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url else { return }

                    // Handle both file URLs and dropped files
                    if url.pathExtension.lowercased() == "pdf" {
                        Task { @MainActor in
                            self.queue.addFile(url)
                        }
                    }
                }
            }
        }
        return acceptedFiles
    }
}

struct QueueListView: View {
    @EnvironmentObject var queue: ProcessingQueue
    @Binding var selectedItem: QueueItem?
    @Binding var isDragging: Bool
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Queue (\(queue.items.count))", systemImage: "doc.text.fill.viewfinder")
                    .font(.headline)
                Spacer()

                // Settings button
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings")

                // Setup Status button
                Button(action: {
                    FirstRunSetup.shared.showSetupWindowManually()
                }) {
                    Image(systemName: "checklist")
                }
                .buttonStyle(.plain)
                .help("System Setup Status")

                if queue.isProcessing {
                    Button(action: { queue.stopProcessing() }) {
                        Image(systemName: "stop.fill")
                    }
                } else if !queue.pendingItems.isEmpty {
                    Button(action: { queue.startProcessing() }) {
                        Image(systemName: "play.fill")
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            // List
            ScrollView {
                VStack(spacing: 2) {
                    if queue.items.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 60))
                                .foregroundColor(isDragging ? .accentColor : .secondary)

                            Text("Drop PDF files here")
                                .font(.title3)

                            Text("or drag to app icon")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 400)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                                    style: StrokeStyle(lineWidth: 2, dash: isDragging ? [] : [8])
                                )
                        )
                        .padding(20)
                    } else {
                        ForEach(queue.items) { item in
                            QueueItemRow(
                                item: item,
                                isSelected: selectedItem?.id == item.id,
                                isActive: queue.currentItem?.id == item.id
                            )
                            .onTapGesture {
                                selectedItem = item
                            }
                        }
                    }
                }
                .padding(8)
            }

            // Footer
            HStack(spacing: 16) {
                Label("\(queue.processedCount) processed", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
                    .font(.caption)

                if queue.failedCount > 0 {
                    Label("\(queue.failedCount) failed", systemImage: "xmark.circle")
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Spacer()

                if queue.failedCount > 0 {
                    Button("Retry failed") {
                        queue.retryFailed()
                    }
                    .font(.caption)
                }

                if !queue.completedItems.isEmpty {
                    Button("Clear completed") {
                        queue.clearCompleted()
                    }
                    .font(.caption)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .sheet(isPresented: $showingSettings) {
            ConfigView()
        }
    }
}

struct QueueItemRow: View {
    @ObservedObject var item: QueueItem
    let isSelected: Bool
    let isActive: Bool
    @EnvironmentObject var queue: ProcessingQueue

    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            Group {
                switch item.status {
                case .pending:
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                case .processing:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.fileName)
                        .font(.system(size: 13))
                        .lineLimit(1)

                    // Only show eye button if file exists at any location
                    if item.originalFileExists || item.result?.document?.processedPath != nil {
                        Button(action: {
                            NSWorkspace.shared.open(item.currentFileURL)
                        }) {
                            Image(systemName: "eye")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor.opacity(0.7))
                        .help("Open PDF in Preview")
                    }
                }

                if item.status == .processing {
                    HStack(spacing: 4) {
                        Text(item.currentStep)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ProgressView(value: item.progress)
                            .progressViewStyle(.linear)
                            .frame(width: 100)
                    }
                }
            }

            Spacer()

            if case .failed = item.status {
                Button(action: {
                    queue.retryItem(item)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.orange)
                .help("Retry processing")
            }

            if item.status == .completed, let result = item.result?.document {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(result.aiType?.capitalized ?? result.documentType.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)

                    Text("\(Int(result.confidence * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isActive ? Color.blue.opacity(0.2) :
            isSelected ? Color.accentColor.opacity(0.1) :
            Color(NSColor.controlBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
        )
        .cornerRadius(6)
    }
}

struct ItemDetailView: View {
    @ObservedObject var item: QueueItem
    @EnvironmentObject var queue: ProcessingQueue

    var body: some View {
        VStack(spacing: 0) {
            // Header section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StatusIcon(status: item.status)
                        .font(.title)
                    VStack(alignment: .leading) {
                        HStack {
                            Text(item.fileName)
                                .font(.title3)

                            // Preview original PDF only if it still exists
                            if item.originalFileExists {
                                Button(action: {
                                    NSWorkspace.shared.open(item.fileURL)
                                }) {
                                    Image(systemName: "eye")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                                .help("Open original PDF in Preview")
                            }
                        }
                        Text("Added: \(item.addedAt.formatted())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                // Progress bar if processing
                if item.status == .processing {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.currentStep)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(item.progress * 100))%")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: item.progress)
                            .progressViewStyle(.linear)

                        // Preview button during processing
                        HStack {
                            if item.originalFileExists {
                                Button(action: {
                                    NSWorkspace.shared.open(item.fileURL)
                                }) {
                                    Label("View PDF", systemImage: "doc.richtext")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            if let tempImage = item.tempImagePath,
                               FileManager.default.fileExists(atPath: tempImage.path) {
                                Button(action: {
                                    NSWorkspace.shared.open(tempImage)
                                }) {
                                    Label("View Page Image", systemImage: "photo")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                if let result = item.result?.document {
                    GroupBox("Processing Result") {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "Document Type", value: result.aiType?.capitalized ?? result.documentType.displayName)
                            InfoRow(label: "Confidence", value: "\(Int(result.confidence * 100))%")

                            if let vendor = result.vendor {
                                InfoRow(label: "Vendor", value: vendor)
                            }

                            if let amount = result.amount {
                                InfoRow(label: "Amount", value: formatCurrency(amount))
                            }

                            if let date = result.date {
                                InfoRow(label: "Date", value: date.formatted(date: .abbreviated, time: .omitted))
                            }

                            if let newPath = result.processedPath {
                                HStack {
                                    Text("New Name:")
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .leading)
                                    Text(newPath.lastPathComponent)
                                        .fontWeight(.medium)
                                        .textSelection(.enabled)

                                    Button(action: {
                                        NSWorkspace.shared.open(newPath)
                                    }) {
                                        Image(systemName: "eye")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.accentColor)
                                    .help("Open renamed PDF in Preview")

                                    Button(action: {
                                        NSWorkspace.shared.selectFile(newPath.path, inFileViewerRootedAtPath: "")
                                    }) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.accentColor)
                                    .help("Show in Finder")

                                    Spacer()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if case .failed(let error) = item.status {
                    GroupBox("Error") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error.localizedDescription)
                                .foregroundColor(.red)
                                .font(.system(.body, design: .monospaced))

                            Button(action: {
                                queue.retryItem(item)
                            }) {
                                Label("Retry Processing", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

            }
            .padding()

            Divider()

            // Processing Log
            if !item.processingLog.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Processing Log")
                            .font(.headline)

                        Spacer()

                        Button(action: {
                            let logText = item.processingLog.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(logText, forType: .string)
                        }) {
                            Label("Copy All", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.windowBackgroundColor))

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(item.processingLog.enumerated()), id: \.offset) { index, log in
                                    LogEntryView(
                                        log: log,
                                        item: item,
                                        index: index
                                    )
                                    .id(index)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .onChange(of: item.processingLog.count) {
                            // Auto-scroll to bottom
                            withAnimation {
                                proxy.scrollTo(item.processingLog.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }

    private func getTitle(from item: QueueItem) -> String? {
        // Try to find title from processing log
        for log in item.processingLog {
            if log.contains("Title:") {
                let components = log.split(separator: ":")
                if components.count >= 2 {
                    return String(components[1...].joined(separator: ":")).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
}

struct StatusIcon: View {
    let status: QueueItemStatus

    var body: some View {
        Group {
            switch status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
            case .processing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.accentColor)
                    .rotationEffect(.degrees(360))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: true)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

struct LogEntryView: View {
    let log: String
    @ObservedObject var item: QueueItem
    let index: Int

    @State private var isExpanded = false

    var logType: LogType {
        if log.contains("===") { return .header }
        if log.contains("---") { return .step }
        if log.contains("characters extracted") { return .ocrExtracted }
        if log.contains("First 200 characters:") { return .ocrPreview }
        if log.contains("Vision AI Response:") { return .visionAI }
        if log.contains("Text AI Response:") { return .textAI }
        if log.contains("Vision AI Request JSON:") { return .jsonRequest }
        if log.contains("Text AI Request JSON:") { return .jsonRequest }
        if log.contains("Text AI Full Response JSON:") { return .jsonResponse }
        if log.contains("Vision AI Prompt") { return .aiPrompt }
        if log.contains("Text AI Prompt") { return .aiPrompt }
        if log.contains("KB PNG") { return .imageInfo }
        if log.contains("Selected text:") { return .ocrSelected }
        if log.contains("Decision:") { return .decision }
        if log.contains("COMPLETED") { return .completed }
        if log.contains("ERROR") { return .error }
        return .regular
    }

    enum LogType {
        case header, step, ocrExtracted, ocrPreview, ocrSelected
        case visionAI, textAI, aiPrompt, jsonRequest, jsonResponse, imageInfo
        case decision, completed, error, regular

        var isExpandable: Bool {
            switch self {
            case .ocrExtracted, .ocrPreview, .ocrSelected, .visionAI, .textAI, .aiPrompt, .jsonRequest, .jsonResponse, .imageInfo:
                return true
            default:
                return false
            }
        }

        var icon: String? {
            switch self {
            case .header: return "doc.text.fill"
            case .step: return "arrow.right.circle"
            case .ocrExtracted, .ocrPreview, .ocrSelected: return "text.alignleft"
            case .visionAI, .textAI: return "brain"
            case .aiPrompt: return "text.bubble"
            case .jsonRequest, .jsonResponse: return "curlybraces"
            case .imageInfo: return "photo"
            case .decision: return "checkmark.circle"
            case .completed: return "checkmark.seal.fill"
            case .error: return "xmark.octagon.fill"
            case .regular: return nil
            }
        }

        var color: Color {
            switch self {
            case .header: return .blue
            case .step: return .purple
            case .ocrExtracted, .ocrPreview, .ocrSelected: return .orange
            case .visionAI, .textAI: return .indigo
            case .aiPrompt: return .gray
            case .jsonRequest, .jsonResponse: return .cyan
            case .imageInfo: return .teal
            case .decision: return .mint
            case .completed: return .green
            case .error: return .red
            case .regular: return .primary
            }
        }
    }

    @State private var hasContent: Bool = true

    var body: some View {
        // Only show if has actual expandable content or is not expandable
        if hasContent || !logType.isExpandable {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    // Icon or expand indicator
                    if logType.isExpandable && hasContent {
                        Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle")
                            .font(.system(size: 12))
                            .foregroundColor(logType.color.opacity(0.7))
                            .frame(width: 20)
                    } else if logType.icon != nil {
                        Image(systemName: logType.icon!)
                            .font(.system(size: 11))
                            .foregroundColor(logType.color.opacity(0.7))
                            .frame(width: 20)
                    } else {
                        Spacer()
                            .frame(width: 20)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // Main log text
                        HStack {
                            Text(getMainLogText())
                                .font(getLogFont())
                                .foregroundColor(logType.color)
                                .textSelection(.enabled)
                                .lineLimit(isExpanded ? nil : 2)

                            Spacer()

                            // Action buttons inline
                            HStack(spacing: 4) {
                                if shouldShowCopyButton() {
                                    Button(action: { copyLogContent() }) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.accentColor.opacity(0.7))
                                    .help("Copy content")
                                }

                                if logType == .imageInfo && item.tempImagePath != nil {
                                    Button(action: { openImage() }) {
                                        Image(systemName: "eye")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.accentColor.opacity(0.7))
                                    .help("Open image in Preview")
                                }
                            }
                        }

                        // Expanded content
                        if isExpanded && logType.isExpandable && hasContent {
                            ExpandedLogContent(
                                log: log,
                                logType: logType,
                                item: item
                            )
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, getVerticalPadding())
                .contentShape(Rectangle()) // Make entire area clickable
                .onTapGesture {
                    if logType.isExpandable && hasContent {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                }

                // Separator for sections
                if logType == .header || logType == .completed {
                    Divider()
                        .padding(.horizontal, 12)
                }
            }
            .background(getBackgroundColor())
            .onAppear {
                checkIfHasContent()
            }
        } else {
            EmptyView()
        }
    }

    private func getMainLogText() -> String {
        let cleanLog = log.replacingOccurrences(of: "\\[\\d{2}:\\d{2}:\\d{2}\\] ", with: "", options: .regularExpression)

        switch logType {
        case .ocrPreview:
            if let colonIndex = cleanLog.firstIndex(of: ":") {
                let prefix = String(cleanLog[..<colonIndex])
                if !isExpanded && hasContent {
                    let preview = String(cleanLog.suffix(from: cleanLog.index(after: colonIndex)))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return "\(prefix): \(String(preview.prefix(50)))... ▶"
                }
                return prefix + ":"
            }
        case .ocrExtracted, .ocrSelected:
            let baseText = cleanLog.components(separatedBy: ":").first ?? cleanLog
            if !isExpanded && hasContent {
                return baseText + " ▶"
            }
            return baseText
        case .visionAI, .textAI:
            let baseText = cleanLog.components(separatedBy: ":").first ?? cleanLog
            if !isExpanded && hasContent {
                return baseText + " ▶"
            }
            return baseText
        case .aiPrompt:
            if !isExpanded && hasContent {
                let parts = cleanLog.components(separatedBy: ":")
                if parts.count > 1 {
                    return "\(parts[0]): [\(parts[1].prefix(30))...] ▶"
                }
            }
        case .imageInfo:
            if !isExpanded && hasContent {
                return cleanLog + " ▶"
            }
            return cleanLog
        default:
            break
        }

        return cleanLog
    }

    private func getLogFont() -> Font {
        switch logType {
        case .header:
            return .system(size: 12, weight: .semibold, design: .monospaced)
        case .step:
            return .system(size: 11, weight: .medium, design: .monospaced)
        case .completed, .error:
            return .system(size: 11, weight: .bold, design: .monospaced)
        default:
            return .system(size: 11, design: .monospaced)
        }
    }

    private func getVerticalPadding() -> CGFloat {
        switch logType {
        case .header, .completed: return 6
        case .step: return 4
        default: return 2
        }
    }

    private func getBackgroundColor() -> Color {
        switch logType {
        case .header:
            return Color.blue.opacity(0.05)
        case .step:
            return Color.purple.opacity(0.03)
        case .completed:
            return Color.green.opacity(0.05)
        case .error:
            return Color.red.opacity(0.05)
        default:
            return Color.clear
        }
    }

    private func shouldShowCopyButton() -> Bool {
        switch logType {
        case .ocrExtracted, .ocrPreview, .ocrSelected, .visionAI, .textAI, .aiPrompt:
            return true
        default:
            return false
        }
    }

    private func copyLogContent() {
        var textToCopy = ""

        switch logType {
        case .ocrExtracted, .ocrSelected:
            if let text = item.result?.document?.extractedText {
                textToCopy = text
            } else {
                textToCopy = extractFullContent(from: log)
            }
        case .ocrPreview:
            textToCopy = extractFullContent(from: log)
        case .visionAI, .textAI, .aiPrompt:
            textToCopy = extractFullContent(from: log)
        default:
            textToCopy = log
        }

        if !textToCopy.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textToCopy, forType: .string)
        }
    }

    private func extractFullContent(from log: String) -> String {
        // Check if this log contains inline JSON
        if log.contains("{") && log.contains("}") {
            // Try to extract JSON from the log
            if let jsonStart = log.firstIndex(of: "{"),
               let jsonEnd = log.lastIndex(of: "}") {
                let jsonRange = jsonStart...jsonEnd
                return String(log[jsonRange])
            }
        }

        // Default: extract content after colon
        if let colonIndex = log.firstIndex(of: ":") {
            return String(log[log.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return log
    }

    private func openImage() {
        if let tempImagePath = item.tempImagePath,
           FileManager.default.fileExists(atPath: tempImagePath.path) {
            NSWorkspace.shared.open(tempImagePath)
        }
    }

    private func checkIfHasContent() {
        switch logType {
        case .ocrExtracted, .ocrSelected, .ocrPreview:
            // Check if we have OCR text (during processing or after)
            if let text = item.tempOCRText, !text.isEmpty {
                hasContent = true
            } else if let text = item.result?.document?.extractedText, !text.isEmpty {
                hasContent = true
            } else {
                // Try to extract from log
                let content = extractFullContent(from: log)
                hasContent = !content.isEmpty && content != log
            }
        case .visionAI:
            // Check for Vision AI response
            if let response = item.tempVisionAIResponse, !response.isEmpty {
                hasContent = true
            } else {
                let content = extractFullContent(from: log)
                hasContent = !content.isEmpty && content != log
            }
        case .textAI:
            // Check for Text AI response
            if let response = item.tempTextAIResponse, !response.isEmpty {
                hasContent = true
            } else {
                let content = extractFullContent(from: log)
                hasContent = !content.isEmpty && content != log
            }
        case .jsonRequest:
            // For JSON Request, check if we have JSON in the next log entries
            if let index = item.processingLog.firstIndex(of: log),
               index + 1 < item.processingLog.count {
                // Check if next log entry starts with {
                let nextLog = item.processingLog[index + 1]
                hasContent = nextLog.trimmingCharacters(in: .whitespaces).hasPrefix("{")
            } else if let json = item.tempJsonRequests["visionAI"], !json.isEmpty {
                hasContent = true
            } else if let json = item.tempJsonRequests["textAI"], !json.isEmpty {
                hasContent = true
            } else {
                let content = extractFullContent(from: log)
                hasContent = !content.isEmpty && content != log
            }
        case .jsonResponse:
            // Check for stored JSON response
            if let json = item.tempJsonResponses["textAI"], !json.isEmpty {
                hasContent = true
            } else {
                let content = extractFullContent(from: log)
                hasContent = !content.isEmpty && content != log
            }
        case .aiPrompt:
            // Check for stored prompt content
            if log.contains("Vision AI Prompt:"),
               let prompt = item.tempJsonRequests["visionAIPrompt"], !prompt.isEmpty {
                hasContent = true
            } else if log.contains("Text AI Prompt:"),
                      let prompt = item.tempJsonRequests["textAIPrompt"], !prompt.isEmpty {
                hasContent = true
            } else {
                // Fallback to checking content after colon
                let content = extractFullContent(from: log)
                hasContent = !content.isEmpty && content != log
            }
        case .imageInfo:
            // Check if image exists
            hasContent = item.tempImagePath != nil
        default:
            hasContent = false
        }
    }
}

struct ExpandedLogContent: View {
    let log: String
    let logType: LogEntryView.LogType
    @ObservedObject var item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if logType == .imageInfo {
                // Show image preview
                if let tempImagePath = item.tempImagePath,
                   FileManager.default.fileExists(atPath: tempImagePath.path) {
                    GroupBox {
                        if let nsImage = NSImage(contentsOf: tempImagePath) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 400)
                                .frame(maxWidth: .infinity)
                                .background(Color.black.opacity(0.1))
                                .cornerRadius(4)
                        } else {
                            Text("Image not available")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .groupBoxStyle(DefaultGroupBoxStyle())
                }
            } else {
                let content = extractContent()

                if !content.isEmpty {
                    GroupBox {
                        ScrollView {
                            Text(content)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: getMaxHeight())
                    }
                    .groupBoxStyle(DefaultGroupBoxStyle())
                }
            }
        }
    }

    private func extractContent() -> String {
        switch logType {
        case .ocrExtracted, .ocrSelected, .ocrPreview:
            // Try temporary OCR text first (during processing)
            if let text = item.tempOCRText, !text.isEmpty {
                return text
            }
            // Then try final result
            if let text = item.result?.document?.extractedText, !text.isEmpty {
                return text
            }
            // Fallback to extracting from log
            return extractFromLog()

        case .visionAI:
            // Try temporary Vision AI response first
            if let response = item.tempVisionAIResponse, !response.isEmpty {
                return response
            }
            // Fallback to extracting from log
            return extractFromLog()

        case .textAI:
            // Try temporary Text AI response first
            if let response = item.tempTextAIResponse, !response.isEmpty {
                return response
            }
            // Fallback to extracting from log
            return extractFromLog()

        case .jsonRequest:
            // For JSON Request, collect all following lines until we hit another header
            if let index = item.processingLog.firstIndex(of: log),
               index + 1 < item.processingLog.count {
                var jsonLines: [String] = []
                var currentIndex = index + 1

                while currentIndex < item.processingLog.count {
                    let line = item.processingLog[currentIndex]
                    let trimmed = line.trimmingCharacters(in: .whitespaces)

                    // Stop if we hit another header or command
                    if trimmed.hasPrefix("Sending") || trimmed.hasPrefix(">>")
                        || trimmed.contains("AI Response:") || trimmed.contains("===")
                        || trimmed.contains("---") {
                        break
                    }

                    jsonLines.append(line)
                    currentIndex += 1
                }

                if !jsonLines.isEmpty {
                    return jsonLines.joined(separator: "\n")
                }
            }

            // Fallback to stored JSON
            if log.contains("Vision AI Request JSON:"),
               let json = item.tempJsonRequests["visionAI"], !json.isEmpty {
                return json
            } else if log.contains("Text AI Request JSON:"),
                      let json = item.tempJsonRequests["textAI"], !json.isEmpty {
                return json
            }
            return ""

        case .jsonResponse:
            // Try to get stored JSON response
            if let json = item.tempJsonResponses["textAI"], !json.isEmpty {
                return json
            }
            return extractFromLog()

        case .aiPrompt:
            // Try to get stored prompt
            if log.contains("Vision AI Prompt:"),
               let prompt = item.tempJsonRequests["visionAIPrompt"], !prompt.isEmpty {
                return prompt
            } else if log.contains("Text AI Prompt:"),
                      let prompt = item.tempJsonRequests["textAIPrompt"], !prompt.isEmpty {
                return prompt
            }
            return extractFromLog()

        default:
            return ""
        }
    }

    private func extractFromLog() -> String {
        // Remove timestamp if present
        let cleanLog = log.replacingOccurrences(of: "\\[\\d{2}:\\d{2}:\\d{2}\\] ", with: "", options: .regularExpression)

        // Extract content after colon
        if let colonIndex = cleanLog.firstIndex(of: ":") {
            return String(cleanLog[cleanLog.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleanLog
    }

    private func getMaxHeight() -> CGFloat {
        switch logType {
        case .ocrExtracted, .ocrSelected:
            return 300
        case .visionAI, .textAI:
            return 250
        case .aiPrompt, .ocrPreview:
            return 150
        default:
            return 200
        }
    }
}

// Removed ActionButton struct as functionality is now integrated into LogEntryView

struct ResourceBarView: View {
    @ObservedObject var monitor: ResourceMonitor

    var body: some View {
        HStack(spacing: 20) {
            // CPU Usage with E/P cores
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(monitor.metrics.cpuString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Text("(\(monitor.metrics.cpuDetailString))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 12)

            // Memory
            HStack(spacing: 8) {
                Image(systemName: "memorychip")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(monitor.metrics.memoryString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }

            Divider()
                .frame(height: 12)

            // GPU
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(monitor.metrics.gpuString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }

            Divider()
                .frame(height: 12)

            // ANE (Neural Engine)
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(monitor.metrics.aneString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }

            Spacer()

            // Processing indicator
            if monitor.metrics.cpuUsageTotal > 5 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle()
                                .stroke(Color.green.opacity(0.3), lineWidth: 4)
                                .scaleEffect(1.5)
                                .opacity(0.5)
                                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: monitor.metrics.cpuUsageTotal)
                        )
                    Text("Processing")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Select a file from the queue")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}