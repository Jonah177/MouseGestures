//
//  MouseGesturesApp.swift
//  MouseGestures
//
//  App entry point + menu bar UI. Handles the Accessibility permission flow
//  and launch-at-login, and owns the GestureEngine.
//

import SwiftUI
import ServiceManagement
import ApplicationServices
import Combine

@main
struct MouseGesturesApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("Mouse Gestures", systemImage: "computermouse") {
            if state.isTrusted {
                Text(state.isEnabled ? "Gestures active" : "Gestures paused")
            } else {
                Text("Needs Accessibility permission")
                Button("Open Accessibility Settings…") { state.openAccessibilitySettings() }
            }

            Divider()

            Toggle("Enabled", isOn: $state.isEnabled)
            Toggle("Launch at Login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var isTrusted = false
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var isEnabled = true {
        didSet { engine.isEnabled = isEnabled }
    }

    private let engine = GestureEngine()
    private var trustTimer: Timer?

    init() {
        // First launch: this shows the system prompt asking for Accessibility access.
        isTrusted = Self.checkAccessibility(prompt: true)
        if isTrusted {
            engine.start()
        } else {
            waitForPermission()
        }
    }

    // MARK: Accessibility

    /// Asks macOS whether this app is allowed to control the computer.
    /// The literal key string is the value of kAXTrustedCheckOptionPrompt.
    private static func checkAccessibility(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// macOS doesn't notify apps when permission is granted, so poll every 2s.
    private func waitForPermission() {
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPermission() }
        }
    }

    private func pollPermission() {
        guard Self.checkAccessibility(prompt: false) else { return }
        trustTimer?.invalidate()
        trustTimer = nil
        isTrusted = engine.start()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Launch at login

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("MouseGestures: launch-at-login change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
