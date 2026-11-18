//
//  GestureConfig.swift
//  MouseGestures
//
//  Everything you'd want to tweak lives here: button numbers, the drag
//  threshold, which apps are left alone, and what each gesture does.
//

import CoreGraphics
import Carbon.HIToolbox   // kVK_* virtual key code constants

/// The four directions a drag can resolve to.
nonisolated enum Direction {
    case up, down, left, right

    /// Turns a start/end point into a direction, or nil if the mouse
    /// didn't move far enough to count as a gesture.
    /// Screen coordinates have their origin at the top-left, so +y is DOWN.
    static func from(_ start: CGPoint, to end: CGPoint,
                     threshold: CGFloat = Config.dragThreshold) -> Direction? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard abs(dx) >= threshold || abs(dy) >= threshold else { return nil }

        if abs(dx) > abs(dy) {
            return dx > 0 ? .right : .left
        } else {
            return dy > 0 ? .down : .up
        }
    }
}

/// Something a button or gesture can trigger.
nonisolated enum GestureAction: Sendable {
    case keystroke(CGKeyCode, CGEventFlags)   // post a keyboard shortcut
    case openApp(String)                      // launch an app by path
    case screenshot                           // interactive region screenshot
    case none                                 // deliberately do nothing
}

nonisolated enum Config {

    // MARK: - Tuning

    /// Pixels the cursor must travel before a press counts as a drag gesture.
    static let dragThreshold: CGFloat = 60

    /// macOS button numbers: 0 = left, 1 = right, 2 = middle, 3 = back, 4 = front.
    /// If your side buttons come out swapped, swap these two values.
    static let backButton: Int64  = 3
    static let frontButton: Int64 = 4

    /// Stamped onto every event we post ourselves, so our own tap can recognize
    /// and ignore them instead of intercepting them in a loop. Any unusual number works.
    static let syntheticMarker: Int64 = 0x4D_47_53_54   // "MGST"

    /// Apps where right-drag should behave normally (gestures off).
    /// Find an app's ID with:  osascript -e 'id of app "AppName"'
    static let passThroughApps: Set<String> = [
        "org.blenderfoundation.blender",
    ]

    // MARK: - Key shortcuts used below

    /// Arrow keys on a real Mac keyboard carry the Fn and numeric-pad flags.
    /// Some system shortcuts (like switching Spaces) ignore synthetic arrows without them.
    private static let arrowFlags: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]

    private static let goBack    = GestureAction.keystroke(CGKeyCode(kVK_ANSI_LeftBracket),  .maskCommand) // Cmd+[
    private static let goForward = GestureAction.keystroke(CGKeyCode(kVK_ANSI_RightBracket), .maskCommand) // Cmd+]

    // MARK: - Front side button

    static let frontButtonAction: GestureAction = .keystroke(CGKeyCode(kVK_ANSI_4), [.maskCommand, .maskShift, .maskControl])

    // MARK: - Back side button (hold + drag)

    /// What a plain click (no drag) on the back button does.
    static let backClickAction: GestureAction = goBack

    /// Drags not listed here (up/down) fall back to `backClickAction`.
    static let backDragActions: [Direction: GestureAction] = [
        .left:  goBack,
        .right: goForward,
    ]

    // MARK: - Right button (hold + drag)

    /// A plain right-click (no drag) is always replayed as a normal right-click.
    static let rightDragActions: [Direction: GestureAction] = [
        .up:    .openApp("/System/Applications/Mission Control.app"),
        .down:  .keystroke(CGKeyCode(kVK_ANSI_M), .maskCommand),                          // close tab/window
        .left:  .keystroke(CGKeyCode(kVK_RightArrow),  arrowFlags.union(.maskControl)),    // previous Desktop
        .right: .keystroke(CGKeyCode(kVK_LeftArrow), arrowFlags.union(.maskControl)),    // next Desktop
    ]
}
