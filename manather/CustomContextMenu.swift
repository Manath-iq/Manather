//
//  CustomContextMenu.swift
//  manather
//
//  A custom right-click menu (dark, rounded, dimmed backdrop) that replaces the
//  native macOS context menu — matching the reference look.
//

import SwiftUI
import AppKit

// MARK: - Right-click detection

/// Transparent overlay that reports right-clicks (and control-clicks) without
/// swallowing left-clicks or hover. It does NO coordinate conversion, so it
/// stays correct under the global UI zoom — the caller reads the SwiftUI frame.
struct RightClickCatcher: NSViewRepresentable {
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ClickView)?.onRightClick = onRightClick
    }

    private final class ClickView: NSView {
        var onRightClick: (() -> Void)?

        // Only claim the hit for right / control clicks; pass everything else
        // (left click, hover) through to the SwiftUI content underneath.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let isRight = event.type == .rightMouseDown || event.type == .rightMouseUp
            let isControlLeft = (event.type == .leftMouseDown || event.type == .leftMouseUp)
                && event.modifierFlags.contains(.control)
            return (isRight || isControlLeft) ? self : nil
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                onRightClick?()
            } else {
                super.mouseDown(with: event)
            }
        }
    }
}

extension View {
    /// Reports a right-click along with this view's frame in the given space.
    func onRightClick(in space: CoordinateSpace, perform: @escaping (CGRect) -> Void) -> some View {
        overlay(
            GeometryReader { proxy in
                RightClickCatcher {
                    perform(proxy.frame(in: space))
                }
            }
        )
    }
}

// MARK: - Menu item model

struct AssetMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var systemImage: String
    var isDestructive: Bool = false
    var showsChevron: Bool = false
    var action: () -> Void
}

// MARK: - Shared menu palette + chrome

/// All colors for the floating menus, derived from the current theme so the
/// same panel works in both dark and light mode.
struct MenuPalette {
    let isDarkMode: Bool

    var panel: Color { isDarkMode ? Color(red: 0.14, green: 0.14, blue: 0.155) : Color.white }
    var stroke: Color { isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08) }
    var shadow: Color { Color.black.opacity(isDarkMode ? 0.40 : 0.16) }
    var label: Color { isDarkMode ? .white : Color(red: 0.11, green: 0.11, blue: 0.13) }
    var icon: Color { label.opacity(0.85) }
    var hover: Color { isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06) }
    var divider: Color { isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.07) }
    var secondary: Color { label.opacity(isDarkMode ? 0.35 : 0.4) }
    var destructive: Color { Color(red: 0.92, green: 0.30, blue: 0.28) }
}

private extension View {
    /// Applies the rounded panel background, border and shadow shared by both menus.
    func menuPanelChrome(_ palette: MenuPalette) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.stroke, lineWidth: 1)
            )
            .shadow(color: palette.shadow, radius: 22, x: 0, y: 12)
    }
}

/// A thin separator used between groups of rows.
private struct MenuDivider: View {
    let palette: MenuPalette
    var body: some View {
        Rectangle()
            .fill(palette.divider)
            .frame(height: 1)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }
}

// MARK: - Add (+) menu

/// The styled menu shown by the floating "+" button. Same look as the
/// right-click menu, themed for light/dark.
struct AddMenuView: View {
    let isDarkMode: Bool
    let onDismiss: () -> Void
    let onImport: () -> Void
    let onWebLink: () -> Void
    let onCodeSnippet: () -> Void
    let onSkill: () -> Void
    let onMCPServer: () -> Void

    private var palette: MenuPalette { MenuPalette(isDarkMode: isDarkMode) }

    var body: some View {
        VStack(spacing: 2) {
            row("Import files", "doc.badge.plus", onImport)
            row("Add web link", "link", onWebLink)
            row("Add code snippet", "curlybraces", onCodeSnippet)
            MenuDivider(palette: palette)
            row("Add skill", "sparkles.rectangle.stack", onSkill)
            row("Add MCP server", "server.rack", onMCPServer)
        }
        .padding(6)
        .frame(width: 220)
        .menuPanelChrome(palette)
        .fixedSize()
    }

    private func row(_ title: String, _ image: String, _ action: @escaping () -> Void) -> some View {
        ContextMenuRow(
            item: AssetMenuItem(title: title, systemImage: image) { action(); onDismiss() },
            palette: palette
        )
    }
}

// MARK: - Menu panel

/// The styled dark menu panel. Supports a main page plus "Add to collection /
/// project" sub-pages so we never need floating native submenus.
struct AssetContextMenuView: View {
    let asset: AssetItem
    let isDarkMode: Bool
    let collections: [String]
    /// Create a brand-new collection object with this name (the row also assigns
    /// the asset to it). Lets you make a collection straight from the right-click
    /// menu instead of having to open the inspector first.
    let onCreateCollection: (String) -> Void
    let isTrash: Bool

    let onOpen: () -> Void
    let onCopyPrompt: () -> Void
    let onCopyImage: (() -> Void)?
    let onRevealInFinder: (() -> Void)?
    let onDuplicate: () -> Void
    let onExport: (() -> Void)?
    let onTrash: () -> Void
    let onRestore: () -> Void
    let onDeletePermanently: () -> Void
    let onDismiss: () -> Void

    private enum Page { case main, collections }
    @State private var page: Page = .main

    private var palette: MenuPalette { MenuPalette(isDarkMode: isDarkMode) }

    // Inline "New collection…" field state (collections sub-page).
    @State private var isCreatingCollection = false
    @State private var newCollectionName = ""
    @FocusState private var newCollectionFocused: Bool

    var body: some View {
        VStack(spacing: 2) {
            switch page {
            case .main:        mainPage
            case .collections: assignPage(title: "Add to Collection", options: collections) { asset.collectionName = $0 }
            }
        }
        .padding(6)
        .frame(width: 232)
        .menuPanelChrome(palette)
        .fixedSize()
    }

    // MARK: Pages

    @ViewBuilder
    private var mainPage: some View {
        if isTrash {
            row(.init(title: "Restore", systemImage: "arrow.uturn.backward") {
                onRestore(); onDismiss()
            })
            divider
            row(.init(title: "Delete Permanently", systemImage: "trash.slash", isDestructive: true) {
                onDeletePermanently(); onDismiss()
            })
        } else {
            row(.init(title: "Open", systemImage: "arrow.up.left.and.arrow.down.right") {
                onOpen(); onDismiss()
            })
            divider
            if !asset.prompt.isEmpty {
                row(.init(title: "Copy Prompt", systemImage: "doc.on.doc") {
                    onCopyPrompt(); onDismiss()
                })
            }
            if let onCopyImage {
                row(.init(title: "Copy Image", systemImage: "photo.on.rectangle") {
                    onCopyImage(); onDismiss()
                })
            }
            divider
            row(.init(title: "Add to Collection", systemImage: "folder.badge.plus", showsChevron: true) {
                page = .collections
            })
            divider
            row(.init(title: "Duplicate", systemImage: "plus.square.on.square") {
                onDuplicate(); onDismiss()
            })
            if let onRevealInFinder {
                row(.init(title: "Reveal in Finder", systemImage: "folder") {
                    onRevealInFinder(); onDismiss()
                })
            }
            if let onExport {
                row(.init(title: "Export…", systemImage: "square.and.arrow.up") {
                    onExport(); onDismiss()
                })
            }
            divider
            row(.init(title: "Move to Trash", systemImage: "trash", isDestructive: true) {
                onTrash(); onDismiss()
            })
        }
    }

    @ViewBuilder
    private func assignPage(title: String, options: [String], assign: @escaping (String?) -> Void) -> some View {
        // Header with back button
        Button {
            page = .main
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(palette.label.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        divider

        // Create a new collection right here, then drop the asset into it.
        if title.contains("Collection") {
            if isCreatingCollection {
                newCollectionField(assign: assign)
            } else {
                row(.init(title: "New Collection…", systemImage: "plus") {
                    isCreatingCollection = true
                    DispatchQueue.main.async { newCollectionFocused = true }
                })
            }
            divider
        }

        if options.isEmpty {
            Text("No \(title.contains("Collection") ? "collections" : "projects") yet")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(options, id: \.self) { name in
                row(.init(title: name, systemImage: "circle.fill") {
                    assign(name); onDismiss()
                })
            }
        }

        divider
        row(.init(title: title.contains("Collection") ? "Remove from Collection" : "Remove from Project",
                  systemImage: "minus.circle") {
            assign(nil); onDismiss()
        })
    }

    /// Inline text field for naming a new collection inside the menu.
    private func newCollectionField(assign: @escaping (String?) -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.icon)
                .frame(width: 18, alignment: .center)

            TextField("Name", text: $newCollectionName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.label)
                .focused($newCollectionFocused)
                .onSubmit { commitNewCollection(assign: assign) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func commitNewCollection(assign: @escaping (String?) -> Void) {
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            isCreatingCollection = false
            return
        }
        onCreateCollection(name)
        assign(name)
        newCollectionName = ""
        isCreatingCollection = false
        onDismiss()
    }

    // MARK: Pieces

    private var divider: some View {
        MenuDivider(palette: palette)
    }

    private func row(_ item: AssetMenuItem) -> some View {
        ContextMenuRow(item: item, palette: palette)
    }
}

struct ContextMenuRow: View {
    let item: AssetMenuItem
    let palette: MenuPalette
    @State private var isHovered = false

    private var tint: Color {
        item.isDestructive ? palette.destructive : palette.label
    }

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(item.isDestructive ? tint.opacity(0.95) : palette.icon)
                    .frame(width: 18, alignment: .center)

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)

                Spacer(minLength: 8)

                if item.showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered
                          ? (item.isDestructive ? tint.opacity(0.16) : palette.hover)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
