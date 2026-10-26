import CoreGraphics

enum PadKey: Int, CaseIterable {
    case d0 = 0, d1, d2, d3, d4, d5, d6, d7, d8, d9

    /// kVK_ANSI_Keypad0…9 (note the gap at 0x5A)
    var keyCode: CGKeyCode {
        switch self {
        case .d0: 0x52
        case .d1: 0x53
        case .d2: 0x54
        case .d3: 0x55
        case .d4: 0x56
        case .d5: 0x57
        case .d6: 0x58
        case .d7: 0x59
        case .d8: 0x5B
        case .d9: 0x5C
        }
    }

    var label: String { String(rawValue) }
}

/// Maps a normalized trackpad position (0…1, origin bottom-left) to a key.
///
///     left half: ignored │        0
///                        │  7  │  8  │  9
///                        │  4  │  5  │  6
///                        │  1  │  2  │  3
struct PadLayout {
    /// Pad starts at this x; everything left of it is ignored.
    var splitX: Float = 0.5
    /// Height of the top "0" band as a fraction of the pad height.
    var zeroBand: Float = 0.25

    func key(x: Float, y: Float) -> PadKey? {
        guard x >= splitX else { return nil }
        let y = min(max(y, 0), 1)
        if y >= 1 - zeroBand { return .d0 }
        let u = min(max((x - splitX) / (1 - splitX), 0), 0.9999)
        let v = min(max(y / (1 - zeroBand), 0), 0.9999)
        let row = Int(v * 3)   // 0 = bottom row (1 2 3)
        let col = Int(u * 3)
        return PadKey(rawValue: row * 3 + col + 1)
    }
}
