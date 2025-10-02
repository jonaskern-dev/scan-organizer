import Foundation
import AppKit
import SwiftUI

public class FirstRunSetup {
    public static let shared = FirstRunSetup()

    private var setupWindowController: SetupWindowController?

    private init() {}

    // Shared check methods - these are used by both FirstRunSetup and SetupWindow
    // to ensure consistency
    public static func checkRequirementOllamaInstalled() async -> Bool {
        // Check if Ollama API is reachable - this is the most reliable way
        // Works regardless of installation method (Homebrew, binary, Docker, etc.)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-s",                          // silent
            "--max-time", "2",             // 2 second timeout
            "--fail",                      // fail on HTTP errors
            "http://localhost:11434/api/tags"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let result = process.terminationStatus == 0

            // If API is reachable, Ollama is definitely installed and running
            if result {
                return true
            }

            // API not reachable - check if ollama binary exists anywhere
            // This handles the case where Ollama is installed but not running
            let possiblePaths = [
                "/usr/local/bin/ollama",
                "/opt/homebrew/bin/ollama",
                "/usr/bin/ollama",
                "/Applications/Ollama.app/Contents/Resources/ollama"
            ]

            for path in possiblePaths {
                if FileManager.default.fileExists(atPath: path) {
                    return true  // Installed but service not running
                }
            }

            return false
        } catch {
            return false
        }
    }

    public static func checkRequirementServiceRunning() async -> Bool {
        // Check if Ollama service is running by calling the API
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-s",                          // silent
            "--max-time", "2",             // 2 second timeout
            "--fail",                      // fail on HTTP errors
            "http://localhost:11434/api/tags"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public static func checkRequirementModelsInstalled() async -> Bool {
        // Check if service is running - we need the API to check models
        let serviceRunning = await checkRequirementServiceRunning()
        guard serviceRunning else {
            return false
        }

        // Use Ollama API to get list of installed models
        // This works regardless of how Ollama was installed
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-s",                          // silent
            "--max-time", "5",             // 5 second timeout
            "http://localhost:11434/api/tags"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return false
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = jsonData["models"] as? [[String: Any]] else {
                return false
            }

            // Extract model names
            var installedModels: Set<String> = []
            for model in models {
                if let name = model["name"] as? String {
                    installedModels.insert(name.lowercased())
                }
            }

            // Get the selected models from AppConfig
            let selectedVisionModel = await MainActor.run { AppConfig.shared.ollamaVisionModel.lowercased() }
            let selectedTextModel = await MainActor.run { AppConfig.shared.ollamaTextModel.lowercased() }

            // Check if the specifically selected models are installed
            let hasVisionModel = installedModels.contains(selectedVisionModel)
            let hasTextModel = installedModels.contains(selectedTextModel)

            return hasVisionModel && hasTextModel
        } catch {
            return false
        }
    }

    public func checkAndRunSetup(completion: @escaping (Bool) -> Void) {
        Task {
            let needsSetup = await performFirstRunSetup()

            await MainActor.run {
                // Only show setup window if something is missing
                if needsSetup {
                    showSetupWindow(isFirstRun: true, completion: completion)
                } else {
                    // Everything is configured, continue normally
                    completion(true)
                }
            }
        }
    }

    @MainActor
    public func showSetupWindowManually() {
        let viewModel = SetupViewModel()
        viewModel.isFirstRun = false
        viewModel.setCompletionHandler {
            self.setupWindowController?.close()
            self.setupWindowController = nil
        }
        viewModel.setOpenSettingsHandler {
            // Close setup window and open settings
            self.setupWindowController?.close()
            self.setupWindowController = nil

            // Post notification to open settings
            NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
        }

        setupWindowController = SetupWindowController(viewModel: viewModel)
        setupWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func performFirstRunSetup() async -> Bool {
        let ollamaInstalled = await Self.checkRequirementOllamaInstalled()
        let serviceRunning = await Self.checkRequirementServiceRunning()
        let modelsInstalled = await Self.checkRequirementModelsInstalled()

        return !ollamaInstalled || !serviceRunning || !modelsInstalled
    }

    @MainActor
    private func showSetupWindow(isFirstRun: Bool, completion: @escaping (Bool) -> Void) {
        let viewModel = SetupViewModel()
        viewModel.isFirstRun = isFirstRun
        viewModel.setCompletionHandler {
            self.setupWindowController?.close()
            self.setupWindowController = nil
            completion(true)
        }
        viewModel.setOpenSettingsHandler {
            // Close setup window and open settings
            self.setupWindowController?.close()
            self.setupWindowController = nil

            // Post notification to open settings
            NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
        }

        setupWindowController = SetupWindowController(viewModel: viewModel)
        setupWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }


    private func showSetupDialog(ollamaInstalled: Bool, modelsInstalled: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .informational

        if !ollamaInstalled {
            alert.messageText = "Ollama Not Installed"
            alert.informativeText = "Scan Organizer requires Ollama for AI processing.\n\nPlease install it via Homebrew:\n  brew install ollama\n\nThen restart Scan Organizer."
            alert.addButton(withTitle: "Quit")
            alert.runModal()
        } else if !modelsInstalled {
            alert.messageText = "AI Models Required"
            alert.informativeText = """
            Scan Organizer needs to download AI models for document processing:

            • llama3.2-vision:latest (7.8 GB - Image Analysis)
            • granite3.3:latest (4.9 GB - Text Extraction)

            Total download size: ~12.7 GB
            Estimated time: 10-20 minutes (depending on connection)

            The app will be unavailable until installation completes.
            """

            alert.addButton(withTitle: "Download Models")
            alert.addButton(withTitle: "Quit")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Task {
                    await ensureOllamaServiceRunning()
                    await installModelsWithProgress()
                }
            }
        }
    }

    private func ensureOllamaServiceRunning() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew")
        process.arguments = ["services", "start", "ollama"]

        do {
            try process.run()
            process.waitUntilExit()
            // Give Ollama a moment to start
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        } catch {
            print("Failed to start Ollama service: \(error)")
        }
    }

    private func installModelsWithProgress() async {
        let progressWindow = await MainActor.run { () -> NSWindow in
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.title = "Installing AI Models"
            window.center()
            window.isReleasedWhenClosed = false

            let contentView = NSView(frame: window.contentView!.bounds)

            let statusLabel = NSTextField(labelWithString: "Preparing download...")
            statusLabel.frame = NSRect(x: 20, y: 120, width: 360, height: 40)
            statusLabel.font = .systemFont(ofSize: 14)
            statusLabel.alignment = .center
            contentView.addSubview(statusLabel)

            let progressIndicator = NSProgressIndicator(frame: NSRect(x: 50, y: 80, width: 300, height: 20))
            progressIndicator.isIndeterminate = false
            progressIndicator.minValue = 0
            progressIndicator.maxValue = 2
            progressIndicator.doubleValue = 0
            contentView.addSubview(progressIndicator)

            let detailLabel = NSTextField(labelWithString: "")
            detailLabel.frame = NSRect(x: 20, y: 40, width: 360, height: 30)
            detailLabel.font = .systemFont(ofSize: 12)
            detailLabel.alignment = .center
            detailLabel.textColor = .secondaryLabelColor
            contentView.addSubview(detailLabel)

            window.contentView = contentView
            window.makeKeyAndOrderFront(nil)

            return window
        }

        // Download vision model
        await MainActor.run {
            if let contentView = progressWindow.contentView {
                (contentView.subviews[0] as? NSTextField)?.stringValue = "Downloading llama3.2-vision..."
                (contentView.subviews[2] as? NSTextField)?.stringValue = "This may take several minutes"
            }
        }

        await downloadModel("llama3.2-vision:latest")

        await MainActor.run {
            if let contentView = progressWindow.contentView {
                (contentView.subviews[1] as? NSProgressIndicator)?.doubleValue = 1
            }
        }

        // Download text model
        await MainActor.run {
            if let contentView = progressWindow.contentView {
                (contentView.subviews[0] as? NSTextField)?.stringValue = "Downloading granite3.3..."
            }
        }

        await downloadModel("granite3.3:latest")

        await MainActor.run {
            if let contentView = progressWindow.contentView {
                (contentView.subviews[1] as? NSProgressIndicator)?.doubleValue = 2
                (contentView.subviews[0] as? NSTextField)?.stringValue = "Installation complete!"
                (contentView.subviews[2] as? NSTextField)?.stringValue = ""
            }
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        await MainActor.run {
            progressWindow.close()
        }

        await showCompletionDialog()
    }

    private func downloadModel(_ model: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ollama")
        process.arguments = ["pull", model]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Failed to download model \(model): \(error)")
        }
    }

    private func showCompletionDialog() async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Setup Complete"
            alert.informativeText = "Ollama and AI models have been installed.\nYou can now use Scan Organizer!"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    public func resetFirstRun() {
        // No longer needed - setup window only shows when something is missing
    }
}
