import AppKit

/// "Glas" design on macOS 26: every key and the display are individual, see-through Liquid Glass
/// elements floating on the desktop (no backing slab). They share one NSGlassEffectContainerView,
/// so a pressed key that bulges towards its neighbours briefly melts into them.
@available(macOS 26.0, *)
final class LiquidGlassBoard: NSView {
    /// Glass shapes closer than this merge. Resting gap is larger, so only a pressed (bulged) key merges.
    private static let mergeSpacing: CGFloat = 7
    private static let bulge: CGFloat = 3.5

    private let container = NSGlassEffectContainerView()
    private var keys: [PadKey: (glass: NSGlassEffectView, glow: NSView, rest: CGRect)] = [:]
    private var generation: [PadKey: Int] = [:]
    private let display = NSTextField(labelWithString: "")
    private let pill = NSView()


    init(frame: NSRect, keyFrames: [PadKey: CGRect], displayFrame: CGRect) {
        super.init(frame: frame)
        container.frame = bounds
        container.autoresizingMask = [.width, .height]
        container.spacing = Self.mergeSpacing
        let content = NSView(frame: bounds)
        container.contentView = content
        addSubview(container)

        for (key, rect) in keyFrames {
            let glass = makeGlass(rect, radius: 25)
            let host = NSView(frame: glass.bounds)
            glass.contentView = host
            // Tint on clear glass is barely visible, so the press colour is its own fading layer.
            let glow = NSView(frame: host.bounds)
            glow.autoresizingMask = [.width, .height]
            glow.wantsLayer = true
            glow.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            glow.layer?.cornerRadius = 25
            glow.alphaValue = 0
            host.addSubview(glow)
            let label = Self.label(key.label, font: key == .delete
                ? .systemFont(ofSize: 22, weight: .regular)
                : Self.rounded(24, .medium))
            center(label, inView: host)
            content.addSubview(glass)
            keys[key] = (glass, glow, rect)
        }

        let displayGlass = makeGlass(displayFrame, radius: 20)
        let dc = NSView(frame: NSRect(origin: .zero, size: displayFrame.size))
        displayGlass.contentView = dc

        let caption = Self.label("", font: .systemFont(ofSize: 10, weight: .semibold))
        caption.attributedStringValue = NSAttributedString(string: "NUMPAD", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.8),
            .kern: 1.2,
        ])
        caption.frame = NSRect(x: 14, y: displayFrame.height - 24, width: 120, height: 14)
        dc.addSubview(caption)

        display.font = NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .light).roundedVariant
        display.textColor = .white
        display.alignment = .right
        display.lineBreakMode = .byTruncatingHead
        display.shadow = Self.legibilityShadow
        display.frame = NSRect(x: 12, y: 4, width: displayFrame.width - 26, height: 40)
        dc.addSubview(display)

        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        pill.layer?.cornerRadius = 8
        pill.frame = NSRect(x: displayFrame.width - 14 - 58, y: displayFrame.height - 25, width: 58, height: 16)
        let pillLabel = Self.label("", font: .systemFont(ofSize: 9, weight: .bold))
        pillLabel.attributedStringValue = NSAttributedString(string: "FIXIERT", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: NSColor.white, .kern: 0.8,
        ])
        pillLabel.shadow = nil
        center(pillLabel, inView: pill)
        pill.isHidden = true
        dc.addSubview(pill)

        content.addSubview(displayGlass)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setTyped(_ s: String) { display.stringValue = s }
    func setLatched(_ latched: Bool) { pill.isHidden = !latched }

    /// Showcase only: hold a key in its pressed state.
    func hold(_ key: PadKey) {
        guard let k = keys[key] else { return }
        k.glass.frame = k.rest.insetBy(dx: -Self.bulge, dy: -Self.bulge)
        k.glow.alphaValue = 1
    }

    /// Bulge + tint instantly, then flow back with a slight overshoot.
    func press(_ key: PadKey) {
        guard let k = keys[key] else { return }
        let gen = (generation[key] ?? 0) + 1
        generation[key] = gen
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            k.glass.frame = k.rest.insetBy(dx: -Self.bulge, dy: -Self.bulge)
            k.glow.alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.generation[key] == gen else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.35, 0.45, 1)
                ctx.allowsImplicitAnimation = true
                k.glass.animator().frame = k.rest
                k.glow.animator().alphaValue = 0
            }
        }
    }

    // MARK: Helpers

    private func makeGlass(_ rect: CGRect, radius: CGFloat) -> NSGlassEffectView {
        let g = NSGlassEffectView(frame: rect)
        g.style = .clear
        g.cornerRadius = radius
        return g
    }

    private func center(_ label: NSTextField, inView host: NSView) {
        label.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: host.centerYAnchor, constant: 0.5),
        ])
    }

    private static let legibilityShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.35)
        s.shadowBlurRadius = 3
        s.shadowOffset = NSSize(width: 0, height: -0.5)
        return s
    }()

    private static func label(_ text: String, font: NSFont) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.textColor = .white
        l.shadow = legibilityShadow
        return l
    }

    private static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight).roundedVariant
    }
}

extension NSFont {
    var roundedVariant: NSFont {
        guard let d = fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: pointSize) else { return self }
        return f
    }
}
