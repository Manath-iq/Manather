//
//  AddSheetComponents.swift
//  manather
//
//  Shared chrome for the "Add …" sheets (web link, code snippet, MCP server,
//  skill) so they all match the app's light/dark paper-card style — the same
//  look as New Collection / New Board and the floating menus — instead of the
//  old forced-dark HUD material. One place to tweak the sheet design.
//

import SwiftUI

// MARK: - Sheet card chrome

/// The rounded paper-card background + matching color scheme applied to every
/// add sheet. Width hugs to `width`; height hugs its content. Use `.sheetCard()`.
private struct SheetCard: ViewModifier {
    let width: CGFloat
    @AppStorage("isDarkMode") private var isDarkMode = false

    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ManatherTheme.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ManatherTheme.hairline, lineWidth: 1)
                    )
            )
            .preferredColorScheme(isDarkMode ? .dark : .light)
    }
}

extension View {
    /// Wraps a sheet's content in the standard paper card (light/dark aware).
    func sheetCard(width: CGFloat = 460) -> some View {
        modifier(SheetCard(width: width))
    }
}

// MARK: - Header

/// Centered accent icon + title shown at the top of each add sheet.
struct SheetHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ManatherTheme.accent)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ManatherTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 4)
    }
}

// MARK: - Field label

/// Small uppercase caption above a field.
struct SheetFieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ManatherTheme.mutedInk)
            .textCase(.uppercase)
            .tracking(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Field background

/// Adaptive rounded fill + hairline used behind text fields and editors.
struct SheetFieldBackground: View {
    @AppStorage("isDarkMode") private var isDarkMode = false
    var cornerRadius: CGFloat = 7

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ManatherTheme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    /// Plain single-line text field styled for a sheet.
    func sheetField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(ManatherTheme.ink)
            .padding(8)
            .background(SheetFieldBackground())
    }
}

// MARK: - Footer

/// Standard Cancel / primary action row at the bottom of a sheet. The primary
/// button can show a spinner (`isPrimaryLoading`) for sheets that do async work.
struct SheetFooter: View {
    var primaryTitle: String
    var primaryEnabled: Bool
    var isPrimaryLoading: Bool = false
    let onCancel: () -> Void
    let onPrimary: () -> Void

    @AppStorage("isDarkMode") private var isDarkMode = false

    private var neutralFill: Color {
        isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    var body: some View {
        HStack(spacing: 12) {
            Spacer()

            Button("Cancel", action: onCancel)
                .buttonStyle(.microAnimated)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ManatherTheme.ink.opacity(0.75))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(neutralFill)
                )

            Button(action: onPrimary) {
                if isPrimaryLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text(primaryTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(primaryEnabled ? .white : ManatherTheme.mutedInk)
                }
            }
            .buttonStyle(.microAnimated)
            .disabled(!primaryEnabled || isPrimaryLoading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(primaryEnabled ? ManatherTheme.accent : neutralFill)
            )
        }
        .padding(.top, 4)
    }
}
