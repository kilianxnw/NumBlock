import AppKit

enum ThemeID: String, CaseIterable {
    case auto, light, dark, glass, calculator, aurora

    var title: String {
        switch self {
        case .auto: "Automatisch (Hell/Dunkel)"
        case .light: "Hell"
        case .dark: "Dunkel"
        case .glass: "Glas"
        case .calculator: "Rechner"
        case .aurora: "Aurora"
        }
    }

    /// Resolves `.auto` against the current system appearance.
    func resolved() -> Theme {
        switch self {
        case .auto:
            let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        case .glass: return .glass
        case .calculator: return .calculator
        case .aurora: return .aurora
        }
    }

    /// Small menu swatch: panel colour with a key on it.
    var swatch: NSImage {
        let theme = resolved()
        return NSImage(size: NSSize(width: 18, height: 14), flipped: false) { r in
            let bg = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            if case .gradient(let colors) = theme.background {
                NSGradient(colors: colors)?.draw(in: bg, angle: -35)
            } else {
                theme.swatchColor.setFill()
                bg.fill()
            }
            NSColor.black.withAlphaComponent(0.15).setStroke()
            bg.lineWidth = 0.5
            bg.stroke()
            let key = NSBezierPath(roundedRect: NSRect(x: 4, y: 3.5, width: 10, height: 7), xRadius: 3.5, yRadius: 3.5)
            theme.keyPressed.setFill()
            key.fill()
            return true
        }
    }
}

struct Theme {
    enum Background {
        case material(NSVisualEffectView.Material)
        case glass
        case solid(NSColor)
        case gradient([NSColor])
    }

    var background: Background
    var dark: Bool
    var swatchColor: NSColor

    var keyFill: NSColor
    var keyPressed: NSColor
    var keyText: NSColor
    var keyPressedText: NSColor
    var keyBorder: NSColor?
    var keyShadow = false
    var capsuleKeys = false
    var keyRadius: CGFloat = 12
    var roundedFont = false
    var keyFontWeight: NSFont.Weight = .medium

    var displayFill: NSColor
    var displayText: NSColor
    var displayWeight: NSFont.Weight = .light
    var captionText: NSColor
    var pillFill: NSColor
    var pillText: NSColor = .white

    var accent: NSColor { .controlAccentColor }

    static var light: Theme {
        Theme(background: .material(.popover), dark: false, swatchColor: NSColor(white: 0.93, alpha: 1),
              keyFill: NSColor.white.withAlphaComponent(0.9),
              keyPressed: .controlAccentColor,
              keyText: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
              keyPressedText: .white,
              keyBorder: NSColor.black.withAlphaComponent(0.06),
              keyShadow: true,
              displayFill: NSColor.black.withAlphaComponent(0.045),
              displayText: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
              captionText: NSColor.black.withAlphaComponent(0.45),
              pillFill: .controlAccentColor)
    }

    static var dark: Theme {
        Theme(background: .material(.hudWindow), dark: true, swatchColor: NSColor(white: 0.17, alpha: 1),
              keyFill: NSColor.white.withAlphaComponent(0.10),
              keyPressed: .controlAccentColor,
              keyText: .white,
              keyPressedText: .white,
              keyBorder: NSColor.white.withAlphaComponent(0.08),
              displayFill: NSColor.black.withAlphaComponent(0.28),
              displayText: .white,
              captionText: NSColor.white.withAlphaComponent(0.5),
              pillFill: .controlAccentColor)
    }

    static var glass: Theme {
        Theme(background: .glass, dark: true, swatchColor: NSColor(srgbRed: 0.55, green: 0.66, blue: 0.78, alpha: 1),
              keyFill: NSColor.white.withAlphaComponent(0.16),
              keyPressed: NSColor.white.withAlphaComponent(0.92),
              keyText: .white,
              keyPressedText: NSColor(srgbRed: 0.08, green: 0.1, blue: 0.14, alpha: 1),
              keyBorder: NSColor.white.withAlphaComponent(0.28),
              capsuleKeys: true,
              roundedFont: true,
              displayFill: NSColor.white.withAlphaComponent(0.08),
              displayText: .white,
              captionText: NSColor.white.withAlphaComponent(0.6),
              pillFill: NSColor.white.withAlphaComponent(0.9),
              pillText: NSColor(srgbRed: 0.08, green: 0.1, blue: 0.14, alpha: 1))
    }

    /// Apple Calculator: black, graphite capsules, orange highlight.
    static var calculator: Theme {
        let orange = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)
        return Theme(background: .solid(NSColor(white: 0.0, alpha: 0.96)), dark: true, swatchColor: .black,
                     keyFill: NSColor(white: 0.2, alpha: 1),
                     keyPressed: orange,
                     keyText: .white,
                     keyPressedText: .white,
                     keyBorder: nil,
                     capsuleKeys: true,
                     keyFontWeight: .regular,
                     displayFill: .clear,
                     displayText: .white,
                     displayWeight: .thin,
                     captionText: NSColor(white: 0.55, alpha: 1),
                     pillFill: orange)
    }

    static var aurora: Theme {
        Theme(background: .gradient([
                  NSColor(srgbRed: 0.29, green: 0.33, blue: 0.95, alpha: 1),
                  NSColor(srgbRed: 0.66, green: 0.32, blue: 0.93, alpha: 1),
                  NSColor(srgbRed: 1.0, green: 0.42, blue: 0.55, alpha: 1),
              ]),
              dark: true, swatchColor: NSColor(srgbRed: 0.6, green: 0.35, blue: 0.9, alpha: 1),
              keyFill: NSColor.white.withAlphaComponent(0.2),
              keyPressed: .white,
              keyText: .white,
              keyPressedText: NSColor(srgbRed: 0.42, green: 0.27, blue: 0.9, alpha: 1),
              keyBorder: NSColor.white.withAlphaComponent(0.3),
              keyRadius: 14,
              roundedFont: true,
              keyFontWeight: .semibold,
              displayFill: NSColor.black.withAlphaComponent(0.16),
              displayText: .white,
              displayWeight: .regular,
              captionText: NSColor.white.withAlphaComponent(0.75),
              pillFill: .white,
              pillText: NSColor(srgbRed: 0.42, green: 0.27, blue: 0.9, alpha: 1))
    }

    func font(size: CGFloat, weight: NSFont.Weight, monospacedDigits: Bool = false) -> NSFont {
        var font = monospacedDigits ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                                    : NSFont.systemFont(ofSize: size, weight: weight)
        if roundedFont, let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) {
            font = f
        }
        return font
    }
}
