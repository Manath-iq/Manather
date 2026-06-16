//
//  AIClient.swift
//  manather
//
//  Calls the user's default AI provider for the app's two AI features:
//  • chat(…)              — refine the export goal text (any provider).
//  • generateVariation(…) — make an image variation (OpenAI / xAI / Gemini).
//
//  Credentials/config are resolved from the same places Settings writes them
//  (Keychain via KeychainStore, prefs via AIProviderStore). Keys never leave the
//  request and are never logged.
//

import Foundation
import AppKit

enum AIError: LocalizedError {
    case notConnected
    case imagesUnsupported(String)   // provider display name
    case http(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No AI provider connected. Add a key in Settings → AI Providers and set a default."
        case .imagesUnsupported(let name):
            return "\(name) can't generate images. Set OpenAI or Google Gemini as the default provider."
        case .http(let message):
            return message
        case .badResponse:
            return "The model returned no usable result."
        }
    }
}

/// The default provider plus the resolved key/base/model needed to call it.
struct ResolvedProvider {
    let provider: AIProvider
    let key: String
    let baseURL: String
    let model: String
}

enum AIClient {

    // MARK: - Resolve default provider

    @MainActor
    static func resolveDefault() -> ResolvedProvider? {
        let store = AIProviderStore()
        guard let id = store.defaultProviderID, let provider = AIProvider.provider(id: id) else { return nil }
        let key = store.apiKey(for: provider)
        if provider.kind.needsKey && key.isEmpty { return nil }
        return ResolvedProvider(
            provider: provider, key: key,
            baseURL: trimSlash(store.baseURL(for: provider)),
            model: store.selectedModel(for: provider)
        )
    }

    // MARK: - Chat (text)

    /// Sends a system+user prompt to the default provider's chat model.
    static func chat(system: String, user: String) async throws -> String {
        guard let cfg = await resolveDefault() else { throw AIError.notConnected }

        let url: URL
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: [String: Any]

        switch cfg.provider.kind {
        case .openAICompatible:
            url = try makeURL("\(cfg.baseURL)/chat/completions")
            headers["Authorization"] = "Bearer \(cfg.key)"
            body = ["model": cfg.model, "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]]
        case .anthropic:
            url = try makeURL("\(cfg.baseURL)/v1/messages")
            headers["x-api-key"] = cfg.key
            headers["anthropic-version"] = "2023-06-01"
            body = ["model": cfg.model, "max_tokens": 1500, "system": system,
                    "messages": [["role": "user", "content": user]]]
        case .gemini:
            url = try makeURL("\(cfg.baseURL)/models/\(cfg.model):generateContent?key=\(cfg.key)")
            body = ["contents": [["parts": [["text": user]]]],
                    "systemInstruction": ["parts": [["text": system]]]]
        case .ollama:
            url = try makeURL("\(cfg.baseURL)/api/chat")
            body = ["model": cfg.model, "stream": false, "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]]
        }

        let data = try await post(url, headers: headers, body: body, timeout: 60)
        guard let text = parseChatText(data, kind: cfg.provider.kind), !text.isEmpty else {
            throw AIError.badResponse
        }
        return text
    }

    // MARK: - Image variation

    /// Generates one image variation of `asset` and returns PNG/JPEG data.
    static func generateVariation(of asset: AssetItem) async throws -> Data {
        guard let cfg = await resolveDefault() else { throw AIError.notConnected }
        let prompt = asset.prompt.isEmpty ? asset.title : asset.prompt

        switch cfg.provider.kind {
        case .gemini:
            return try await geminiVariation(cfg: cfg, asset: asset, prompt: prompt)
        case .openAICompatible:
            guard let imageModel = openAIImageModel(for: cfg.provider.id) else {
                throw AIError.imagesUnsupported(cfg.provider.displayName)
            }
            return try await openAIImage(cfg: cfg, model: imageModel, prompt: prompt)
        case .anthropic, .ollama:
            throw AIError.imagesUnsupported(cfg.provider.displayName)
        }
    }

    /// OpenAI / xAI image-capable model ids; nil = no image generation.
    private static func openAIImageModel(for providerID: String) -> String? {
        switch providerID {
        case "openai": return "gpt-image-1"
        case "xai":    return "grok-2-image"
        default:       return nil   // OpenRouter/DeepSeek/Mistral: not wired
        }
    }

    private static func openAIImage(cfg: ResolvedProvider, model: String, prompt: String) async throws -> Data {
        let url = try makeURL("\(cfg.baseURL)/images/generations")
        let headers = ["Content-Type": "application/json", "Authorization": "Bearer \(cfg.key)"]
        // Minimal body: gpt-image-1 always returns base64 and rejects extra params.
        let body: [String: Any] = ["model": model, "prompt": prompt, "n": 1]
        let data = try await post(url, headers: headers, body: body, timeout: 120)
        guard let first = (json(data)?["data"] as? [[String: Any]])?.first else { throw AIError.badResponse }
        if let b64 = first["b64_json"] as? String, let imgData = Data(base64Encoded: b64) {
            return imgData
        }
        if let urlStr = first["url"] as? String, let imageURL = URL(string: urlStr) {
            return try await URLSession.shared.data(from: imageURL).0
        }
        throw AIError.badResponse
    }

    private static func geminiVariation(cfg: ResolvedProvider, asset: AssetItem, prompt: String) async throws -> Data {
        let src = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
        guard let imgData = try? Data(contentsOf: src) else { throw AIError.badResponse }
        let mime = mimeType(for: asset.relativeFilePath)
        let instruction = "Create a new variation of this image. Keep the same subject, " +
            "style, mood and colour palette, but vary the composition and details. " +
            "Return only the image. Reference description: \(prompt)"

        // Use the dedicated image model regardless of the chosen chat model.
        let url = try makeURL("\(cfg.baseURL)/models/gemini-2.5-flash-image:generateContent?key=\(cfg.key)")
        let body: [String: Any] = ["contents": [[
            "parts": [
                ["text": instruction],
                ["inline_data": ["mime_type": mime, "data": imgData.base64EncodedString()]]
            ]
        ]]]
        let data = try await post(url, headers: ["Content-Type": "application/json"], body: body, timeout: 120)

        let parts = (((json(data)?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        for part in parts {
            // Gemini returns either inlineData (camelCase) or inline_data.
            let inline = (part["inlineData"] as? [String: Any]) ?? (part["inline_data"] as? [String: Any])
            if let b64 = inline?["data"] as? String, let out = Data(base64Encoded: b64) {
                return out
            }
        }
        throw AIError.badResponse
    }

    // MARK: - Networking

    private static func post(_ url: URL, headers: [String: String], body: [String: Any], timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.http("No response") }
        guard http.statusCode == 200 else {
            throw AIError.http(errorMessage(from: data) ?? "HTTP \(http.statusCode)")
        }
        return data
    }

    // MARK: - Parsing helpers

    private static func json(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func parseChatText(_ data: Data, kind: ProviderKind) -> String? {
        guard let root = json(data) else { return nil }
        switch kind {
        case .openAICompatible:
            let msg = (root["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
            return msg?["content"] as? String
        case .anthropic:
            let blocks = root["content"] as? [[String: Any]]
            return blocks?.compactMap { $0["text"] as? String }.joined()
        case .gemini:
            let parts = ((root["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
            return parts?.compactMap { $0["text"] as? String }.joined()
        case .ollama:
            return (root["message"] as? [String: Any])?["content"] as? String
        }
    }

    /// Pulls a human-readable error out of a provider error body.
    private static func errorMessage(from data: Data) -> String? {
        guard let root = json(data) else { return nil }
        if let err = root["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
        if let msg = root["error"] as? String { return msg }              // Ollama
        if let msg = root["message"] as? String { return msg }
        return nil
    }

    private static func mimeType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        default:            return "image/png"
        }
    }

    private static func trimSlash(_ s: String) -> String { s.hasSuffix("/") ? String(s.dropLast()) : s }

    private static func makeURL(_ s: String) throws -> URL {
        guard let url = URL(string: s) else { throw AIError.http("Bad URL") }
        return url
    }
}
