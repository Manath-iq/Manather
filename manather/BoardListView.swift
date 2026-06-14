//
//  BoardListView.swift
//  manather
//
//  The list of boards that belong to one project. Opened from a project card's
//  "Boards" action. Lets you create a new board (title + description), open a
//  board (→ BoardView), and rename / duplicate / delete existing ones.
//

import SwiftUI
import SwiftData

struct BoardListView: View {
    let projectName: String
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @AppStorage("isDarkMode") private var isDarkMode = false

    @Query private var boards: [Board]

    @State private var openBoard: Board?
    @State private var showNewBoardSheet = false
    @State private var renamingBoard: Board?

    init(projectName: String, onClose: @escaping () -> Void) {
        self.projectName = projectName
        self.onClose = onClose
        let predicate = #Predicate<Board> { $0.projectName == projectName }
        _boards = Query(filter: predicate, sort: \Board.dateModified, order: .reverse)
    }

    var body: some View {
        ZStack {
            // Background — paper in light, charcoal-ish in dark (matches the app).
            ManatherTheme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
            }

            if let board = openBoard {
                BoardView(board: board) {
                    withAnimation(ManatherTheme.overlayMotion) { openBoard = nil }
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .sheet(isPresented: $showNewBoardSheet) {
            NewBoardSheet(projectName: projectName) { newBoard in
                withAnimation(ManatherTheme.overlayMotion) { openBoard = newBoard }
            }
        }
        .sheet(item: $renamingBoard) { board in
            EditBoardSheet(board: board)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Projects")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(ManatherTheme.mutedInk)
            }
            .buttonStyle(.microAnimated)

            Spacer()

            VStack(spacing: 1) {
                Text(projectName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ManatherTheme.ink)
                Text(boards.isEmpty ? "No boards yet" : "\(boards.count) board\(boards.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ManatherTheme.mutedInk)
            }

            Spacer()

            Button {
                showNewBoardSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("New board")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(ManatherTheme.accent)
                )
            }
            .buttonStyle(.microAnimated)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(ManatherTheme.paper.opacity(0.6))
        .overlay(alignment: .bottom) {
            Rectangle().fill(ManatherTheme.hairline).frame(height: 1)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if boards.isEmpty {
            emptyState
        } else {
            ScrollView {
                let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 20)]
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(boards) { board in
                        Button {
                            withAnimation(ManatherTheme.overlayMotion) { openBoard = board }
                        } label: {
                            boardCard(board)
                                .hoverLift()
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                renamingBoard = board
                            } label: {
                                Label("Rename / Edit details", systemImage: "pencil")
                            }
                            Button {
                                duplicate(board)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            Divider()
                            Button(role: .destructive) {
                                delete(board)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(ManatherTheme.accent.opacity(0.7))
            Text("No boards in this project yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ManatherTheme.ink)
            Text("Create a board to start a mood-board canvas\nfor \"\(projectName)\".")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(ManatherTheme.mutedInk)
            Button {
                showNewBoardSheet = true
            } label: {
                Text("New board")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(ManatherTheme.accent))
            }
            .buttonStyle(.microAnimated)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Board card

    private func boardCard(_ board: Board) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Canvas preview placeholder (dark, like the board itself).
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ManatherTheme.viewerBackground)
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                Image(systemName: "square.dashed")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.20))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(board.title.isEmpty ? "Untitled board" : board.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isDarkMode ? Color.white : Color.primary)
                    .lineLimit(1)

                if !board.details.isEmpty {
                    Text(board.details)
                        .font(.system(size: 11))
                        .foregroundStyle(isDarkMode ? Color.white.opacity(0.55) : Color.secondary)
                        .lineLimit(2)
                }

                Text(board.dateModified.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.4) : Color.secondary.opacity(0.8))
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background(isDarkMode ? Color.white.opacity(0.03) : Color.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func duplicate(_ board: Board) {
        let copy = Board(
            title: board.title + " copy",
            details: board.details,
            projectName: board.projectName,
            cameraX: board.cameraX,
            cameraY: board.cameraY,
            zoom: board.zoom
        )
        modelContext.insert(copy)
        // Copy items too so the duplicate is a real clone.
        for item in board.items {
            let newItem = BoardItem(
                kind: item.kind,
                x: item.x,
                y: item.y,
                width: item.width,
                height: item.height,
                zIndex: item.zIndex,
                assetID: item.assetID,
                text: item.text,
                fillColorHex: item.fillColorHex,
                shapeKind: item.shapeKindRaw == nil ? nil : item.shapeKind,
                frameTitle: item.frameTitle
            )
            newItem.board = copy
            modelContext.insert(newItem)
        }
    }

    private func delete(_ board: Board) {
        modelContext.delete(board) // cascade removes its items
    }
}

// MARK: - New board sheet

private struct NewBoardSheet: View {
    let projectName: String
    let onCreate: (Board) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ManatherTheme.accent)
                Text("New Board")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 4)

            fieldLabel("Board Name")
            TextField("e.g. Landing, Logo, Color mood", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(8)
                .background(fieldBackground)

            fieldLabel("Description (optional)")
            TextEditor(text: $details)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 90)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(ManatherTheme.viewerBorder, lineWidth: 1)
                        )
                )

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.microAnimated)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )

                Button("Create Board") { create() }
                    .buttonStyle(.microAnimated)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ManatherTheme.accent)
                    )
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440, height: 320)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, forceDark: true)
        )
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(ManatherTheme.viewerField)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ManatherTheme.viewerBorder, lineWidth: 1)
            )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .textCase(.uppercase)
            .tracking(0.7)
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let board = Board(
            title: trimmed.isEmpty ? "Untitled board" : trimmed,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            projectName: projectName
        )
        modelContext.insert(board)
        dismiss()
        onCreate(board)
    }
}

// MARK: - Edit board sheet (rename + details)

private struct EditBoardSheet: View {
    @Bindable var board: Board
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Board")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            fieldLabel("Board Name")
            TextField("Untitled board", text: $board.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ManatherTheme.viewerField)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(ManatherTheme.viewerBorder, lineWidth: 1)
                        )
                )

            fieldLabel("Description")
            TextEditor(text: $board.details)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 90)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(ManatherTheme.viewerBorder, lineWidth: 1)
                        )
                )

            HStack {
                Spacer()
                Button("Done") {
                    board.dateModified = Date()
                    dismiss()
                }
                .buttonStyle(.microAnimated)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ManatherTheme.accent)
                )
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440, height: 320)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, forceDark: true)
        )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .textCase(.uppercase)
            .tracking(0.7)
    }
}
