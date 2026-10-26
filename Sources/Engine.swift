import CoreGraphics
import Foundation
import QuartzCore
import os

enum Hotkey: String, CaseIterable {
    case rightCommand, rightOption, fn

    var keyCode: Int64 {
        switch self {
        case .rightCommand: 54
        case .rightOption: 61
        case .fn: 63
        }
    }

    /// Device-dependent flag bit, distinguishes left/right modifiers.
    var deviceMask: UInt64 {
        switch self {
        case .rightCommand: 0x10      // NX_DEVICERCMDKEYMASK
        case .rightOption: 0x40       // NX_DEVICERALTKEYMASK
        case .fn: 0x800000            // NX_SECONDARYFNMASK
        }
    }

    var title: String {
        switch self {
        case .rightCommand: "Rechte ⌘-Taste"
        case .rightOption: "Rechte ⌥-Taste"
        case .fn: "fn / 🌐"
        }
    }
}

enum Trigger: String {
    /// Fire as soon as a finger lands (fastest).
    case touch
    /// Fire on the physical click / tap-to-click, using the most recent finger's position.
    case click
}

/// Central state machine. Fed from two threads: the multitouch frame thread and the event tap thread.
/// All mutable state lives behind one unfair lock; UI callbacks are delivered on the main queue.
final class Engine {
    static let shared = Engine()

    /// Marks events we post ourselves so the tap lets them through untouched.
    static let syntheticMarker: Int64 = 0x5452_4B4E

    /// Press shorter than this without using the pad toggles the latched mode.
    private let latchTapDuration = 0.30
    /// Clicks arriving shortly after deactivation (tap-to-click lag) are still swallowed.
    private let swallowGrace = 0.30
    /// Same key within this window counts as a duplicate contact.
    private let repeatGuard = 0.045
    /// No frame for this long means all fingers have lifted.
    private let frameGap = 0.15

    struct State {
        var enabled = true
        var hotkey = Hotkey.rightCommand
        var trigger = Trigger.touch
        var layout = PadLayout()

        var held = false
        var latched = false
        var pressStart = 0.0
        var usedThisPress = false
        var cancelledThisPress = false
        var active = false
        var reportedLatched = false

        var swallowUntil = 0.0
        var swallowedButtons: UInt32 = 0

        var touchMask: UInt64 = 0
        var lastFrame = 0.0
        var lastBeganX: Float = -1
        var lastBeganY: Float = -1
        var lastKey: PadKey?
        var lastKeyTime = 0.0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let keySource = CGEventSource(stateID: .privateState)

    /// (active, latched) – main queue
    var onModeChange: ((Bool, Bool) -> Void)?
    /// main queue
    var onKey: ((PadKey) -> Void)?
    /// Print every new contact (diagnostics, `--probe`).
    var probe = false

    func configure(enabled: Bool, hotkey: Hotkey, trigger: Trigger) {
        let change = state.withLockUnchecked { s -> (Bool, Bool)? in
            s.enabled = enabled
            s.trigger = trigger
            if s.hotkey != hotkey {
                s.hotkey = hotkey
                s.held = false
            }
            if !enabled {
                s.held = false
                s.latched = false
            }
            return recompute(&s, now: CACurrentMediaTime())
        }
        notify(change)
    }

    /// Drops held/latched state, e.g. on sleep or after the tap was disabled.
    func resync() {
        let change = state.withLockUnchecked { s -> (Bool, Bool)? in
            let flags = CGEventSource.flagsState(.hidSystemState).rawValue
            s.held = flags & s.hotkey.deviceMask != 0
            if !s.held { s.cancelledThisPress = false }
            s.touchMask = 0
            return recompute(&s, now: CACurrentMediaTime())
        }
        notify(change)
    }

    func unlatch() {
        let change = state.withLockUnchecked { s -> (Bool, Bool)? in
            s.latched = false
            return recompute(&s, now: CACurrentMediaTime())
        }
        notify(change)
    }

    // MARK: Multitouch thread

    func handleFrame(_ touches: UnsafePointer<MTTouch>?, _ count: Int) {
        let now = CACurrentMediaTime()
        var fired: [PadKey] = []
        var probeLines: [String] = []
        state.withLockUnchecked { s in
            if now - s.lastFrame > frameGap { s.touchMask = 0 }
            s.lastFrame = now
            var mask: UInt64 = 0
            if let touches {
                for i in 0..<count {
                    let t = touches[i]
                    guard t.state == Int32(MTStateMakeTouch) || t.state == Int32(MTStateTouching) else { continue }
                    let bit: UInt64 = 1 << (UInt64(UInt32(bitPattern: t.pathIndex)) & 63)
                    mask |= bit
                    guard s.touchMask & bit == 0 else { continue }

                    // New contact
                    let x = t.normalized.position.x, y = t.normalized.position.y
                    s.lastBeganX = x
                    s.lastBeganY = y
                    let key = s.layout.key(x: x, y: y)
                    if probe {
                        probeLines.append(String(format: "finger %2d  x=%.3f  y=%.3f  → %@", t.pathIndex, x, y, key?.label ?? "–"))
                    }
                    if s.active, s.trigger == .touch, let key, accept(key, &s, now) {
                        fired.append(key)
                    }
                }
            }
            s.touchMask = mask
        }
        for line in probeLines { print(line) }
        for key in fired { emit(key) }
    }

    // MARK: Event tap thread

    /// Returns true if the event must be swallowed.
    func handleTapEvent(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let now = CACurrentMediaTime()
        var swallow = false
        var fire: PadKey?
        let change = state.withLockUnchecked { s -> (Bool, Bool)? in
            switch type {
            case .flagsChanged:
                guard s.enabled, event.getIntegerValueField(.keyboardEventKeycode) == s.hotkey.keyCode else { return nil }
                let down = event.flags.rawValue & s.hotkey.deviceMask != 0
                if down, !s.held {
                    s.held = true
                    s.pressStart = now
                    s.usedThisPress = false
                    s.cancelledThisPress = false
                } else if !down, s.held {
                    s.held = false
                    if !s.usedThisPress, !s.cancelledThisPress, now - s.pressStart < latchTapDuration {
                        s.latched.toggle()
                    }
                }

            case .keyDown:
                guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return nil }
                if s.latched, event.getIntegerValueField(.keyboardEventKeycode) == 53 {  // Esc
                    s.latched = false
                    swallow = true
                } else if s.held {
                    // A regular shortcut with the hotkey – step aside for this press.
                    s.cancelledThisPress = true
                }

            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                let bit = Self.buttonBit(type)
                if s.active || now < s.swallowUntil {
                    s.swallowedButtons |= bit
                    swallow = true
                    if type == .leftMouseDown, s.active, s.trigger == .click,
                       let key = s.layout.key(x: s.lastBeganX, y: s.lastBeganY), accept(key, &s, now) {
                        fire = key
                    }
                } else {
                    s.swallowedButtons &= ~bit
                }

            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                let bit = Self.buttonBit(type)
                if s.swallowedButtons & bit != 0 {
                    s.swallowedButtons &= ~bit
                    swallow = true
                }

            case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                swallow = s.active || s.swallowedButtons & Self.buttonBit(type) != 0

            default:  // moved, scroll, gestures
                swallow = s.active
            }
            return recompute(&s, now: now)
        }
        notify(change)
        if let fire { emit(fire) }
        return swallow
    }

    // MARK: Internals

    private func accept(_ key: PadKey, _ s: inout State, _ now: Double) -> Bool {
        if key == s.lastKey, now - s.lastKeyTime < repeatGuard { return false }
        s.lastKey = key
        s.lastKeyTime = now
        if s.held { s.usedThisPress = true }
        return true
    }

    private func recompute(_ s: inout State, now: Double) -> (Bool, Bool)? {
        let active = s.enabled && ((s.held && !s.cancelledThisPress) || s.latched)
        guard active != s.active || s.latched != s.reportedLatched else { return nil }
        if active != s.active, !active { s.swallowUntil = now + swallowGrace }
        s.active = active
        s.reportedLatched = s.latched
        return (active, s.latched)
    }

    private func notify(_ change: (Bool, Bool)?) {
        guard let change else { return }
        DispatchQueue.main.async { self.onModeChange?(change.0, change.1) }
    }

    private func emit(_ key: PadKey) {
        post(key)
        Feedback.shared.keyPressed()
        DispatchQueue.main.async { self.onKey?(key) }
    }

    private func post(_ key: PadKey) {
        var ch = UniChar(0x30 + key.rawValue)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: keySource, virtualKey: key.keyCode, keyDown: down) else { continue }
            // Explicit flags: a held ⌘/⌥ must not turn the digit into a shortcut.
            e.flags = .maskNumericPad
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            e.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            e.post(tap: .cghidEventTap)
        }
    }

    private static func buttonBit(_ type: CGEventType) -> UInt32 {
        switch type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: 1
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: 2
        default: 4
        }
    }
}
