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

// MARK: - Menu panel

/// The styled dark menu panel. Supports a main page plus "Add to collection /
/// project" sub-pages so we never need floating native submenus.
struct AssetContextMenuView: View {
    let asset: AssetItem
    let collections: [String]
    let projects: [String]
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

    private enum Page { case main, collections, projects }
    @State private var page: Page = .main

    var body: some View {
        VStack(spacing: 2) {
            switch page {
            case .main:        mainPage
            case .collections: assignPage(title: "Add to Collection", options: collections) { asset.collectionName = $0 }
            case .projects:    assignPage(title: "Add to Project", options: projects) { asset.spaceName = $0 }
            }
        }
        .padding(6)
        .frame(width: 232)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.14, green: 0.14, blue: 0.155))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.40), radius: 22, x: 0, y: 12)
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
            row(.init(title: "Add to Project", systemImage: "square.stack.3d.up", showsChevron: true) {
                page = .projects
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
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        divider

        if options.isEmpty {
            Text("No \(title.contains("Collection") ? "collections" : "projects") yet")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
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

    // MARK: Pieces

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }

    private func row(_ item: AssetMenuItem) -> some View {
        ContextMenuRow(item: item)
    }
}

private struct ContextMenuRow: View {
    let item: AssetMenuItem
    @State private var isHovered = false

    private var tint: Color {
        item.isDestructive ? Color(red: 0.95, green: 0.36, blue: 0.34) : .white
    }

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint.opacity(item.isDestructive ? 0.95 : 0.85))
                    .frame(width: 18, alignment: .center)

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)

                Spacer(minLength: 8)

                if item.showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered
                          ? (item.isDestructive ? tint.opacity(0.16) : Color.white.opacity(0.10))
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
