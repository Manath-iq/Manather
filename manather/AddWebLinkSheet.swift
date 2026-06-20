//
//  AddWebLinkSheet.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI
import SwiftData

struct AddWebLinkSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var urlString = ""
    @State private var isFetching = false
    @State private var errorMessage = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(icon: "link", title: "Add Web Link")

            Text("Paste a URL to save a website bookmark.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ManatherTheme.mutedInk)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("example.com", text: $urlString)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(ManatherTheme.ink)
                .focused($isFieldFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(errorMessage.isEmpty ? ManatherTheme.hairline : Color.red.opacity(0.55), lineWidth: 1)
                        )
                )
                .onChange(of: urlString) { _, _ in
                    errorMessage = ""
                }
                .onSubmit {
                    if !urlString.isEmpty && !isFetching {
                        fetchAndSave()
                    }
                }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            SheetFooter(
                primaryTitle: "Add URL",
                primaryEnabled: !urlString.isEmpty,
                isPrimaryLoading: isFetching,
                onCancel: { dismiss() },
                onPrimary: { fetchAndSave() }
            )
        }
        .sheetCard(width: 420)
        .onAppear { isFieldFocused = true }
    }

    private func fetchAndSave() {
        var cleanURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURLString.lowercased().hasPrefix("http://") && !cleanURLString.lowercased().hasPrefix("https://") {
            cleanURLString = "https://" + cleanURLString
        }

        guard let url = URL(string: cleanURLString), url.host != nil else {
            withAnimation(ManatherTheme.uiMotion) {
                errorMessage = "Enter a valid website address."
            }
            return
        }

        errorMessage = ""
        isFetching = true

        Task {
            var pageTitle = url.host ?? "Web Link"

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let html = String(data: data, encoding: .utf8),
                   let range = html.range(of: "<title>([^<]+)</title>", options: [.regularExpression, .caseInsensitive]) {
                    let rawTag = html[range]
                    let cleanTitle = rawTag
                        .replacingOccurrences(of: "<title>", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "</title>", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanTitle.isEmpty {
                        pageTitle = cleanTitle
                    }
                }
            } catch {
                // Use host as fallback title
            }

            await MainActor.run {
                let asset = AssetItem(
                    title: pageTitle,
                    relativeFilePath: "",
                    sourceURL: url.absoluteString,
                    typeRaw: "webLink"
                )
                modelContext.insert(asset)
                isFetching = false
                dismiss()
                WebsiteScreenshotManager.shared.generateScreenshot(for: asset, in: modelContext)
            }
        }
    }
}
