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
        // A new/removed key invalidates the previous test result and the model
        // list it produced — those models belonged to the old key.
        results[provider.id] = .idle
        setCachedModels([], for: provider)
        if key.isEmpty { UserDefaults.standard.removeObject(forKey: "ai.model.\(provider.id)") }
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

    // MARK: - Discovered models (live, cached in UserDefaults)

    /// The real model list pulled from the provider with the user's key. Persisted
    /// so it survives relaunches — we only refetch when the user asks or saves a key.
    func cachedModels(for provider: AIProvider) -> [String] {
        UserDefaults.standard.stringArray(forKey: "ai.models.\(provider.id)") ?? []
    }

    private func setCachedModels(_ models: [String], for provider: AIProvider) {
        UserDefaults.standard.set(models, forKey: "ai.models.\(provider.id)")
    }

    // MARK: - Selected model (UserDefaults)

    /// The model AI features should use. Returns the user's pick if it's still a
    /// real model for this key; otherwise the best auto-pick from the live list.
    /// Empty string means "no models loaded yet" — callers must treat that as not ready.
    func selectedModel(for provider: AIProvider) -> String {
        let stored = UserDefaults.standard.string(forKey: "ai.model.\(provider.id)") ?? ""
        let models = cachedModels(for: provider)
        if !stored.isEmpty, models.isEmpty || models.contains(stored) { return stored }
        return bestDefaultModel(for: provider, from: models)
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

    /// The live models for the model picker (empty until a fetch succeeds).
    func discoveredModels(for provider: AIProvider) -> [String] {
        cachedModels(for: provider)
    }

    /// Picks a sensible chat model out of a live list: skips non-chat models
    /// (embeddings, image, audio, moderation…), prefers a known flagship if the
    /// key exposes one, otherwise the first remaining chat model.
    private func bestDefaultModel(for provider: AIProvider, from models: [String]) -> String {
        guard !models.isEmpty else { return "" }
        let chat = models.filter { Self.isLikelyChatModel($0) }
        let pool = chat.isEmpty ? models : chat
        if let preferred = provider.suggestedModels.first(where: { pool.contains($0) }) {
            return preferred
        }
        return pool.first ?? models[0]
    }

    /// Heuristic to keep non-conversational models out of the default pick.
    private static func isLikelyChatModel(_ id: String) -> Bool {
        let lower = id.lowercased()
        let excluded = ["embed", "embedding", "tts", "whisper", "transcribe", "speech",
                        "audio", "image", "dall", "imagen", "moderation", "rerank",
                        "search", "similarity", "guard", "aqa"]
        return !excluded.contains { lower.contains($0) }
    }

    // MARK: - Fetch models

    /// Hits the provider's `/models` endpoint with the saved key, caches the live
    /// list, and makes sure the selected model is one that actually exists.
    @MainActor
    func refreshModels(_ provider: AIProvider) async {
        let key = apiKey(for: provider)
        if provider.kind.needsKey && key.isEmpty {
            results[provider.id] = .failure("Enter an API key first")
            return
        }
        results[provider.id] = .testing
        let outcome = await ProviderConnectionService.test(
            provider: provider, key: key, baseURL: baseURL(for: provider)
        )
        if case .success(let models) = outcome, !models.isEmpty {
            setCachedModels(models, for: provider)
            // Drop a stale pick and auto-select a default if needed.
            let current = UserDefaults.standard.string(forKey: "ai.model.\(provider.id)") ?? ""
            if current.isEmpty || !models.contains(current) {
                setSelectedModel(bestDefaultModel(for: provider, from: models), for: provider)
            }
        }
        results[provider.id] = outcome
    }

    /// Fetches models only when we don't already have a cached list — used when a
    /// provider row opens so the picker fills in without a manual click.
    @MainActor
    func refreshModelsIfNeeded(_ provider: AIProvider) async {
        guard isConfigured(provider), cachedModels(for: provider).isEmpty else { return }
        await refreshModels(provider)
    }

    /// Back-compat alias: "Test connection" = fetch the live model list.
    @MainActor
    func test(_ provider: AIProvider) async { await refreshModels(provider) }
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
