//
//  GlobalHotKey.swift
//  manather
//
//  A system-wide hotkey (works even when manather is in the background) plus the
//  interactive screenshot capture it triggers. Uses Carbon's RegisterEventHotKey
//  — unlike a global NSEvent monitor, it does not need Accessibility permission.
//

import SwiftUI
import AppKit
import Carbon.HIToolbox
import SwiftData

// MARK: - Modifier helpers

enum HotKeyModifiers {
    /// NSEvent modifier flags → Carbon modifier mask (for RegisterEventHotKey).
    static func carbon(from flags: NSEvent.ModifierFlags) -> Int {
        var mask = 0
        if flags.contains(.command) { mask |= cmdKey }
        if flags.contains(.shift)   { mask |= shiftKey }
        if flags.contains(.option)  { mask |= optionKey }
        if flags.contains(.control) { mask |= controlKey }
        return mask
    }

    /// A readable label like "⌘⇧7" for the given Carbon modifiers + key.
    static func displayString(carbonModifiers: Int, keyLabel: String) -> String {
        var s = ""
        if carbonModifiers & controlKey != 0 { s += "⌃" }
        if carbonModifiers & optionKey  != 0 { s += "⌥" }
        if carbonModifiers & shiftKey   != 0 { s += "⇧" }
        if carbonModifiers & cmdKey     != 0 { s += "⌘" }
        return s + keyLabel.uppercased()
    }
}

// MARK: - Hotkey manager

final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    /// Called on the main thread whenever the registered hotkey is pressed.
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// (Re)register the hotkey. Pass `enabled: false` or an empty keyCode to clear it.
    func update(keyCode: Int, carbonModifiers: Int, enabled: Bool) {
        unregister()
        guard enabled, keyCode > 0, carbonModifiers != 0 else { return }

        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: fourCharCode("MNTH"), id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(carbonModifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        } else {
            print("RegisterEventHotKey failed: \(status)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onTrigger?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    private func fourCharCode(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + FourCharCode(scalar.value & 0xFF)
        }
        return result
    }
}

// MARK: - Screenshot capture

@MainActor
enum ScreenshotCapture {
    /// Launches the native interactive screenshot UI (crosshair / window picker).
    /// When the user finishes a selection, the captured image is added to the
    /// library. Cancelling produces no file and adds nothing.
    static func captureInteractive(into context: ModelContext) {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("manather-shot-\(UUID().uuidString).png")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive selection, -o no shadow on window captures.
        task.arguments = ["-i", "-o", tmpURL.path]
        task.terminationHandler = { _ in
            DispatchQueue.main.async {
                defer { try? FileManager.default.removeItem(at: tmpURL) }
                guard FileManager.default.fileExists(atPath: tmpURL.path),
                      let image = NSImage(contentsOf: tmpURL) else {
                    return // user cancelled the selection
                }
                let stamp = Self.timestamp()
                AssetIngest.ingestImage(image, title: "Screenshot \(stamp)", into: context)
            }
        }

        do {
            try task.run()
        } catch {
            print("screencapture failed to launch: \(error)")
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH.mm.ss"
        return formatter.string(from: Date())
    }
}

// MARK: - Settings: hotkey recorder

/// A compact "click then press a combo" recorder for the screenshot hotkey,
/// plus an on/off toggle. Persists straight to the shared AppStorage keys that
/// ContentView watches to (re)register the global hotkey.
struct HotKeyRecorderView: View {
    @AppStorage("screenshotHotKeyEnabled") private var enabled = true
    @AppStorage("screenshotHotKeyCode") private var keyCode = 26
    @AppStorage("screenshotHotKeyModifiers") private var modifiers = 768
    @AppStorage("screenshotHotKeyDisplay") private var display = "⌘⇧7"
    @AppStorage("isDarkMode") private var isDarkMode = false

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $enabled) {
                Text("Screenshot hotkey")
                    .font(.system(size: 11, weight: .semibold))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(ManatherTheme.accent)

            HStack {
                Text("Shortcut")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    Text(isRecording ? "Press keys…" : display)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isRecording ? ManatherTheme.accent : (isDarkMode ? .white : .primary))
                        .frame(minWidth: 62)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isRecording ? ManatherTheme.accent.opacity(0.7) : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.4)
            }

            Text("Capture a screenshot from anywhere. macOS may ask for Screen Recording permission the first time.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape cancels recording without changing anything.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            // Require at least one modifier so the global hotkey can't be a bare key.
            guard !flags.isEmpty else { return nil }

            let carbon = HotKeyModifiers.carbon(from: flags)
            keyCode = Int(event.keyCode)
            modifiers = carbon
            display = HotKeyModifiers.displayString(
                carbonModifiers: carbon,
                keyLabel: event.charactersIgnoringModifiers ?? ""
            )
            stopRecording()
            return nil // swallow the event so it doesn't act elsewhere
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
