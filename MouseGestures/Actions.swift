//
//  Actions.swift
//  MouseGestures
//
//  The "do something" half: posting keystrokes, taking screenshots,
//  launching apps, and replaying a normal right-click.
//

import AppKit

enum Actions {

    /// Runs a configured action. Always called on the main thread.
    static func perform(_ action: GestureAction) {
        switch action {
        case .keystroke(let key, let flags):
            postKey(key, flags: flags)
        case .openApp(let path):
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                               configuration: NSWorkspace.OpenConfiguration())
        case .screenshot:
            takeScreenshot()
        case .none:
            break
        }
    }

    /// Posts a key-down + key-up pair with the given modifier flags.
    static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source,
                                      virtualKey: keyCode,
                                      keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Config.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Launches macOS's built-in screenshot tool.
    ///   -i  interactive: drag to select a region (press Space to pick a window instead)
    ///   -c  copy to the clipboard instead of saving a file
    static func takeScreenshot() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c"]
        do {
            try process.run()
        } catch {
            NSLog("MouseGestures: screenshot failed: \(error)")
        }
    }

    /// Re-sends a right-click at the point where the user originally pressed,
    /// tagged so our own event tap lets it through untouched.
    static func replayRightClick(at point: CGPoint) {
        postRightMouse(.rightMouseDown, at: point)
        // Real clicks have a short gap between press and release. Some apps
        // (Catalyst apps like Messages) mishandle a down+up arriving at the same instant.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            postRightMouse(.rightMouseUp, at: point)
        }
    }

    private static func postRightMouse(_ type: CGEventType, at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(mouseEventSource: source,
                                  mouseType: type,
                                  mouseCursorPosition: point,
                                  mouseButton: .right) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: 1)   // "single click", like real hardware
        event.setIntegerValueField(.eventSourceUserData, value: Config.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }
}
