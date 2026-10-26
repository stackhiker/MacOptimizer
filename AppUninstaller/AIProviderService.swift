import Foundation
import Security

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openAI
    case gemini
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .claude: return "https://api.anthropic.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .gemini: return "gemini-2.5-flash"
        case .claude: return "claude-sonnet-4-20250514"
        }
    }
}

struct AIProviderConfiguration {
    let provider: AIProvider
    let baseURL: String
    let apiKey: String
    let model: String

    var isComplete: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct AIAttachmentPayload {
    let data: Data
    let mimeType: String
}

private struct AIProviderStoredConfiguration: Codable {
    var baseURL: String
    // Decoded only to migrate older files. New files never contain a key.
    var apiKey: String?
    var model: String
}

private struct AIProviderSettingsFile: Codable {
    var activeProvider: AIProvider
    var providers: [String: AIProviderStoredConfiguration]
}

protocol AISecretStore {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
}

final class AIProviderSettingsStore: ObservableObject {
    static let shared = AIProviderSettingsStore()

    @Published var activeProvider: AIProvider {
        didSet {
            storedSettings.activeProvider = activeProvider
            do { try persist(storedSettings); credentialStorageFailed = false }
            catch { credentialStorageFailed = true }
        }
    }
    @Published private(set) var credentialStorageFailed = false

    private static let activeProviderKey = "ai_active_provider"
    private let settingsURL: URL
    private let secrets: AISecretStore
    private var storedSettings: AIProviderSettingsFile

    init(settingsURL: URL? = nil, defaults: UserDefaults = .standard, secrets: AISecretStore? = nil) {
        self.settingsURL = settingsURL ?? Self.makeSettingsURL()
        self.secrets = secrets ?? AIKeychainStore()
        self.storedSettings = Self.readSettings(from: self.settingsURL) ?? Self.legacySettings(defaults: defaults)
        self.activeProvider = storedSettings.activeProvider
        do {
            // Preserve the old file if any Keychain write fails, so migration can
            // be retried without losing credentials. Existing Keychain keys stay.
            try persist(storedSettings)
            Self.removeLegacySettings(defaults: defaults)
        } catch {
            credentialStorageFailed = true
        }
    }

    func configuration(for provider: AIProvider? = nil) -> AIProviderConfiguration {
        let provider = provider ?? activeProvider
        let stored = storedSettings.providers[provider.rawValue]
        return AIProviderConfiguration(
            provider: provider,
            baseURL: stored?.baseURL ?? provider.defaultBaseURL,
            apiKey: (try? secrets.read(account: Self.account(provider))) ?? stored?.apiKey ?? "",
            model: stored?.model ?? provider.defaultModel
        )
    }

    func save(provider: AIProvider, baseURL: String, apiKey: String, model: String) throws {
        // Finish a pending migration before replacing any provider's key.
        try persist(storedSettings)
        let account = Self.account(provider)
        let previous = try secrets.read(account: account) ?? ""
        try secrets.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: account)
        var updated = storedSettings
        updated.activeProvider = provider
        updated.providers[provider.rawValue] = .init(
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: nil,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try persist(updated)
        } catch {
            try? secrets.write(previous, account: account)
            throw error
        }
        activeProvider = provider
        credentialStorageFailed = false
        objectWillChange.send()
    }

    func hasCompleteConfiguration(for provider: AIProvider? = nil) -> Bool {
        configuration(for: provider).isComplete
    }

    var storagePath: String { settingsURL.path }

    private static func account(_ provider: AIProvider) -> String { "ai.\(provider.rawValue).api-key" }

    private func persist(_ settings: AIProviderSettingsFile) throws {
        var sanitized = settings
        for provider in AIProvider.allCases {
            if let legacyKey = sanitized.providers[provider.rawValue]?.apiKey, !legacyKey.isEmpty {
                try secrets.write(legacyKey, account: Self.account(provider))
            }
            sanitized.providers[provider.rawValue]?.apiKey = nil
        }
        try Self.write(sanitized, to: settingsURL)
        storedSettings = sanitized
    }

    private static func makeSettingsURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Mac优化大师", isDirectory: true)
            .appendingPathComponent("ai-provider-settings.json", isDirectory: false)
    }

    private static func readSettings(from url: URL) -> AIProviderSettingsFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AIProviderSettingsFile.self, from: data)
    }

    private static func write(_ settings: AIProviderSettingsFile, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(settings).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw AIProviderError.fileStorage }
    }

    private static func legacySettings(defaults: UserDefaults) -> AIProviderSettingsFile {
        let active = AIProvider(rawValue: defaults.string(forKey: activeProviderKey) ?? "") ?? .openAI
        var providers: [String: AIProviderStoredConfiguration] = [:]
        for provider in AIProvider.allCases {
            providers[provider.rawValue] = .init(
                baseURL: defaults.string(forKey: "ai_\(provider.rawValue)_base_url") ?? provider.defaultBaseURL,
                apiKey: nil,
                model: defaults.string(forKey: "ai_\(provider.rawValue)_model") ?? provider.defaultModel
            )
        }
        return .init(activeProvider: active, providers: providers)
    }

    private static func removeLegacySettings(defaults: UserDefaults) {
        defaults.removeObject(forKey: activeProviderKey)
        for provider in AIProvider.allCases {
            defaults.removeObject(forKey: "ai_\(provider.rawValue)_base_url")
            defaults.removeObject(forKey: "ai_\(provider.rawValue)_model")
        }
    }
}

private struct AIKeychainStore: AISecretStore {
    private let service = Bundle.main.bundleIdentifier ?? "com.macoptimizer.ai"

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func read(account: String) throws -> String? {
        var lookup = query(account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AIProviderError.credentialStorage(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, account: String) throws {
        let lookup = query(account)
        if value.isEmpty {
            let status = SecItemDelete(lookup as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AIProviderError.credentialStorage(status)
            }
            return
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(lookup as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = lookup
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AIProviderError.credentialStorage(status) }
    }
}

enum AIProviderError: Error {
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int)
    case emptyResponse
    case fileStorage
    case credentialStorage(OSStatus)
}

struct AIProviderClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateJSON(
        configuration: AIProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        attachments: [AIAttachmentPayload] = []
    ) async throws -> String {
        switch configuration.provider {
        case .openAI:
            return try await requestOpenAI(configuration, systemPrompt: systemPrompt, userPrompt: userPrompt, attachments: attachments)
        case .gemini:
            return try await requestGemini(configuration, systemPrompt: systemPrompt, userPrompt: userPrompt, attachments: attachments)
        case .claude:
            return try await requestClaude(configuration, systemPrompt: systemPrompt, userPrompt: userPrompt, attachments: attachments)
        }
    }

    private func requestOpenAI(
        _ configuration: AIProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        attachments: [AIAttachmentPayload]
    ) async throws -> String {
        let url = try endpoint(baseURL: configuration.baseURL, suffix: "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let userContent: Any
        if attachments.isEmpty {
            userContent = userPrompt
        } else {
            var parts: [[String: Any]] = [["type": "text", "text": userPrompt]]
            parts.append(contentsOf: attachments.map { attachment in
                [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(attachment.mimeType);base64,\(attachment.data.base64EncodedString())"
                    ]
                ]
            })
            userContent = parts
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model,
            "temperature": 0,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ])

        let payload = try await send(request)
        let choices = payload["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = extractedText(from: message?["content"])
                ?? extractedText(from: choices?.first?["text"])
                ?? extractedText(from: payload["output_text"])
                ?? extractedText(from: payload["output"]) else {
            throw AIProviderError.invalidResponse
        }
        return content
    }

    private func requestGemini(
        _ configuration: AIProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        attachments: [AIAttachmentPayload]
    ) async throws -> String {
        var components = try endpointComponents(baseURL: configuration.baseURL)
        components.path = joinedPath(
            components.path,
            "models/\(configuration.model):generateContent"
        )
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "key" }
        queryItems.append(URLQueryItem(name: "key", value: configuration.apiKey))
        components.queryItems = queryItems
        guard let url = components.url else { throw AIProviderError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var parts: [[String: Any]] = [["text": userPrompt]]
        parts.append(contentsOf: attachments.map { attachment in
            [
                "inlineData": [
                    "mimeType": attachment.mimeType,
                    "data": attachment.data.base64EncodedString()
                ]
            ]
        })
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["temperature": 0]
        ])

        let payload = try await send(request)
        guard let candidates = payload["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let text = extractedText(from: content["parts"]) else {
            throw AIProviderError.invalidResponse
        }
        return text
    }

    private func requestClaude(
        _ configuration: AIProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        attachments: [AIAttachmentPayload]
    ) async throws -> String {
        let url = try endpoint(baseURL: configuration.baseURL, suffix: "messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var content: [[String: Any]] = [["type": "text", "text": userPrompt]]
        content.append(contentsOf: attachments.map { attachment in
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": attachment.mimeType,
                    "data": attachment.data.base64EncodedString()
                ]
            ]
        })
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model,
            "max_tokens": 800,
            "temperature": 0,
            "system": systemPrompt,
            "messages": [["role": "user", "content": content]]
        ])

        let payload = try await send(request)
        guard let text = extractedText(from: payload["content"]) else {
            throw AIProviderError.invalidResponse
        }
        return text
    }

    private func extractedText(from value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : text
        }
        if let dictionary = value as? [String: Any] {
            for key in ["text", "output_text", "content"] {
                if let text = extractedText(from: dictionary[key]) { return text }
            }
            return nil
        }
        if let array = value as? [Any] {
            let parts = array.compactMap(extractedText(from:))
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        }
        return nil
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AIProviderError.httpStatus(http.statusCode) }
        guard !data.isEmpty else { throw AIProviderError.emptyResponse }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }
        return payload
    }

    private func endpoint(baseURL: String, suffix: String) throws -> URL {
        var components = try endpointComponents(baseURL: baseURL)
        if !components.path.lowercased().hasSuffix("/\(suffix.lowercased())") {
            components.path = joinedPath(components.path, suffix)
        }
        guard let url = components.url else { throw AIProviderError.invalidBaseURL }
        return url
    }

    private func endpointComponents(baseURL: String) throws -> URLComponents {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil else {
            throw AIProviderError.invalidBaseURL
        }
        components.path = components.path.replacingOccurrences(of: "//", with: "/")
        return components
    }

    private func joinedPath(_ base: String, _ suffix: String) -> String {
        let left = base.hasSuffix("/") ? String(base.dropLast()) : base
        let right = suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix
        return "\(left)/\(right)"
    }
}
