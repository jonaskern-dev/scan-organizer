import Foundation
import Combine

public class AppConfig: ObservableObject {
    public static let shared = AppConfig()

    // Configuration keys
    private enum ConfigKey: String {
        case remindersEnabled = "remindersEnabled"
        case ollamaVisionModel = "ollamaVisionModel"
        case ollamaTextModel = "ollamaTextModel"
        case reminderSound = "reminderSound"
        case showNotificationBanner = "showNotificationBanner"
        case reminderDelaySeconds = "reminderDelaySeconds"
        case visionPrompt = "visionPrompt"
        case textPrompt = "textPrompt"
    }

    // Published properties for UI binding
    @Published public var remindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(remindersEnabled, forKey: ConfigKey.remindersEnabled.rawValue)
        }
    }

    @Published public var ollamaVisionModel: String {
        didSet {
            UserDefaults.standard.set(ollamaVisionModel, forKey: ConfigKey.ollamaVisionModel.rawValue)
        }
    }

    @Published public var ollamaTextModel: String {
        didSet {
            UserDefaults.standard.set(ollamaTextModel, forKey: ConfigKey.ollamaTextModel.rawValue)
        }
    }

    @Published public var reminderSound: Bool {
        didSet {
            UserDefaults.standard.set(reminderSound, forKey: ConfigKey.reminderSound.rawValue)
        }
    }

    @Published public var showNotificationBanner: Bool {
        didSet {
            UserDefaults.standard.set(showNotificationBanner, forKey: ConfigKey.showNotificationBanner.rawValue)
        }
    }

    @Published public var reminderDelaySeconds: Int {  // 40 seconds default
        didSet {
            UserDefaults.standard.set(reminderDelaySeconds, forKey: ConfigKey.reminderDelaySeconds.rawValue)
        }
    }

    @Published public var visionPrompt: String {
        didSet {
            UserDefaults.standard.set(visionPrompt, forKey: ConfigKey.visionPrompt.rawValue)
            UserDefaults.standard.synchronize()
        }
    }

    @Published public var textPrompt: String {
        didSet {
            UserDefaults.standard.set(textPrompt, forKey: ConfigKey.textPrompt.rawValue)
            UserDefaults.standard.synchronize()
        }
    }

    // Default models (always available, even if not installed)
    public static let defaultVisionModel = OllamaModel(
        name: "granite3.2-vision",
        tags: [OllamaModelTag(tag: "2b", isLatest: false, isCompatible: true)],
        isVision: true
    )

    public static let defaultTextModel = OllamaModel(
        name: "granite3.3",
        tags: [OllamaModelTag(tag: "2b", isLatest: false, isCompatible: true)],
        isVision: false
    )

    // Available models (will be populated from Ollama)
    @Published public var availableVisionModels: [OllamaModel] = [defaultVisionModel]
    @Published public var availableTextModels: [OllamaModel] = [defaultTextModel]
    @Published public var installedModels: Set<String> = []

    // Selected model base names (without tag)
    @Published public var selectedVisionModelBase: String = "granite3.2-vision"
    @Published public var selectedTextModelBase: String = "granite3.3"

    // Selected model tags
    @Published public var selectedVisionModelTag: String = "latest"
    @Published public var selectedTextModelTag: String = "latest"

    // Default prompts - improved versions
    public static let defaultVisionPrompt = """
    Analyze this document image.

    OCR text excerpt:
    {TEXT_EXCERPT}

    Provide:
    1. First state: LANGUAGE: GERMAN or LANGUAGE: ENGLISH etc.
    2. Document type
    3. Main title: Primary heading reflecting the document type
       (largest/bold text, ignore auxiliary elements like page numbers/headers)
    4. Primary purpose

    Start your response with the language.
    """

    public static let defaultTextPrompt = """
    Analyze document and extract key components.

    Vision AI description:
    {VISION_DESCRIPTION}

    OCR text:
    {TEXT_EXCERPT}

    File creation date (fallback): {FILE_DATE}

    Date rules:
    - If you find full date: use it
    - If you find month/year: use first day
    - If you find year only: use YYYY-01-01
    - If no date found: use {FILE_DATE}

    DOCUMENT LANGUAGE: {LANGUAGE}

    Return JSON with these fields:
    - date: document date in YYYY-MM-DD format (following rules above)
    - title: main description IN {LANGUAGE} LANGUAGE - MUST BE NORMALIZED
    - type: [Keyword] - Use most specific applicable English term. Compound nouns allowed. Single phrase only, no explanatory text.
    - components: array with max 5 important identifiers FOR THE FILENAME

    CRITICAL for title field:
    - NEVER copy ALL CAPS text directly from document
    - ALWAYS normalize to standard {LANGUAGE} capitalization
    - Capitalize first letter after each hyphen
    - Keep only real acronyms in uppercase

    Component structure: {"label": "field name", "value": "content", "confidence": 0.0-1.0}

    Confidence scoring:

    1.0: Critical identifiers - unique to this specific document instance, essential for differentiation
    0.8: High-value metadata - key contextual information that aids document classification and retrieval
    0.5: Supporting details - supplementary information with moderate utility
    0.3: Low utility - generic, repetitive, or decorative content

    IMPORTANT:
    - Labels in English
    - Values in document's language
    - No individual times or repetitive details

    Generate complete, valid JSON only:
    """

    private init() {
        // Load saved configuration or use defaults
        self.remindersEnabled = UserDefaults.standard.object(forKey: ConfigKey.remindersEnabled.rawValue) as? Bool ?? true
        self.ollamaVisionModel = UserDefaults.standard.string(forKey: ConfigKey.ollamaVisionModel.rawValue) ?? "granite3.2-vision:2b"
        self.ollamaTextModel = UserDefaults.standard.string(forKey: ConfigKey.ollamaTextModel.rawValue) ?? "granite3.3:2b"
        self.reminderSound = UserDefaults.standard.object(forKey: ConfigKey.reminderSound.rawValue) as? Bool ?? true
        self.showNotificationBanner = UserDefaults.standard.object(forKey: ConfigKey.showNotificationBanner.rawValue) as? Bool ?? true
        self.reminderDelaySeconds = UserDefaults.standard.object(forKey: ConfigKey.reminderDelaySeconds.rawValue) as? Int ?? 40  // 40 seconds default
        self.visionPrompt = UserDefaults.standard.string(forKey: ConfigKey.visionPrompt.rawValue) ?? Self.defaultVisionPrompt
        self.textPrompt = UserDefaults.standard.string(forKey: ConfigKey.textPrompt.rawValue) ?? Self.defaultTextPrompt

        // Fetch available models
        Task {
            await loadAvailableModels()
        }
    }

    // Load locally installed models immediately
    @MainActor
    public func loadInstalledModels() {
        var allInstalledModels: Set<String> = []
        var modelDetails: [String: (size: Int64, details: [String: Any])] = [:]

        // Get installed models from local Ollama API
        if let url = URL(string: "http://localhost:11434/api/tags") {
            do {
                let data = try Data(contentsOf: url)

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["models"] as? [[String: Any]] {

                    for model in models {
                        if let name = model["name"] as? String {
                            allInstalledModels.insert(name)

                            // Extract size (in bytes)
                            if let size = model["size"] as? Int64 {
                                modelDetails[name] = (size: size, details: model)
                            }
                        }
                    }
                }
            } catch {
                // Silent failure - will retry on next load
            }
        }

        self.installedModels = allInstalledModels

        // Create basic models from installed ones if no online data available yet
        if availableVisionModels.isEmpty && availableTextModels.isEmpty {
            createModelsFromInstalled(allInstalledModels, modelDetails: modelDetails)
        }
    }

    // Load only locally installed models (clear online cache)
    @MainActor
    public func loadInstalledModelsOnly() {
        var allInstalledModels: Set<String> = []
        var modelDetails: [String: (size: Int64, details: [String: Any])] = [:]

        // Get installed models from local Ollama API
        if let url = URL(string: "http://localhost:11434/api/tags") {
            do {
                let data = try Data(contentsOf: url)

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["models"] as? [[String: Any]] {

                    for model in models {
                        if let name = model["name"] as? String {
                            allInstalledModels.insert(name)

                            // Extract size (in bytes)
                            if let size = model["size"] as? Int64 {
                                modelDetails[name] = (size: size, details: model)
                            }
                        }
                    }
                }
            } catch {
                // Silent failure - will retry on next load
            }
        }

        self.installedModels = allInstalledModels

        // Clear and recreate models from installed ones only
        availableVisionModels = [Self.defaultVisionModel]
        availableTextModels = [Self.defaultTextModel]
        createModelsFromInstalled(allInstalledModels, modelDetails: modelDetails)

        // Reset to defaults after clearing cache
        resetToDefaults()
    }

    // Merge local size information and "latest" tag into web-fetched models
    private func mergeLocalSizes(models: [OllamaModel], localSizes: [String: String]) -> [OllamaModel] {
        let logPath = NSHomeDirectory() + "/Desktop/ollama_scraping.log"

        var logMessage = "\n=== MERGE LOCAL SIZES ===\n"
        logMessage += "Local sizes: \(localSizes)\n\n"

        let result = models.map { model in
            var updatedTags = model.tags.map { tag -> OllamaModelTag in
                let fullName = "\(model.name):\(tag.tag)"

                logMessage += "Processing tag: \(fullName)\n"
                logMessage += "  - Web size: \(tag.size ?? "nil")\n"
                logMessage += "  - Web context: \(tag.contextLength.map { "\($0)" } ?? "nil")\n"
                logMessage += "  - Web inputTypes: \(tag.inputTypes?.joined(separator: ", ") ?? "nil")\n"
                logMessage += "  - Local size: \(localSizes[fullName] ?? "nil")\n"

                // If we have local size info and web data doesn't have it, use local size
                if let localSize = localSizes[fullName], tag.size == nil {
                    logMessage += "  -> Using local size: \(localSize)\n"
                    return OllamaModelTag(
                        tag: tag.tag,
                        size: localSize,
                        contextLength: tag.contextLength,
                        inputTypes: tag.inputTypes,
                        downloads: tag.downloads,
                        updated: tag.updated,
                        digest: tag.digest,
                        isLatest: tag.isLatest,
                        isCompatible: tag.isCompatible
                    )
                }
                logMessage += "\n"
                return tag
            }

            // Add "latest" tag if it's installed locally but not in web data
            let latestFullName = "\(model.name):latest"
            if let latestSize = localSizes[latestFullName], !updatedTags.contains(where: { $0.tag == "latest" }) {
                logMessage += "Adding 'latest' tag for \(model.name) with size \(latestSize)\n\n"

                updatedTags.insert(OllamaModelTag(
                    tag: "latest",
                    size: latestSize,
                    contextLength: nil,
                    inputTypes: nil,
                    downloads: nil,
                    updated: nil,
                    digest: nil,
                    isLatest: false,  // This is the "latest" tag itself, not a concrete version
                    isCompatible: true
                ), at: 0)  // Insert at beginning so it appears first
            }

            return OllamaModel(name: model.name, tags: updatedTags, isVision: model.isVision)
        }

        // Write log
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }

        return result
    }

    // Create basic model entries from installed models
    @MainActor
    private func createModelsFromInstalled(_ installed: Set<String>, modelDetails: [String: (size: Int64, details: [String: Any])] = [:]) {
        var visionModels: [OllamaModel] = []
        var textModels: [OllamaModel] = []

        for modelName in installed {
            let parts = modelName.split(separator: ":")
            let baseName = parts.first.map(String.init) ?? modelName
            let tag = parts.count > 1 ? String(parts[1]) : "latest"

            // Check if it's a vision model
            let isVision = baseName.contains("vision") || baseName.contains("llava")

            // Get size from model details
            var sizeString: String? = nil
            if let details = modelDetails[modelName] {
                let sizeBytes = details.size
                let sizeGB = Double(sizeBytes) / 1_000_000_000.0
                if sizeGB >= 1.0 {
                    sizeString = String(format: "%.1fGB", sizeGB)
                } else {
                    let sizeMB = Double(sizeBytes) / 1_000_000.0
                    sizeString = String(format: "%.0fMB", sizeMB)
                }
            }

            // Create tag object with size
            // Note: Only add "latest" tag if it's actually installed
            // Don't mark it as isLatest=true, since that's for concrete versions
            let modelTag = OllamaModelTag(
                tag: tag,
                size: sizeString,
                contextLength: nil,  // Not available from local API
                inputTypes: nil,     // Not available from local API
                downloads: nil,      // Not available from local API
                updated: nil,        // Not available from local API
                digest: nil,         // Not available from local API
                isLatest: false,     // isLatest is for concrete versions like "2b", not for "latest" tag
                isCompatible: true
            )

            // Find or create model
            if isVision {
                if let index = visionModels.firstIndex(where: { $0.name == baseName }) {
                    let existing = visionModels[index]
                    if !existing.tags.contains(where: { $0.tag == tag }) {
                        var newTags = existing.tags
                        newTags.append(modelTag)
                        visionModels[index] = OllamaModel(name: baseName, tags: newTags, isVision: true)
                    }
                } else {
                    visionModels.append(OllamaModel(name: baseName, tags: [modelTag], isVision: true))
                }
            } else {
                if let index = textModels.firstIndex(where: { $0.name == baseName }) {
                    let existing = textModels[index]
                    if !existing.tags.contains(where: { $0.tag == tag }) {
                        var newTags = existing.tags
                        newTags.append(modelTag)
                        textModels[index] = OllamaModel(name: baseName, tags: newTags, isVision: false)
                    }
                } else {
                    textModels.append(OllamaModel(name: baseName, tags: [modelTag], isVision: false))
                }
            }
        }

        self.availableVisionModels = visionModels.sorted { $0.name < $1.name }
        self.availableTextModels = textModels.sorted { $0.name < $1.name }
    }

    // Fetch available models from Ollama website (background task)
    @MainActor
    public func loadAvailableModels(forceRefresh: Bool = false) async {
        // First, always load installed models immediately
        loadInstalledModels()

        // Save local size information before fetching from web
        var localSizes: [String: String] = [:]
        for model in availableVisionModels {
            for tag in model.tags {
                if let size = tag.size {
                    localSizes["\(model.name):\(tag.tag)"] = size
                }
            }
        }
        for model in availableTextModels {
            for tag in model.tags {
                if let size = tag.size {
                    localSizes["\(model.name):\(tag.tag)"] = size
                }
            }
        }

        // Then fetch from website in background with incremental updates
        do {
            let (visionModels, textModels) = try await OllamaModelFetcher.shared.fetchModels(forceRefresh: forceRefresh) { model, isVision in
                // Update config immediately when a model is loaded
                Task { @MainActor in
                    if isVision {
                        // Add this vision model to the list
                        let mergedModel = self.mergeLocalSizes(models: [model], localSizes: localSizes).first!
                        if !self.availableVisionModels.contains(where: { $0.name == mergedModel.name }) {
                            self.availableVisionModels.append(mergedModel)
                        }
                    } else {
                        // Add this text model to the list
                        let mergedModel = self.mergeLocalSizes(models: [model], localSizes: localSizes).first!
                        if !self.availableTextModels.contains(where: { $0.name == mergedModel.name }) {
                            self.availableTextModels.append(mergedModel)
                        }
                    }
                }
            }

            // Final update with all models (in case callback missed any)
            var mergedVisionModels = mergeLocalSizes(models: visionModels, localSizes: localSizes)
            var mergedTextModels = mergeLocalSizes(models: textModels, localSizes: localSizes)

            // Ensure default models are always present
            if !mergedVisionModels.contains(where: { $0.name == Self.defaultVisionModel.name }) {
                mergedVisionModels.insert(Self.defaultVisionModel, at: 0)
            }
            if !mergedTextModels.contains(where: { $0.name == Self.defaultTextModel.name }) {
                mergedTextModels.insert(Self.defaultTextModel, at: 0)
            }

            self.availableVisionModels = mergedVisionModels
            self.availableTextModels = mergedTextModels

            // Parse current ollamaVisionModel to extract base and tag
            let visionParts = ollamaVisionModel.split(separator: ":").map(String.init)
            if visionParts.count == 2 {
                selectedVisionModelBase = visionParts[0]
                selectedVisionModelTag = visionParts[1]
            } else if visionParts.count == 1 {
                selectedVisionModelBase = visionParts[0]
                selectedVisionModelTag = "latest"
            }

            // Parse current ollamaTextModel to extract base and tag
            let textParts = ollamaTextModel.split(separator: ":").map(String.init)
            if textParts.count == 2 {
                selectedTextModelBase = textParts[0]
                selectedTextModelTag = textParts[1]
            } else if textParts.count == 1 {
                selectedTextModelBase = textParts[0]
                selectedTextModelTag = "latest"
            }
        } catch {
            // Keep the installed models that we already loaded
        }
    }

    // Check if currently selected models are installed
    public func areSelectedModelsInstalled() -> (visionInstalled: Bool, textInstalled: Bool) {
        let visionInstalled = installedModels.contains(ollamaVisionModel)
        let textInstalled = installedModels.contains(ollamaTextModel)

        return (visionInstalled, textInstalled)
    }

    // Reset to defaults
    public func resetToDefaults() {
        remindersEnabled = true
        ollamaVisionModel = "granite3.2-vision:2b"
        ollamaTextModel = "granite3.3:2b"
        reminderSound = true
        showNotificationBanner = true
        reminderDelaySeconds = 40
        visionPrompt = Self.defaultVisionPrompt
        textPrompt = Self.defaultTextPrompt

        // Update selected model base and tag
        selectedVisionModelBase = "granite3.2-vision"
        selectedVisionModelTag = "2b"
        selectedTextModelBase = "granite3.3"
        selectedTextModelTag = "2b"

        // Ensure the selected model is in the available list
        Task {
            await loadAvailableModels()
        }
    }

    // Helper to replace placeholders in prompts
    public static func replacePromptPlaceholders(_ prompt: String, with values: [String: String]) -> String {
        var result = prompt
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}