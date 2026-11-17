//
//  GestureEngine.swift
//  MouseGestures
//
//  The core: installs a CGEventTap, watches mouse buttons, decides whether
//  each press was a click or a drag gesture, and swallows or passes events.
//
//  The tap's run-loop source is added to the MAIN run loop, so every callback
//  below runs on the main thread, one at a time. No locking needed.
//

import AppKit

nonisolated final class GestureEngine {

    /// When false, every event passes straight through untouched.
    var isEnabled = true {
        didSet { if !isEnabled { resetState() } }
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Where the cursor was when each tracked button went down (nil = not tracking).
    private var rightStart: CGPoint?
    private var backStart: CGPoint?

    var isRunning: Bool { tap != nil }

    // MARK: - Start / stop

    /// Installs the event tap. Returns false if macOS refused, which almost
    /// always means the app doesn't have Accessibility permission yet.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let watched: [CGEventType] = [
            .rightMouseDown, .rightMouseDragged, .rightMouseUp,
            .otherMouseDown, .otherMouseDragged, .otherMouseUp,
        ]
        let mask = watched.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,          // all events for this login session
            place: .headInsertEventTap,       // see events before other taps do
            options: .defaultTap,             // active tap: we may modify or drop events
            eventsOfInterest: mask,
            callback: gestureTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("MouseGestures: tapCreate failed (Accessibility permission missing?)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        tap = newTap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        resetState()
    }

    private func resetState() {
        rightStart = nil
        backStart = nil
    }

    // MARK: - Event handling

    /// Return the event to let it through, or nil to swallow it.
    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        // macOS disables a tap whose callback is too slow, or when secure input
        // (e.g. a password field) is active. Turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        }

        guard isEnabled else { return passThrough }

        // Our own replayed clicks: let them through untouched.
        if event.getIntegerValueField(.eventSourceUserData) == Config.syntheticMarker {
            return passThrough
        }

        switch type {
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp:
            return handleRightButton(type, event)
        case .otherMouseDown, .otherMouseDragged, .otherMouseUp:
            return handleOtherButton(type, event)
        default:
            return passThrough
        }
    }

    // MARK: Right button: click vs. 4-direction gesture

    private func handleRightButton(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .rightMouseDown:
            if frontmostAppIsPassThrough() {
                return Unmanaged.passUnretained(event)   // behave normally in this app
            }
            rightStart = event.location
            return nil                                  // hold the click until we know what it is

        case .rightMouseDragged:
            // Hide drags only while we're tracking a gesture.
            return rightStart == nil ? Unmanaged.passUnretained(event) : nil

        default: // .rightMouseUp
            guard let start = rightStart else {
                return Unmanaged.passUnretained(event)  // a press we didn't track
            }
            rightStart = nil

            if let direction = Direction.from(start, to: event.location) {
                let action = Config.rightDragActions[direction] ?? .none
                runLater { Actions.perform(action) }
            } else {
                runLater { Actions.replayRightClick(at: start) }   // it was just a click
            }
            return nil
        }
    }

    // MARK: Side buttons

    private func handleOtherButton(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)

        switch button {
        case Config.frontButton:
            if type == .otherMouseDown {
                let action = Config.frontButtonAction
                runLater { Actions.perform(action) }
            }
            return nil

        case Config.backButton:
            switch type {
            case .otherMouseDown:
                backStart = event.location
            case .otherMouseUp:
                if let start = backStart {
                    let action = Direction.from(start, to: event.location)
                        .flatMap { Config.backDragActions[$0] }
                        ?? Config.backClickAction
                    runLater { Actions.perform(action) }
                }
                backStart = nil
            default:
                break   // drags while held: swallow
            }
            return nil

        default:
            return Unmanaged.passUnretained(event)   // middle click etc.: untouched
        }
    }

    // MARK: Helpers

    private func frontmostAppIsPassThrough() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return Config.passThroughApps.contains(id)
    }

    /// Runs an action after the callback returns, so the tap stays fast
    /// and we never post new events from inside the tap callback itself.
    private func runLater(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { work() }
    }
}

// MARK: - C callback

/// CGEventTap needs a plain C function pointer, so this can't capture anything.
/// We recover the engine instance from the userInfo pointer passed to tapCreate.
nonisolated private func gestureTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<GestureEngine>.fromOpaque(userInfo).takeUnretainedValue()
    return engine.handle(type: type, event: event)
}
