import CoreGraphics
import Foundation

private var tapPort: CFMachPort?

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
        Engine.shared.resync()
        return Unmanaged.passUnretained(event)
    }
    return Engine.shared.handleTapEvent(type, event) ? nil : Unmanaged.passUnretained(event)
}

/// Session-wide event tap on its own high-priority thread, so a busy main thread never delays system input.
enum InputTap {
    static var isRunning: Bool { tapPort != nil }

    /// Returns false while Accessibility permission is missing.
    static func start() -> Bool {
        if tapPort != nil { return true }

        var mask: CGEventMask = 0
        let types: [CGEventType] = [
            .flagsChanged, .keyDown,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .mouseMoved, .scrollWheel,
        ]
        for t in types { mask |= 1 << CGEventMask(t.rawValue) }
        // Trackpad gestures: rotate, begin/end, gesture, magnify, swipe, smart magnify, quick look, pressure
        for raw: CGEventMask in [18, 19, 20, 29, 30, 31, 32, 33, 34] { mask |= 1 << raw }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: nil
        ) else { return false }

        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "TrackNum.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }
}
