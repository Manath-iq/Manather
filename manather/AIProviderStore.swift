//
//  AIProviderStore.swift
//  manather
//
//  Holds per-provider connection state: the API key (Keychain), an optional base
//  URL override and chosen model (UserDefaults), plus the live result of the last
//  "Test connection". Secrets never touch UserDefaults or logs.
//

import Foundation
import Observation

/// Result of validating a provider connection.
enum ConnectionResult: Equatable {
    case idle
    case testing
    case success(models: [String])
    case failure(String)
}

@Observable
final class AIProviderStore {
    /// Transient per-provider test results (reset each session).
    private(set) var results: [String: ConnectionResult] = [:]

    /// Which provider the app uses by default for AI features.
    var defaultProviderID: String? {
        didSet { UserDefaults.standard.set(defaultProviderID, forKey: "ai.defaultProvider") }
    }

    init() {
        defaultProviderID = UserDefaults.standard.string(forKey: "ai.defaultProvider")
    }

    // MARK: - API keys (Keychain)

    func apiKey(for provider: AIProvider) -> String {
        KeychainStore.get(account: keyAccount(provider)) ?? ""
    }

    func hasKey(_ provider: AIProvider) -> Bool {
        KeychainStore.exists(account: keyAccount(provider))
    }

    func setAPIKey(_ key: String, for provider: AIProvider) {
        KeychainStore.set(key, account: keyAccount(provider))
        // Editing the key invalidates the previous test result.
        results[provider.id] = .idle
    }

    private func keyAccount(_ provider: AIProvider) -> String { "apikey.\(provider.id)" }

    // MARK: - Base URL (UserDefaults; only for editable endpoints)

    func baseURL(for provider: AIProvider) -> String {
        guard provider.baseURLEditable else { return provider.defaultBaseURL }
        let stored = UserDefaults.standard.string(forKey: "ai.baseURL.\(provider.id)")
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? provider.defaultBaseURL : trimmed
    }

    func setBaseURL(_ url: String, for provider: AIProvider) {
        UserDefaults.standard.set(url, forKey: "ai.baseURL.\(provider.id)")
    }

    // MARK: - Selected model (UserDefaults)

    func selectedModel(for provider: AIProvider) -> String {
        let stored = UserDefaults.standard.string(forKey: "ai.model.\(provider.id)") ?? ""
        return stored.isEmpty ? (provider.suggestedModels.first ?? "") : stored
    }

    func setSelectedModel(_ model: String, for provider: AIProvider) {
        UserDefaults.standard.set(model, forKey: "ai.model.\(provider.id)")
    }

    /// True once a provider has the credentials it needs (key, or none for Ollama).
    func isConfigured(_ provider: AIProvider) -> Bool {
        provider.kind.needsKey ? hasKey(provider) : true
    }

    func result(for provider: AIProvider) -> ConnectionResult {
        results[provider.id] ?? .idle
    }

    /// Models discovered by the last successful test, if any (for the model picker).
    func discoveredModels(for provider: AIProvider) -> [String] {
        if case .success(let models) = result(for: provider), !models.isEmpty { return models }
        return provider.suggestedModels
    }

    // MARK: - Test connection

    @MainActor
    func test(_ provider: AIProvider) async {
        let key = apiKey(for: provider)
        if provider.kind.needsKey && key.isEmpty {
            results[provider.id] = .failure("Enter an API key first")
            return
        }
        results[provider.id] = .testing
        let outcome = await ProviderConnectionService.test(
            provider: provider, key: key, baseURL: baseURL(for: provider)
        )
        results[provider.id] = outcome
    }
}

// MARK: - Connection service

/// Performs a lightweight authenticated request to confirm the key works and to
/// pull the available model list. Read-only (`GET`), 15s timeout.
enum ProviderConnectionService {
    static func test(provider: AIProvider, key: String, baseURL: String) async -> ConnectionResult {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL

        let urlString: String
        switch provider.kind {
        case .openAICompatible: urlString = "\(base)/models"
        case .anthropic:        urlString = "\(base)/v1/models"
        case .gemini:           urlString = "\(base)/models?key=\(key)"
        case .ollama:           urlString = "\(base)/api/tags"
        }
        guard let url = URL(string: urlString) else { return .failure("Bad base URL") }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        switch provider.kind {
        case .openAICompatible:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini, .ollama:
            break // key is in the query string / not needed
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure("No response") }
            switch http.statusCode {
            case 200:
                return .success(models: parseModels(data, kind: provider.kind))
            case 401, 403:
                return .failure("Invalid or unauthorized API key")
            case 404:
                return .failure("Endpoint not found (check base URL)")
            default:
                return .failure("HTTP \(http.statusCode)")
            }
        } catch {
            if (error as? URLError)?.code == .cannotConnectToHost {
                return .failure("Can't reach server (is it running?)")
            }
            return .failure(error.localizedDescription)
        }
    }

    /// Pulls model ids from each provider's list response shape.
    private static func parseModels(_ data: Data, kind: ProviderKind) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        switch kind {
        case .openAICompatible, .anthropic:
            let arr = json["data"] as? [[String: Any]] ?? []
            return arr.compactMap { $0["id"] as? String }.sorted()
        case .gemini:
            let arr = json["models"] as? [[String: Any]] ?? []
            return arr.compactMap { ($0["name"] as? String)?.replacingOccurrences(of: "models/", with: "") }.sorted()
        case .ollama:
            let arr = json["models"] as? [[String: Any]] ?? []
            return arr.compactMap { $0["name"] as? String }.sorted()
        }
    }
}
