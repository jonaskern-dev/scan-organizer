import Foundation
import AppKit

public struct OllamaModelTag: Codable, Equatable {
    public let tag: String
    public let size: String?           // e.g. "4.7GB"
    public let contextLength: Int?     // e.g. 32000
    public let inputTypes: [String]?   // e.g. ["text", "image"]
    public let downloads: String?      // e.g. "259.5K"
    public let updated: String?        // e.g. "1 year ago"
    public let digest: String?         // e.g. "42c7e6e2af53"
    public let isLatest: Bool
    public let isCompatible: Bool      // Based on available hardware

    public init(tag: String, size: String? = nil, contextLength: Int? = nil, inputTypes: [String]? = nil, downloads: String? = nil, updated: String? = nil, digest: String? = nil, isLatest: Bool = false, isCompatible: Bool = true) {
        self.tag = tag
        self.size = size
        self.contextLength = contextLength
        self.inputTypes = inputTypes
        self.downloads = downloads
        self.updated = updated
        self.digest = digest
        self.isLatest = isLatest
        self.isCompatible = isCompatible
    }

    // Parse size string to bytes for comparison
    public var sizeInBytes: Int64? {
        guard let size = size else { return nil }
        let pattern = #"([\d.]+)\s*(GB|MB)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: size, range: NSRange(size.startIndex..., in: size)),
              let valueRange = Range(match.range(at: 1), in: size),
              let unitRange = Range(match.range(at: 2), in: size),
              let value = Double(size[valueRange]) else {
            return nil
        }

        let unit = String(size[unitRange])
        let multiplier: Int64 = unit == "GB" ? 1_073_741_824 : 1_048_576
        return Int64(value * Double(multiplier))
    }
}

public struct OllamaModel: Codable, Equatable {
    public let name: String
    public let tags: [OllamaModelTag]
    public let isVision: Bool

    public init(name: String, tags: [OllamaModelTag], isVision: Bool) {
        self.name = name
        self.tags = tags
        self.isVision = isVision
    }

    // URL to model description page
    public var libraryURL: URL? {
        URL(string: "https://ollama.com/library/\(name)")
    }

    // Helper to open model page in browser
    public func openInBrowser() {
        guard let url = libraryURL else { return }
        NSWorkspace.shared.open(url)
    }
}

public struct OllamaModelCache: Codable {
    public let timestamp: Date
    public let visionModels: [OllamaModel]
    public let textModels: [OllamaModel]

    public var isExpired: Bool {
        let oneWeek: TimeInterval = 7 * 24 * 60 * 60
        return Date().timeIntervalSince(timestamp) > oneWeek
    }
}

public class OllamaModelFetcher {
    public static let shared = OllamaModelFetcher()

    private let cacheURL: URL
    private let cacheExpirationInterval: TimeInterval = 7 * 24 * 60 * 60 // 1 week

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("ScanOrganizer")
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        cacheURL = appFolder.appendingPathComponent("ollama_models_cache.json")
    }

    // MARK: - Public API

    public func fetchModels(forceRefresh: Bool = false, onModelLoaded: ((OllamaModel, Bool) -> Void)? = nil) async throws -> (vision: [OllamaModel], text: [OllamaModel]) {
        // Try to load from cache first
        if !forceRefresh, let cache = loadCache(), !cache.isExpired {
            print("[OllamaModelFetcher] Using cached models (age: \(String(format: "%.1f", Date().timeIntervalSince(cache.timestamp) / 86400)) days)")
            return (vision: cache.visionModels, text: cache.textModels)
        }

        print("[OllamaModelFetcher] Fetching fresh models from Ollama website...")

        // Fetch vision model names
        let visionModelNames = try await fetchVisionModelNames()
        print("[OllamaModelFetcher] Found \(visionModelNames.count) vision models")

        // Fetch all model names from library
        let allModelNames = try await fetchAllModelNames()
        print("[OllamaModelFetcher] Found \(allModelNames.count) total models")

        // Separate text models (all - vision)
        let textModelNames = allModelNames.filter { !visionModelNames.contains($0) }
        print("[OllamaModelFetcher] Found \(textModelNames.count) text models")

        // Fetch tags with details for each model
        var visionModels: [OllamaModel] = []
        for name in visionModelNames {
            let tags = try await fetchModelTagsWithDetails(modelName: name)
            let model = OllamaModel(name: name, tags: tags, isVision: true)
            visionModels.append(model)

            // Notify callback that a vision model is ready
            onModelLoaded?(model, true)
        }

        var textModels: [OllamaModel] = []
        for name in textModelNames {
            let tags = try await fetchModelTagsWithDetails(modelName: name)
            let model = OllamaModel(name: name, tags: tags, isVision: false)
            textModels.append(model)

            // Notify callback that a text model is ready
            onModelLoaded?(model, false)
        }

        // Cache the results
        let cache = OllamaModelCache(
            timestamp: Date(),
            visionModels: visionModels,
            textModels: textModels
        )
        saveCache(cache)

        print("[OllamaModelFetcher] Successfully fetched and cached models")
        return (vision: visionModels, text: textModels)
    }

    // MARK: - Private Fetching Methods

    private func fetchVisionModelNames() async throws -> [String] {
        guard let url = URL(string: "https://ollama.com/search?c=vision") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Extract model names from href="/library/MODEL_NAME"
        let pattern = #"href="/library/([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        var modelNames = Set<String>()
        for match in matches {
            if let range = Range(match.range(at: 1), in: html) {
                let modelName = String(html[range])
                modelNames.insert(modelName)
            }
        }

        return Array(modelNames).sorted()
    }

    private func fetchAllModelNames() async throws -> [String] {
        guard let url = URL(string: "https://ollama.com/library") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Extract model names from href="/library/MODEL_NAME"
        let pattern = #"href="/library/([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        var modelNames = Set<String>()
        for match in matches {
            if let range = Range(match.range(at: 1), in: html) {
                let modelName = String(html[range])
                modelNames.insert(modelName)
            }
        }

        return Array(modelNames).sorted()
    }

    private func fetchModelTagsWithDetails(modelName: String) async throws -> [OllamaModelTag] {
        guard let url = URL(string: "https://ollama.com/library/\(modelName)/tags") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Get available RAM to determine compatibility
        let availableRAM = getAvailableRAM()

        var modelTags: [OllamaModelTag] = []
        var latestTag: String? = nil

        // Extract downloads count (appears once per model, not per tag)
        // Pattern: <span x-test-pull-count>2.6M</span> or <span x-test-pull-count="">2.6M</span>
        var modelDownloads: String? = nil
        let downloadsPattern = #"x-test-pull-count[^>]*>([0-9.]+[KM])</span>"#
        if let downloadsRegex = try? NSRegularExpression(pattern: downloadsPattern),
           let match = downloadsRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let valueRange = Range(match.range(at: 1), in: html) {
            modelDownloads = String(html[valueRange])
            print("[OllamaModelFetcher] Found model downloads: \(modelDownloads ?? "none")")
        } else {
            print("[OllamaModelFetcher] Could not find downloads count")
        }

        // Parse model tag entries - they appear as sections with model:tag format
        // Looking for patterns like:
        // <a href="/library/model:tag">
        //   Contains: size (e.g., "4.7GB"), context (e.g., "128K"), input types

        let escapedModelName = NSRegularExpression.escapedPattern(for: modelName)

        // Strategy to find latest tag (multi-step priority):
        // 1. First try to find <span>latest</span> badge and use the tag before it
        // 2. If no badge, use digest matching: find digest of "latest" tag
        // 3. Find all tags with matching digest (some models have 3+ with same digest)
        // 4. Use the SECOND tag with matching digest (position 2, after "latest" itself)

        print("[OllamaModelFetcher] Searching for latest tag...")

        var latestDigest: String? = nil
        var latestTagViaBadge: String? = nil

        // Step 1: Try to find latest badge
        let latestBadgePattern = #"<span[^>]*>latest</span>"#
        if let latestBadgeRegex = try? NSRegularExpression(pattern: latestBadgePattern, options: [.caseInsensitive]) {
            let badgeMatches = latestBadgeRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            print("[OllamaModelFetcher] Found \(badgeMatches.count) latest badges")

            for badgeMatch in badgeMatches {
                let badgePosition = badgeMatch.range.location
                let searchStart = max(0, badgePosition - 500)
                let searchRange = NSRange(location: searchStart, length: badgePosition - searchStart)

                let tagPattern = "\(escapedModelName):([^<\"\\s]+)"
                if let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]) {
                    let tagMatches = tagRegex.matches(in: html, options: [], range: searchRange)

                    if let lastTagMatch = tagMatches.last,
                       let tagRange = Range(lastTagMatch.range(at: 1), in: html) {
                        let foundTag = String(html[tagRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                        if foundTag != "latest" {
                            latestTagViaBadge = foundTag
                            print("[OllamaModelFetcher] Found latest tag via badge: \(foundTag)")
                            break
                        }
                    }
                }
            }
        }

        // Step 2: If badge found, use it; otherwise prepare for digest matching
        if let badgeTag = latestTagViaBadge {
            latestTag = badgeTag
            print("[OllamaModelFetcher] Using badge-based latest: \(badgeTag)")
        } else {
            // No badge found, will use digest matching
            let latestMetadata = extractMetadataForTag(from: html, tag: "latest", modelName: modelName)
            if let digest = latestMetadata.digest, !digest.isEmpty {
                latestDigest = digest
                print("[OllamaModelFetcher] Found digest for 'latest' tag: \(digest)")
                print("[OllamaModelFetcher] Will find second tag with matching digest")
            } else {
                print("[OllamaModelFetcher] No 'latest' tag found or no digest available")
            }
        }

        // Find all tag sections - look for model:tag pattern in href
        let tagPattern = "href=\"/library/\(escapedModelName):([^\"]+)\""
        let tagRegex = try NSRegularExpression(pattern: tagPattern)
        let tagMatches = tagRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        var processedTags = Set<String>()
        var digestMatchTags: [String] = []  // Track all tags with matching digest

        for match in tagMatches {
            guard let tagRange = Range(match.range(at: 1), in: html) else { continue }
            let tag = String(html[tagRange])

            // Skip duplicates
            if processedTags.contains(tag) { continue }
            processedTags.insert(tag)

            // Extract metadata from the table row for this tag
            let metadata = extractMetadataForTag(from: html, tag: tag, modelName: modelName)
            let size = metadata.size
            let contextLength = metadata.contextLength
            let inputTypes = metadata.inputTypes
            let downloads = modelDownloads  // Use model-level downloads, not per-tag
            let updated = metadata.updated
            let digest = metadata.digest

            // Step 3: Collect all tags with matching digest (if no badge was found)
            if latestTag == nil, let latestDig = latestDigest, let tagDig = digest, !tagDig.isEmpty {
                if latestDig == tagDig && tag != "latest" {
                    digestMatchTags.append(tag)
                    print("[OllamaModelFetcher] Found digest match: \(tag) (digest: \(tagDig))")
                }
            }

            // Write to log file
            let logPath = NSHomeDirectory() + "/Desktop/ollama_scraping.log"
            let isLatestMarker = (tag == latestTag) ? " [LATEST]" : ""
            let digestMatchMarker = (latestDigest != nil && digest == latestDigest && tag != "latest") ? " [DIGEST MATCH]" : ""
            let logMessage = """
            [OllamaModelFetcher] Tag '\(tag)' for model '\(modelName)'\(isLatestMarker)\(digestMatchMarker):
              - Size: \(size ?? "nil")
              - Context: \(contextLength.map { "\($0)" } ?? "nil")
              - InputTypes: \(inputTypes?.joined(separator: ", ") ?? "nil")
              - Downloads: \(downloads ?? "nil")
              - Updated: \(updated ?? "nil")
              - Digest: \(digest ?? "nil")
              - Latest Digest: \(latestDigest ?? "nil")
              - isLatest flag will be: \(tag == latestTag)

            """
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

            // Check compatibility based on model size
            let isCompatible: Bool
            if let sizeStr = size, let sizeBytes = parseSizeToBytes(sizeStr) {
                // Model should fit in RAM with some overhead (use 80% of available RAM as threshold)
                isCompatible = sizeBytes <= Int64(Double(availableRAM) * 0.8)
            } else {
                isCompatible = true // Unknown size, assume compatible
            }

            modelTags.append(OllamaModelTag(
                tag: tag,
                size: size,
                contextLength: contextLength,
                inputTypes: inputTypes,
                downloads: downloads,
                updated: updated,
                digest: digest,
                isLatest: false, // Will be set later
                isCompatible: isCompatible
            ))
        }

        // Step 4: If no badge was found, use digest matching - pick the SECOND tag with matching digest
        if latestTag == nil && digestMatchTags.count >= 1 {
            // Use index 0 if only one match, otherwise use index 1 (second tag)
            let selectedIndex = digestMatchTags.count > 1 ? 1 : 0
            latestTag = digestMatchTags[selectedIndex]
            print("[OllamaModelFetcher] Using digest-based latest (position \(selectedIndex + 1)): \(latestTag!) from \(digestMatchTags)")
        }

        // Mark the actual latest tag
        if let latest = latestTag {
            for i in 0..<modelTags.count {
                if modelTags[i].tag == latest {
                    modelTags[i] = OllamaModelTag(
                        tag: modelTags[i].tag,
                        size: modelTags[i].size,
                        contextLength: modelTags[i].contextLength,
                        inputTypes: modelTags[i].inputTypes,
                        downloads: modelTags[i].downloads,
                        updated: modelTags[i].updated,
                        digest: modelTags[i].digest,
                        isLatest: true,
                        isCompatible: modelTags[i].isCompatible
                    )
                }
            }
        }

        // Keep "latest" tag - don't filter it out

        // If no tags found after filtering, add latest as fallback
        if modelTags.isEmpty {
            modelTags.append(OllamaModelTag(tag: "latest", isLatest: true, isCompatible: true))
        }

        return modelTags.sorted { $0.tag < $1.tag }
    }

    // MARK: - HTML Parsing Helpers

    private func extractMetadataForTag(from html: String, tag: String, modelName: String) -> (size: String?, contextLength: Int?, inputTypes: [String]?, updated: String?, digest: String?) {
        // The HTML structure is: <a href="/library/modelname:tag">...metadata in surrounding divs...</a>
        let fullTagName = "\(modelName):\(tag)"

        // Find the link containing our tag
        let linkPattern = "href=\"/library/\(NSRegularExpression.escapedPattern(for: fullTagName))\""
        guard let linkRange = html.range(of: linkPattern, options: .regularExpression) else {
            return (nil, nil, nil, nil, nil)
        }

        // Get surrounding context (parent div) - go back 500 chars, forward 1000 chars
        let contextStart = html.index(linkRange.lowerBound, offsetBy: -500, limitedBy: html.startIndex) ?? html.startIndex
        let contextEnd = html.index(linkRange.upperBound, offsetBy: 1000, limitedBy: html.endIndex) ?? html.endIndex
        let contextHTML = String(html[contextStart..<contextEnd])

        var size: String? = nil
        var contextLength: Int? = nil
        var inputTypes: [String]? = nil
        var updated: String? = nil
        var digest: String? = nil

        // Extract size: Look for "X.X GB" or "XXX MB" pattern
        let sizePattern = #"(\d+\.?\d*)\s*(GB|MB)"#
        if let sizeRegex = try? NSRegularExpression(pattern: sizePattern),
           let match = sizeRegex.firstMatch(in: contextHTML, range: NSRange(contextHTML.startIndex..., in: contextHTML)),
           let valueRange = Range(match.range(at: 1), in: contextHTML),
           let unitRange = Range(match.range(at: 2), in: contextHTML) {
            let value = String(contextHTML[valueRange])
            let unit = String(contextHTML[unitRange])
            size = "\(value)\(unit)"
        }

        // Extract context: Look for "X K" or "XXX K" pattern
        let contextPattern = #"(\d+)\s*K"#
        if let contextRegex = try? NSRegularExpression(pattern: contextPattern),
           let match = contextRegex.firstMatch(in: contextHTML, range: NSRange(contextHTML.startIndex..., in: contextHTML)),
           let valueRange = Range(match.range(at: 1), in: contextHTML),
           let value = Int(contextHTML[valueRange]) {
            contextLength = value * 1000
        }

        // Extract input types: Look for "Text" and "Image"
        var types: [String] = []
        if contextHTML.contains("Text") {
            types.append("Text")
        }
        if contextHTML.contains("Image") {
            types.append("Image")
        }
        if !types.isEmpty {
            inputTypes = types
        }

        // Extract digest (hash): Look for 12-char hex pattern
        let digestPattern = #"[0-9a-f]{12}"#
        if let digestRegex = try? NSRegularExpression(pattern: digestPattern),
           let match = digestRegex.firstMatch(in: contextHTML, range: NSRange(contextHTML.startIndex..., in: contextHTML)),
           let valueRange = Range(match.range, in: contextHTML) {
            digest = String(contextHTML[valueRange])
        }

        // Extract updated: Look for pattern "· X time ago" (after the middle dot)
        let updatedPattern = #"·\s*(.+?ago)"#
        if let updatedRegex = try? NSRegularExpression(pattern: updatedPattern),
           let match = updatedRegex.firstMatch(in: contextHTML, range: NSRange(contextHTML.startIndex..., in: contextHTML)),
           let valueRange = Range(match.range(at: 1), in: contextHTML) {
            // Remove &nbsp; and trim whitespace
            updated = String(contextHTML[valueRange])
                .replacingOccurrences(of: "&nbsp;", with: "")
                .trimmingCharacters(in: .whitespaces)
        }

        return (size, contextLength, inputTypes, updated, digest)
    }

    private func parseSizeToBytes(_ sizeString: String) -> Int64? {
        let pattern = #"([\d.]+)\s*(GB|MB)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: sizeString, range: NSRange(sizeString.startIndex..., in: sizeString)),
              let valueRange = Range(match.range(at: 1), in: sizeString),
              let unitRange = Range(match.range(at: 2), in: sizeString),
              let value = Double(sizeString[valueRange]) else {
            return nil
        }

        let unit = String(sizeString[unitRange])
        let multiplier: Int64 = unit == "GB" ? 1_073_741_824 : 1_048_576
        return Int64(value * Double(multiplier))
    }

    private func getAvailableRAM() -> Int64 {
        var size: UInt64 = 0
        var mib = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(mib)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &mib)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_page_size)
            let freeMemory = UInt64(stats.free_count) * pageSize
            let inactiveMemory = UInt64(stats.inactive_count) * pageSize
            return Int64(freeMemory + inactiveMemory)
        }

        // Fallback: get total physical memory
        size = ProcessInfo.processInfo.physicalMemory
        return Int64(size)
    }

    // MARK: - Cache Management

    private func loadCache() -> OllamaModelCache? {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            let cache = try JSONDecoder().decode(OllamaModelCache.self, from: data)
            return cache
        } catch {
            print("[OllamaModelFetcher] Failed to load cache: \(error)")
            return nil
        }
    }

    private func saveCache(_ cache: OllamaModelCache) {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL)
            print("[OllamaModelFetcher] Cache saved to \(cacheURL.path)")
        } catch {
            print("[OllamaModelFetcher] Failed to save cache: \(error)")
        }
    }

    public func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
        print("[OllamaModelFetcher] Cache cleared")
    }
}
