import SwiftUI
import ScanOrganizerCore

struct ConfigView: View {
    @ObservedObject private var config = AppConfig.shared
    @State private var isLoadingModels = false
    @Environment(\.dismiss) private var dismiss

    private func getDisplayText(for modelTag: OllamaModelTag, latestConcreteTag: String?) -> String {
        var parts: [String] = []

        // Base tag name
        parts.append(modelTag.tag)

        // Add size and context
        var metadata: [String] = []
        if let size = modelTag.size {
            metadata.append(size)
        }
        if let context = modelTag.contextLength {
            metadata.append("\(context/1000)K")
        }

        // Build final string
        var result = modelTag.tag

        if !metadata.isEmpty {
            result += " (\(metadata.joined(separator: ", ")))"
        }

        // Add latest marker
        if modelTag.tag == "latest" {
            // "latest" tag: show "latest → 11b"
            if let concreteTag = latestConcreteTag {
                result += " → \(concreteTag)"
            }
        } else if modelTag.isLatest {
            // Concrete tag that is latest: show "11b → latest"
            result += " → latest"
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()

                    // Trigger recheck in main app
                    NotificationCenter.default.post(name: NSNotification.Name("RecheckSetup"), object: nil)
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            Form {
                // Notification Settings
                Section {
                    Toggle("Enable Notifications", isOn: $config.remindersEnabled)
                        .help("Show notifications when documents are processed")

                    if config.remindersEnabled {
                        Toggle("Play Sound", isOn: $config.reminderSound)
                            .help("Play a sound with notifications")
                            .padding(.leading, 20)

                        Toggle("Show Banner", isOn: $config.showNotificationBanner)
                            .help("Show in-app notification banner")
                            .padding(.leading, 20)

                        HStack {
                            Text("Reminder Delay (seconds):")
                                .help("Delay before the reminder alarm triggers")
                            Spacer()
                            TextField("", value: $config.reminderDelaySeconds, formatter: NumberFormatter())
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 60)
                            Text("sec")
                        }
                        .padding(.leading, 20)
                    }
                } header: {
                    Label("Notifications", systemImage: "bell")
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Divider()
                    .padding(.vertical, 8)

                // Ollama Model Settings
                Section {
                    // Vision Model
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Vision Model")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Spacer()

                            // Link to model page
                            if let model = config.availableVisionModels.first(where: { $0.name == config.selectedVisionModelBase }) {
                                Button(action: {
                                    if let url = URL(string: "https://ollama.com/library/\(model.name)/tags") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    Image(systemName: "link")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Open model page on ollama.com")
                            }
                        }

                        HStack(spacing: 8) {
                            Picker("Base Model:", selection: $config.selectedVisionModelBase) {
                                ForEach(config.availableVisionModels, id: \.name) { model in
                                    // Check if any version of this model is installed
                                    let hasLocalVersion = model.tags.contains { tag in
                                        config.installedModels.contains("\(model.name):\(tag.tag)")
                                    }

                                    if hasLocalVersion {
                                        Text("● \(model.name)").tag(model.name)
                                    } else {
                                        Text(model.name).tag(model.name)
                                    }
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 180)
                            .onChange(of: config.selectedVisionModelBase) {
                                // Reset tag to latest version for this model
                                if let model = config.availableVisionModels.first(where: { $0.name == config.selectedVisionModelBase }) {
                                    // Find the tag marked as latest, or use first tag as fallback
                                    if let latestTag = model.tags.first(where: { $0.isLatest }) {
                                        config.selectedVisionModelTag = latestTag.tag
                                    } else if let firstTag = model.tags.first {
                                        config.selectedVisionModelTag = firstTag.tag
                                    }
                                    // Update the full model string
                                    config.ollamaVisionModel = "\(config.selectedVisionModelBase):\(config.selectedVisionModelTag)"
                                }
                            }

                            if !config.availableVisionModels.isEmpty {
                                Picker("Tag:", selection: $config.selectedVisionModelTag) {
                                    if let model = config.availableVisionModels.first(where: { $0.name == config.selectedVisionModelBase }) {
                                        // Find which concrete version is the latest
                                        let latestConcreteTag = model.tags.first(where: { $0.isLatest })?.tag

                                        // Filter tags: hide "latest" if not installed
                                        let visibleTags = model.tags.filter { modelTag in
                                            if modelTag.tag == "latest" {
                                                let fullModel = "\(model.name):\(modelTag.tag)"
                                                return config.installedModels.contains(fullModel)
                                            }
                                            return true
                                        }

                                        ForEach(visibleTags, id: \.tag) { modelTag in
                                            let fullModel = "\(model.name):\(modelTag.tag)"
                                            let isInstalled = config.installedModels.contains(fullModel)
                                            let displayText = getDisplayText(for: modelTag, latestConcreteTag: latestConcreteTag)

                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack {
                                                    if isInstalled {
                                                        Text("● \(displayText)")
                                                    } else {
                                                        Text(displayText)
                                                    }

                                                    Spacer()
                                                }

                                                HStack(spacing: 6) {
                                                    Text(modelTag.size ?? "N/A")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)

                                                    Text("• \(modelTag.contextLength.map { "\($0/1000)K" } ?? "N/A")")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)

                                                    Text("• \(modelTag.inputTypes?.joined(separator: "+") ?? "N/A")")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)

                                                    Spacer()
                                                }
                                            }
                                            .tag(modelTag.tag)
                                            .foregroundColor(modelTag.isCompatible ? .primary : .secondary)
                                        }
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 250)
                                .onChange(of: config.selectedVisionModelTag) {
                                    config.ollamaVisionModel = "\(config.selectedVisionModelBase):\(config.selectedVisionModelTag)"
                                }
                            }
                        }

                        // Show details of selected tag
                        if let model = config.availableVisionModels.first(where: { $0.name == config.selectedVisionModelBase }),
                           let selectedTag = model.tags.first(where: { $0.tag == config.selectedVisionModelTag }) {
                            VStack(alignment: .leading, spacing: 4) {
                                // First row: Size, Context, Input
                                HStack(spacing: 8) {
                                    Text("Size: \(selectedTag.size ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("Context: \(selectedTag.contextLength.map { "\($0/1000)K" } ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("Input: \(selectedTag.inputTypes?.joined(separator: "+") ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                // Second row: Downloads, Updated, Digest
                                HStack(spacing: 8) {
                                    Text("Downloads: \(selectedTag.downloads ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("Updated: \(selectedTag.updated ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("Digest: \(selectedTag.digest ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 2)
                        }

                        if config.availableVisionModels.isEmpty {
                            Text("No models available")
                                .foregroundColor(.secondary)
                                .italic()
                                .font(.caption)
                        }
                    }
                    .help("Model used for image analysis and document understanding. ● = installed locally")

                    Divider()
                        .padding(.vertical, 4)

                    // Text Model
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Text Model")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Spacer()

                            // Link to model page
                            if let model = config.availableTextModels.first(where: { $0.name == config.selectedTextModelBase }) {
                                Button(action: {
                                    if let url = URL(string: "https://ollama.com/library/\(model.name)/tags") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    Image(systemName: "link")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Open model page on ollama.com")
                            }
                        }

                        HStack(spacing: 8) {
                            Picker("Base Model:", selection: $config.selectedTextModelBase) {
                                ForEach(config.availableTextModels, id: \.name) { model in
                                    // Check if any version of this model is installed
                                    let hasLocalVersion = model.tags.contains { tag in
                                        config.installedModels.contains("\(model.name):\(tag.tag)")
                                    }

                                    if hasLocalVersion {
                                        Text("● \(model.name)").tag(model.name)
                                    } else {
                                        Text(model.name).tag(model.name)
                                    }
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 180)
                            .onChange(of: config.selectedTextModelBase) {
                                // Reset tag to latest version for this model
                                if let model = config.availableTextModels.first(where: { $0.name == config.selectedTextModelBase }) {
                                    // Find the tag marked as latest, or use first tag as fallback
                                    if let latestTag = model.tags.first(where: { $0.isLatest }) {
                                        config.selectedTextModelTag = latestTag.tag
                                    } else if let firstTag = model.tags.first {
                                        config.selectedTextModelTag = firstTag.tag
                                    }
                                    // Update the full model string
                                    config.ollamaTextModel = "\(config.selectedTextModelBase):\(config.selectedTextModelTag)"
                                }
                            }

                            if !config.availableTextModels.isEmpty {
                                Picker("Tag:", selection: $config.selectedTextModelTag) {
                                    if let model = config.availableTextModels.first(where: { $0.name == config.selectedTextModelBase }) {
                                        // Find which concrete version is the latest
                                        let latestConcreteTag = model.tags.first(where: { $0.isLatest })?.tag

                                        // Filter tags: hide "latest" if not installed
                                        let visibleTags = model.tags.filter { modelTag in
                                            if modelTag.tag == "latest" {
                                                let fullModel = "\(model.name):\(modelTag.tag)"
                                                return config.installedModels.contains(fullModel)
                                            }
                                            return true
                                        }

                                        ForEach(visibleTags, id: \.tag) { modelTag in
                                            let fullModel = "\(model.name):\(modelTag.tag)"
                                            let isInstalled = config.installedModels.contains(fullModel)
                                            let displayText = getDisplayText(for: modelTag, latestConcreteTag: latestConcreteTag)

                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack {
                                                    if isInstalled {
                                                        Text("● \(displayText)")
                                                    } else {
                                                        Text(displayText)
                                                    }

                                                    Spacer()
                                                }

                                                HStack(spacing: 6) {
                                                    Text(modelTag.size ?? "N/A")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)

                                                    Text("• \(modelTag.contextLength.map { "\($0/1000)K" } ?? "N/A")")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)

                                                    Text("• \(modelTag.inputTypes?.joined(separator: "+") ?? "N/A")")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)

                                                    Spacer()
                                                }
                                            }
                                            .tag(modelTag.tag)
                                            .foregroundColor(modelTag.isCompatible ? .primary : .secondary)
                                        }
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 250)
                                .onChange(of: config.selectedTextModelTag) {
                                    config.ollamaTextModel = "\(config.selectedTextModelBase):\(config.selectedTextModelTag)"
                                }
                            }
                        }

                        // Show details of selected tag
                        if let model = config.availableTextModels.first(where: { $0.name == config.selectedTextModelBase }),
                           let selectedTag = model.tags.first(where: { $0.tag == config.selectedTextModelTag }) {
                            VStack(alignment: .leading, spacing: 4) {
                                // First row: Size, Context, Input
                                HStack(spacing: 8) {
                                    Text("Size: \(selectedTag.size ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("Context: \(selectedTag.contextLength.map { "\($0/1000)K" } ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("Input: \(selectedTag.inputTypes?.joined(separator: "+") ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                // Second row: Downloads, Updated, Digest
                                HStack(spacing: 8) {
                                    Text("Downloads: \(selectedTag.downloads ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("Updated: \(selectedTag.updated ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("Digest: \(selectedTag.digest ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 2)
                        }

                        if config.availableTextModels.isEmpty {
                            Text("No models available")
                                .foregroundColor(.secondary)
                                .italic()
                                .font(.caption)
                        }
                    }
                    .help("Model used for text analysis and information extraction. ● = installed locally")

                    Divider()
                        .padding(.vertical, 4)

                    VStack(spacing: 8) {
                        if isLoadingModels {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                                Text("Loading online model data... Using local/cached models in the meantime.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }

                        HStack {
                            Spacer()

                            Button(action: {
                                Task {
                                    isLoadingModels = true
                                    await config.loadAvailableModels(forceRefresh: true)
                                    isLoadingModels = false
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh Models")
                            }
                            .disabled(isLoadingModels)
                            .help("Refresh models from Ollama website and reload local models")

                            Button(action: {
                                OllamaModelFetcher.shared.clearCache()
                                config.loadInstalledModelsOnly()
                            }) {
                                Image(systemName: "trash")
                                Text("Clear Cache")
                            }
                            .help("Clear online cache and show only locally installed models")

                            Button("Reset to Defaults") {
                                config.resetToDefaults()
                            }
                        }
                    }
                    .padding(.top, 8)

                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Ollama Models", systemImage: "cpu")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("● = locally installed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // AI Prompts Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        // Vision Prompt
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Vision Prompt:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("Placeholders: {TEXT_EXCERPT}")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            TextEditor(text: $config.visionPrompt)
                                .font(.system(.caption, design: .monospaced))
                                .frame(height: 120)
                                .border(Color.gray.opacity(0.3), width: 1)
                                .help("Prompt for vision model analysis. Use {TEXT_EXCERPT} as placeholder.")
                        }

                        // Text Prompt
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Text Prompt:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("Placeholders: {VISION_DESCRIPTION}, {TEXT_EXCERPT}, {FILE_DATE}, {LANGUAGE}")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            TextEditor(text: $config.textPrompt)
                                .font(.system(.caption, design: .monospaced))
                                .frame(height: 150)
                                .border(Color.gray.opacity(0.3), width: 1)
                                .help("Prompt for text analysis. Available placeholders: {VISION_DESCRIPTION}, {TEXT_EXCERPT}, {FILE_DATE}, {LANGUAGE}")
                        }

                        HStack {
                            Spacer()
                            Button("Reset Prompts to Default") {
                                config.visionPrompt = AppConfig.defaultVisionPrompt
                                config.textPrompt = AppConfig.defaultTextPrompt
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("AI Prompts", systemImage: "text.quote")
                        .font(.headline)
                        .foregroundColor(.primary)
                }


                // Debug Settings
                Section {
                    Toggle("Enable Debug Mode", isOn: $config.debugEnabled)
                        .help("Enable debug logging to console")

                    if config.debugEnabled {
                        Toggle("Resource Monitor", isOn: $config.debugResourceMonitor)
                            .help("Show CPU, Memory, GPU, ANE debug logs")
                            .padding(.leading, 20)

                        Toggle("PDF Processor", isOn: $config.debugPDFProcessor)
                            .help("Show PDF processing debug logs")
                            .padding(.leading, 20)

                        Toggle("AI Classifier", isOn: $config.debugAIClassifier)
                            .help("Show AI classification debug logs")
                            .padding(.leading, 20)

                        Toggle("OCR Service", isOn: $config.debugOCRService)
                            .help("Show OCR extraction debug logs")
                            .padding(.leading, 20)

                        Toggle("File Organizer", isOn: $config.debugFileOrganizer)
                            .help("Show file organization debug logs")
                            .padding(.leading, 20)

                        Toggle("Notification Service", isOn: $config.debugNotificationService)
                            .help("Show notification debug logs")
                            .padding(.leading, 20)
                    }
                } header: {
                    Label("Debug", systemImage: "ladybug")
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                // Status Section
                Section {
                    HStack {
                        Circle()
                            .fill(isOllamaRunning() ? Color.green : Color.red)
                            .frame(width: 8, height: 8)

                        Text(isOllamaRunning() ? "Ollama is running" : "Ollama is not running")
                            .foregroundColor(.secondary)

                        Spacer()

                        if !isOllamaRunning() {
                            Link("Install Ollama", destination: URL(string: "https://ollama.ai")!)
                                .font(.caption)
                        }
                    }

                    if !config.availableVisionModels.isEmpty || !config.availableTextModels.isEmpty {
                        Text("Available Models: \(config.availableVisionModels.count + config.availableTextModels.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Status", systemImage: "info.circle")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            }
            .formStyle(.grouped)
            .padding()
            .frame(maxHeight: .infinity)

            Divider()

            // Footer
            HStack {
                Text("Changes are saved automatically")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            isLoadingModels = true
            await config.loadAvailableModels()
            isLoadingModels = false
        }
    }

    private func isOllamaRunning() -> Bool {
        // Simple check if Ollama is accessible
        return !config.availableVisionModels.isEmpty || !config.availableTextModels.isEmpty
    }
}