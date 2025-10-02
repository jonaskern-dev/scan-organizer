import AppKit
import SwiftUI

@MainActor
class SetupWindowController: NSWindowController {
    let viewModel: SetupViewModel

    init(viewModel: SetupViewModel) {
        self.viewModel = viewModel

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Setup Scan Organizer"
        window.center()
        window.isReleasedWhenClosed = false

        let setupView = SetupView(viewModel: viewModel)
        window.contentView = NSHostingView(rootView: setupView)

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct SetupView: View {
    @ObservedObject var viewModel: SetupViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
                    .padding(.top, 20)

                Text("Welcome to Scan Organizer")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Let's set up your AI document processing")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
            }

            Divider()

            // Requirements
            VStack(alignment: .leading, spacing: 16) {
                SetupRequirement(
                    title: "Ollama",
                    description: "AI runtime environment",
                    status: viewModel.ollamaStatus,
                    action: viewModel.installOllama
                )

                SetupRequirement(
                    title: "Ollama Service",
                    description: "Background service running",
                    status: viewModel.serviceStatus,
                    action: viewModel.startService
                )

                SetupRequirement(
                    title: "Vision Model",
                    description: viewModel.visionModelDescription,
                    status: viewModel.visionModelStatus,
                    action: viewModel.downloadVisionModel
                )

                SetupRequirement(
                    title: "Text Model",
                    description: viewModel.textModelDescription,
                    status: viewModel.textModelStatus,
                    action: viewModel.downloadTextModel
                )
            }
            .padding(20)

            Spacer()

            // Progress
            if viewModel.isProcessing {
                VStack(spacing: 8) {
                    if viewModel.showProgress {
                        ProgressView(value: viewModel.downloadProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(width: 400)
                    } else {
                        ProgressView()
                    }
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 16)
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                if viewModel.showQuitButton {
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                }

                Button("Settings") {
                    viewModel.openSettings()
                }
                .disabled(viewModel.isProcessing)

                Spacer()

                if viewModel.canInstallAll {
                    Button("Install All") {
                        Task {
                            await viewModel.installAll()
                        }
                    }
                    .disabled(viewModel.isProcessing)
                }

                if viewModel.allComplete {
                    Button(viewModel.continueButtonText) {
                        viewModel.completeSetup()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
        .frame(width: 520, height: 600)
        .onAppear {
            Task {
                await viewModel.checkStatus()
            }
        }
    }
}

struct SetupRequirement: View {
    let title: String
    let description: String
    let status: SetupStatus
    let action: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: status.icon)
                .font(.system(size: 24))
                .foregroundColor(status.color)
                .frame(width: 30)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Action button
            if status == .missing || status == .error {
                Button("Install") {
                    Task {
                        await action()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

enum SetupStatus {
    case checking
    case complete
    case missing
    case error
    case installing

    var icon: String {
        switch self {
        case .checking: return "hourglass"
        case .complete: return "checkmark.circle.fill"
        case .missing: return "xmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .installing: return "arrow.down.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .checking: return .gray
        case .complete: return .green
        case .missing: return .red
        case .error: return .orange
        case .installing: return .blue
        }
    }
}

@MainActor
class SetupViewModel: ObservableObject {
    @Published var ollamaStatus: SetupStatus = .checking
    @Published var serviceStatus: SetupStatus = .checking
    @Published var visionModelStatus: SetupStatus = .checking
    @Published var textModelStatus: SetupStatus = .checking
    @Published var isProcessing = false
    @Published var statusMessage = ""
    @Published var downloadProgress: Double = 0.0
    @Published var showProgress = false

    var isFirstRun = false

    var visionModelDescription: String {
        AppConfig.shared.ollamaVisionModel
    }

    var textModelDescription: String {
        AppConfig.shared.ollamaTextModel
    }

    var allComplete: Bool {
        ollamaStatus == .complete &&
        serviceStatus == .complete &&
        visionModelStatus == .complete &&
        textModelStatus == .complete
    }

    var canInstallAll: Bool {
        !isProcessing && !allComplete
    }

    var showQuitButton: Bool {
        // Only show quit button when opened automatically due to missing requirements
        !isProcessing && isFirstRun
    }

    var continueButtonText: String {
        isFirstRun ? "Get Started" : "Continue"
    }

    private var onComplete: (() -> Void)?
    private var onOpenSettings: (() -> Void)?

    func setCompletionHandler(_ handler: @escaping () -> Void) {
        onComplete = handler
    }

    func setOpenSettingsHandler(_ handler: @escaping () -> Void) {
        onOpenSettings = handler
    }

    func openSettings() {
        onOpenSettings?()
    }

    func checkStatus() async {
        await checkOllama()
        await checkService()
        await checkVisionModel()
        await checkTextModel()
    }

    func checkOllama() async {
        ollamaStatus = .checking
        let installed = await FirstRunSetup.checkRequirementOllamaInstalled()
        ollamaStatus = installed ? .complete : .missing
    }

    func checkService() async {
        serviceStatus = .checking
        let running = await FirstRunSetup.checkRequirementServiceRunning()
        serviceStatus = running ? .complete : .missing
    }

    func checkVisionModel() async {
        visionModelStatus = .checking
        let (visionInstalled, _) = AppConfig.shared.areSelectedModelsInstalled()
        visionModelStatus = visionInstalled ? .complete : .missing
    }

    func checkTextModel() async {
        textModelStatus = .checking
        let (_, textInstalled) = AppConfig.shared.areSelectedModelsInstalled()
        textModelStatus = textInstalled ? .complete : .missing
    }

    func installOllama() async {
        isProcessing = true
        ollamaStatus = .installing
        statusMessage = "Installing Ollama via Homebrew..."

        let success = await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew")
            process.arguments = ["install", "ollama"]

            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value

        if success {
            await checkOllama()
            await startService()
        } else {
            ollamaStatus = .error
        }

        isProcessing = false
        statusMessage = ""
    }

    func startService() async {
        isProcessing = true
        serviceStatus = .installing
        statusMessage = "Starting Ollama service..."

        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew")
            process.arguments = ["services", "start", "ollama"]

            do {
                try process.run()
                process.waitUntilExit()

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                await MainActor.run {
                    self.serviceStatus = .error
                }
            }
        }.value

        await checkService()

        isProcessing = false
        statusMessage = ""
    }

    func downloadVisionModel() async {
        isProcessing = true
        visionModelStatus = .installing
        showProgress = true
        downloadProgress = 0.0

        let visionModel = AppConfig.shared.ollamaVisionModel
        statusMessage = "Downloading \(visionModel)..."
        let downloadSuccess = await downloadModel(visionModel, progressStart: 0.0, progressEnd: 0.9)

        if downloadSuccess {
            statusMessage = "Verifying \(visionModel)..."
            downloadProgress = 0.95
            let verified = await verifyModel(visionModel)

            if !verified {
                // Remove corrupted model and retry once
                statusMessage = "Download corrupted. Removing and retrying..."
                await removeModel(visionModel)

                // Retry download
                let retrySuccess = await downloadModel(visionModel, progressStart: 0.0, progressEnd: 0.9)
                if retrySuccess {
                    statusMessage = "Verifying \(visionModel)..."
                    downloadProgress = 0.95
                    let retryVerified = await verifyModel(visionModel)

                    if !retryVerified {
                        visionModelStatus = .error
                        statusMessage = "Verification failed after retry. Please check your internet connection."
                        await MainActor.run {
                            self.downloadProgress = 0.0
                        }
                        isProcessing = false
                        showProgress = false
                        return
                    }
                } else {
                    visionModelStatus = .error
                    statusMessage = "Download failed. Please try again."
                    await MainActor.run {
                        self.downloadProgress = 0.0
                    }
                    isProcessing = false
                    showProgress = false
                    return
                }
            }
        }

        // Restart Ollama service to load new model
        statusMessage = "Restarting Ollama service..."
        await restartOllamaService()

        // Reload installed models from Ollama API
        await MainActor.run {
            AppConfig.shared.loadInstalledModels()
        }

        await checkVisionModel()

        isProcessing = false
        showProgress = false
        statusMessage = ""
        downloadProgress = 0.0
    }

    func downloadTextModel() async {
        isProcessing = true
        textModelStatus = .installing
        showProgress = true
        downloadProgress = 0.0

        let textModel = AppConfig.shared.ollamaTextModel
        statusMessage = "Downloading \(textModel)..."
        let downloadSuccess = await downloadModel(textModel, progressStart: 0.0, progressEnd: 0.9)

        if downloadSuccess {
            statusMessage = "Verifying \(textModel)..."
            downloadProgress = 0.95
            let verified = await verifyModel(textModel)

            if !verified {
                // Remove corrupted model and retry once
                statusMessage = "Download corrupted. Removing and retrying..."
                await removeModel(textModel)

                // Retry download
                let retrySuccess = await downloadModel(textModel, progressStart: 0.0, progressEnd: 0.9)
                if retrySuccess {
                    statusMessage = "Verifying \(textModel)..."
                    downloadProgress = 0.95
                    let retryVerified = await verifyModel(textModel)

                    if !retryVerified {
                        textModelStatus = .error
                        statusMessage = "Verification failed after retry. Please check your internet connection."
                        await MainActor.run {
                            self.downloadProgress = 0.0
                        }
                        isProcessing = false
                        showProgress = false
                        return
                    }
                } else {
                    textModelStatus = .error
                    statusMessage = "Download failed. Please try again."
                    await MainActor.run {
                        self.downloadProgress = 0.0
                    }
                    isProcessing = false
                    showProgress = false
                    return
                }
            }
        }

        // Restart Ollama service to load new model
        statusMessage = "Restarting Ollama service..."
        await restartOllamaService()

        // Reload installed models from Ollama API
        await MainActor.run {
            AppConfig.shared.loadInstalledModels()
        }

        await checkTextModel()

        isProcessing = false
        showProgress = false
        statusMessage = ""
        downloadProgress = 0.0
    }

    private func downloadModel(_ model: String, progressStart: Double, progressEnd: Double) async -> Bool {
        // Find ollama path
        let possiblePaths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/usr/bin/ollama"
        ]

        guard let ollamaPath = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return false
        }

        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ollamaPath)
            process.arguments = ["pull", model]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            // Read output asynchronously
            let outputHandle = pipe.fileHandleForReading
            var outputData = Data()
            var hasSuccess = false

            do {
                try process.run()

                // Update progress periodically while process runs
                while process.isRunning {
                    let data = outputHandle.availableData
                    if !data.isEmpty {
                        outputData.append(data)

                        // Parse progress from output if available
                        if let output = String(data: data, encoding: .utf8) {
                            await self.parseDownloadProgress(output, start: progressStart, end: progressEnd)

                            // Check for success message
                            if output.contains("success") {
                                hasSuccess = true
                            }
                        }
                    }
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                }

                process.waitUntilExit()

                // Set to end progress when done
                await MainActor.run {
                    self.downloadProgress = progressEnd
                }

                // Success only if exit code 0 AND we saw "success" message
                return process.terminationStatus == 0 && hasSuccess
            } catch {
                return false
            }
        }.value
    }

    private func parseDownloadProgress(_ output: String, start: Double, end: Double) {
        // Parse ollama output for progress (e.g., "pulling... 45%")
        let range = end - start

        if let percentMatch = output.range(of: #"(\d+)%"#, options: .regularExpression) {
            let percentString = output[percentMatch].replacingOccurrences(of: "%", with: "")
            if let percent = Double(percentString) {
                downloadProgress = start + (percent / 100.0 * range)
            }
        } else if output.contains("pulling manifest") {
            downloadProgress = start + (0.05 * range)
        } else if output.contains("verifying sha256") {
            downloadProgress = start + (0.95 * range)
        } else if output.contains("success") {
            downloadProgress = end
        }
    }

    private func verifyModel(_ model: String) async -> Bool {
        // Verify model is listed in Ollama's model list
        guard let url = URL(string: "http://localhost:11434/api/tags") else {
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                return false
            }

            // Check if model exists in list
            let modelExists = models.contains { modelInfo in
                if let name = modelInfo["name"] as? String {
                    return name.lowercased() == model.lowercased()
                }
                return false
            }

            return modelExists
        } catch {
            return false
        }
    }

    private func removeModel(_ model: String) async {
        let possiblePaths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/usr/bin/ollama"
        ]

        guard let ollamaPath = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return
        }

        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ollamaPath)
            process.arguments = ["rm", model]

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Silent failure
            }
        }.value
    }

    private func restartOllamaService() async {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew")
            process.arguments = ["services", "restart", "ollama"]

            do {
                try process.run()
                process.waitUntilExit()
                // Wait a bit for service to fully restart
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            } catch {
                // Silent failure
            }
        }.value
    }

    func installAll() async {
        if ollamaStatus != .complete {
            await installOllama()
        }

        if serviceStatus != .complete {
            await startService()
        }

        var modelsWereDownloaded = false

        if visionModelStatus != .complete {
            await downloadVisionModel()
            modelsWereDownloaded = true
        }

        if textModelStatus != .complete {
            await downloadTextModel()
            modelsWereDownloaded = true
        }

        // Restart Ollama service after model downloads to ensure they are loaded
        if modelsWereDownloaded {
            statusMessage = "Restarting Ollama service..."
            await restartOllamaService()
            statusMessage = ""
        }
    }

    func completeSetup() {
        onComplete?()
    }
}
