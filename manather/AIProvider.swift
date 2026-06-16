//
//  AIProvider.swift
//  manather
//
//  Catalog of AI providers the user can connect by API key. Connecting stores
//  the key in the Keychain and (optionally) a chosen model; this readies the app
//  for AI features (Generate variation, auto-tag, context.md generation).
//
//  The metadata here also drives "Test connection" — see ProviderConnectionService.
//

import Foundation

/// How a provider authenticates and where its model list lives. This decides the
/// shape of the validation request.
enum ProviderKind {
    case openAICompatible   // OpenAI, OpenRouter, xAI, DeepSeek, Mistral — Bearer + GET /models
    case anthropic          // x-api-key + anthropic-version, GET /v1/models
    case gemini             // ?key=…, GET /v1beta/models
    case ollama             // local, no key, GET /api/tags

    var needsKey: Bool { self != .ollama }
}

struct AIProvider: Identifiable, Hashable {
    let id: String                 // stable id, also the Keychain account
    let displayName: String
    let kind: ProviderKind
    let iconSystemName: String
    /// Base API URL. For Ollama / OpenAI-compatible this can be overridden by the
    /// user (stored in UserDefaults); `defaultBaseURL` is the seed.
    let defaultBaseURL: String
    /// Whether the base URL is user-editable (local / self-hosted endpoints).
    let baseURLEditable: Bool
    let keyPrefixHint: String      // e.g. "sk-or-", shown as a hint; empty = none
    let docsURL: String
    let suggestedModels: [String]  // fallback list before/if we can't fetch live

    static func == (lhs: AIProvider, rhs: AIProvider) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension AIProvider {
    /// The providers shown in Settings, in display order. Core first, then extras.
    static let all: [AIProvider] = [
        AIProvider(
            id: "openrouter", displayName: "OpenRouter", kind: .openAICompatible,
            iconSystemName: "arrow.triangle.branch",
            defaultBaseURL: "https://openrouter.ai/api/v1", baseURLEditable: false,
            keyPrefixHint: "sk-or-", docsURL: "https://openrouter.ai/keys",
            suggestedModels: ["openai/gpt-5", "anthropic/claude-opus-4-8", "google/gemini-2.5-pro"]
        ),
        AIProvider(
            id: "openai", displayName: "OpenAI", kind: .openAICompatible,
            iconSystemName: "circle.hexagongrid",
            defaultBaseURL: "https://api.openai.com/v1", baseURLEditable: false,
            keyPrefixHint: "sk-", docsURL: "https://platform.openai.com/api-keys",
            suggestedModels: ["gpt-5", "gpt-5-mini", "o4-mini"]
        ),
        AIProvider(
            id: "anthropic", displayName: "Anthropic", kind: .anthropic,
            iconSystemName: "sparkle",
            defaultBaseURL: "https://api.anthropic.com", baseURLEditable: false,
            keyPrefixHint: "sk-ant-", docsURL: "https://console.anthropic.com/settings/keys",
            suggestedModels: ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
        ),
        AIProvider(
            id: "gemini", displayName: "Google Gemini", kind: .gemini,
            iconSystemName: "diamond",
            defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta", baseURLEditable: false,
            keyPrefixHint: "AIza", docsURL: "https://aistudio.google.com/app/apikey",
            suggestedModels: ["gemini-2.5-pro", "gemini-2.5-flash"]
        ),
        AIProvider(
            id: "xai", displayName: "xAI (Grok)", kind: .openAICompatible,
            iconSystemName: "x.circle",
            defaultBaseURL: "https://api.x.ai/v1", baseURLEditable: false,
            keyPrefixHint: "xai-", docsURL: "https://console.x.ai",
            suggestedModels: ["grok-4", "grok-4-fast"]
        ),
        AIProvider(
            id: "deepseek", displayName: "DeepSeek", kind: .openAICompatible,
            iconSystemName: "water.waves",
            defaultBaseURL: "https://api.deepseek.com", baseURLEditable: false,
            keyPrefixHint: "sk-", docsURL: "https://platform.deepseek.com/api_keys",
            suggestedModels: ["deepseek-chat", "deepseek-reasoner"]
        ),
        AIProvider(
            id: "mistral", displayName: "Mistral", kind: .openAICompatible,
            iconSystemName: "wind",
            defaultBaseURL: "https://api.mistral.ai/v1", baseURLEditable: false,
            keyPrefixHint: "", docsURL: "https://console.mistral.ai/api-keys",
            suggestedModels: ["mistral-large-latest", "mistral-small-latest"]
        ),
        AIProvider(
            id: "ollama", displayName: "Ollama (local)", kind: .ollama,
            iconSystemName: "desktopcomputer",
            defaultBaseURL: "http://localhost:11434", baseURLEditable: true,
            keyPrefixHint: "", docsURL: "https://ollama.com",
            suggestedModels: ["llama3.2", "qwen2.5-coder", "deepseek-r1"]
        ),
    ]

    static func provider(id: String) -> AIProvider? { all.first { $0.id == id } }
}
