//
//  ExportGoalSheet.swift
//  manather
//
//  Shown right before a collection is exported as a build pack. The user types,
//  in their own words, what the project should become (a website, an app, a
//  bot…) — the brief that drives the export. The text is woven into the entry
//  file (CLAUDE.md / AGENTS.md / README.md) and context.md as a "Goal" section.
//
//  The goal is optional: leaving it blank exports exactly as before, letting the
//  agent infer intent from the materials.
//

import SwiftUI

struct ExportGoalSheet: View {
    let target: ExportTarget
    let collectionName: String
    /// The collection's assets — given to the AI as context when improving the goal.
    let assets: [AssetItem]
    /// Called with the (possibly empty) goal text once the user confirms. The
    /// caller opens the save panel and writes the pack.
    let onExport: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("isDarkMode") private var isDarkMode = false

    @State private var goal = ""
    @FocusState private var isFocused: Bool
    @State private var isImproving = false
    @State private var previousGoal: String? = nil    // for one-tap Undo
    @State private var improveError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ManatherTheme.accent)
                Text("Export “\(collectionName)”")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ManatherTheme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 2)

            Text("for \(target.menuLabel)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ManatherTheme.mutedInk)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 2)

            fieldLabel("What are you building?")

            ZStack(alignment: .topLeading) {
                // Placeholder is nudged a few px past where typed text lands (the
                // editor's 8 padding + NSTextView's ~5 line-fragment padding) so
                // the caret sits in clear space before it instead of overlapping
                // the first letter. Vertical padding matches the editor's.
                if goal.isEmpty {
                    Text("e.g. A one-page marketing site for a productivity app. Dark, modern, with a hero, features, pricing and a sign-up form. Built with Next.js + Tailwind.")
                        .font(.system(size: 13))
                        .foregroundStyle(ManatherTheme.mutedInk.opacity(0.7))
                        .padding(.leading, 17)
                        .padding(.trailing, 13)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $goal)
                    .font(.system(size: 13))
                    .foregroundStyle(ManatherTheme.ink)
                    .focused($isFocused)
                    .textEditorStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 9)
            }
            .frame(height: 150)
            .background(fieldBackground)

            // AI assist: let the default provider sharpen the draft into a brief.
            HStack(spacing: 10) {
                Button { improveGoal() } label: {
                    HStack(spacing: 5) {
                        if isImproving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("✦").font(.system(size: 12))
                        }
                        Text(isImproving ? "Improving…" : "Improve with AI")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(ManatherTheme.accent)
                }
                .buttonStyle(.microAnimated)
                .disabled(isImproving)
                .help("Rewrites your draft into a clear build brief using your default AI provider")

                if previousGoal != nil {
                    Button("Undo") {
                        if let p = previousGoal { goal = p; previousGoal = nil }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ManatherTheme.mutedInk)
                }
                Spacer()
            }

            if let improveError {
                Text(improveError)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.90, green: 0.45, blue: 0.30))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Describe the goal, the stack, the audience, must-haves. The AI uses this as the brief. Optional — skip to let it infer from your materials.")
                    .font(.system(size: 11))
                    .foregroundStyle(ManatherTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.microAnimated)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ManatherTheme.ink.opacity(0.75))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                    )

                Button("Export") {
                    let text = goal.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                    onExport(text)
                }
                .buttonStyle(.microAnimated)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(ManatherTheme.accent)
                )
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ManatherTheme.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(ManatherTheme.hairline, lineWidth: 1)
                )
        )
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onAppear { isFocused = true }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(ManatherTheme.hairline, lineWidth: 1)
            )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ManatherTheme.mutedInk)
            .textCase(.uppercase)
            .tracking(0.7)
    }

    /// Sends the current draft + a summary of the collection's materials to the
    /// default AI provider and replaces the goal with the refined brief.
    private func improveGoal() {
        guard !isImproving else { return }
        isImproving = true
        improveError = nil
        let draft = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let materials = assets
            .filter { !$0.isTrash && !$0.isDeleted }
            .prefix(40)
            .map { asset -> String in
                var line = "- \(asset.title) [\(asset.assetType.rawValue)]"
                if !asset.prompt.isEmpty { line += ": \(asset.prompt.prefix(120))" }
                return line
            }
            .joined(separator: "\n")

        let system = "You are an expert at writing concise build briefs for AI coding agents. " +
            "Given a rough goal and the project's reference materials, produce a clear, specific brief " +
            "(3–6 sentences) the agent can build from: what to build, the look/stack where implied, and key features. " +
            "Keep the user's intent. Return ONLY the brief — no preamble, no markdown headings."
        let user = """
        Draft goal:
        \(draft.isEmpty ? "(empty — propose a brief based on the materials)" : draft)

        Project materials:
        \(materials.isEmpty ? "(none)" : materials)
        """

        Task {
            do {
                let result = try await AIClient.chat(system: system, user: user)
                previousGoal = goal
                goal = result.trimmingCharacters(in: .whitespacesAndNewlines)
                isImproving = false
            } catch {
                isImproving = false
                improveError = (error as? AIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
