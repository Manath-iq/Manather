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

    @State private var urlString = ""
    @State private var isFetching = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Web Link")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Text("Paste a URL to save a website bookmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))

            TextField("example.com", text: $urlString)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ManatherTheme.viewerField)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(errorMessage.isEmpty ? ManatherTheme.viewerBorder : Color.red.opacity(0.55), lineWidth: 1)
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
                .frame(width: 300)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.82))
                    .frame(width: 300, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.microAnimated)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )

                Button {
                    fetchAndSave()
                } label: {
                    if isFetching {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text("Add URL")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.microAnimated)
                .disabled(urlString.isEmpty || isFetching)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(urlString.isEmpty || isFetching ? ManatherTheme.accent.opacity(0.40) : ManatherTheme.accent)
                )
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 360, height: errorMessage.isEmpty ? 190 : 214)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, forceDark: true)
        )
    }

    private func fetchAndSave() {
        var cleanURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURLString.lowercased().hasPrefix("http://") && !cleanURLString.lowercased().hasPrefix("https://") {
            cleanURLString = "https://" + cleanURLString
        }

        guard let url = URL(string: cleanURLString), url.host != nil else {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
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
