import AppKit
import CoreImage

/// Lighting on top of the system glass that makes it read as a thick, clear lens (iOS 26 look).
/// The edge glow and glints are overlay-blended: they brighten whatever colour is behind the glass
/// (purple behind → purple shimmer) instead of painting white. Only a faint hairline rim is plain white.
final class GlassSheenView: NSView {
    private let radius: CGFloat
    /// Overlay-blended group: edge glow, glints, soft rim.
    let tinted = CALayer()
    /// Plain hairline rim, defines the shape on any background.
    let hairline = CAGradientLayer()
    private let hairlineMask = CAShapeLayer()
    private let edgeGlow = CAShapeLayer()
    private let edgeMask = CAShapeLayer()
    private let rim = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private let glintClip = CALayer()
    private let topGlint = CAGradientLayer()
    private let bottomGlint = CAGradientLayer()

    init(frame: NSRect, radius: CGFloat) {
        self.radius = radius
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        guard let root = layer else { return }

        tinted.compositingFilter = CIFilter(name: "CIOverlayBlendMode")
        root.addSublayer(tinted)

        // Inner glow: a "shadow" cast inwards from outside the shape – thick, lens-like edges.
        edgeGlow.fillRule = .evenOdd
        edgeGlow.fillColor = NSColor.white.cgColor
        edgeGlow.shadowColor = NSColor.white.cgColor
        edgeGlow.shadowOpacity = 0.9
        edgeGlow.shadowRadius = 5
        edgeGlow.shadowOffset = CGSize(width: 0, height: -1.5)   // light from above
        edgeGlow.mask = edgeMask
        tinted.addSublayer(edgeGlow)

        glintClip.masksToBounds = true
        for g in [topGlint, bottomGlint] {
            g.type = .radial
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 1)
            glintClip.addSublayer(g)
        }
        topGlint.colors = [NSColor.white.withAlphaComponent(0.5).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        bottomGlint.colors = [NSColor.white.withAlphaComponent(1).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        tinted.addSublayer(glintClip)

        // Soft rim (overlay): bright at the top and bottom edge, faint on the sides.
        rim.colors = [1.0, 0.5, 0.15, 0.15, 0.5, 0.9].map { NSColor.white.withAlphaComponent($0).cgColor }
        rim.locations = [0, 0.18, 0.45, 0.6, 0.86, 1]
        rim.startPoint = CGPoint(x: 0.5, y: 1)
        rim.endPoint = CGPoint(x: 0.5, y: 0)
        rimMask.fillColor = nil
        rimMask.strokeColor = NSColor.black.cgColor
        rimMask.lineWidth = 2.5
        rim.mask = rimMask
        tinted.addSublayer(rim)

        hairline.colors = [0.38, 0.10, 0.04, 0.04, 0.10, 0.22].map { NSColor.white.withAlphaComponent($0).cgColor }
        hairline.locations = rim.locations
        hairline.startPoint = rim.startPoint
        hairline.endPoint = rim.endPoint
        hairlineMask.fillColor = nil
        hairlineMask.strokeColor = NSColor.black.cgColor
        hairlineMask.lineWidth = 0.8
        hairline.mask = hairlineMask
        root.addSublayer(hairline)

        relayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Keeps white glyphs readable when the glass sits on something bright.
    static let legibilityShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.55)
        s.shadowBlurRadius = 5
        s.shadowOffset = NSSize(width: 0, height: -0.5)
        return s
    }()

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
    }

    private func relayout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let b = bounds
        let r = min(radius, b.height / 2, b.width / 2)
        let shape = CGPath(roundedRect: b, cornerWidth: r, cornerHeight: r, transform: nil)

        tinted.frame = b

        let outside = CGMutablePath()
        outside.addRect(b.insetBy(dx: -24, dy: -24))
        outside.addPath(shape)
        edgeGlow.frame = b
        edgeGlow.path = outside
        edgeMask.frame = b
        edgeMask.path = shape

        glintClip.frame = b
        glintClip.cornerRadius = r
        topGlint.frame = CGRect(x: b.width * 0.02, y: b.height * 0.55, width: b.width * 0.6, height: b.height * 0.55)
        bottomGlint.frame = CGRect(x: b.midX - b.width * 0.28, y: -b.height * 0.07, width: b.width * 0.56, height: b.height * 0.2)

        rim.frame = b
        rimMask.frame = b
        let inset = rimMask.lineWidth / 2
        rimMask.path = CGPath(roundedRect: b.insetBy(dx: inset, dy: inset), cornerWidth: r - inset, cornerHeight: r - inset, transform: nil)
        hairline.frame = b
        hairlineMask.frame = b
        let hi = hairlineMask.lineWidth / 2
        hairlineMask.path = CGPath(roundedRect: b.insetBy(dx: hi, dy: hi), cornerWidth: r - hi, cornerHeight: r - hi, transform: nil)
        CATransaction.commit()
    }
}

/// Offscreen approximation of the "Glas" design for `--render` (the real blur comes from the window server).
enum GlassPreview {
    static func draw(into ctx: CGContext, canvas: CGSize, origin: CGPoint, keyFrames: [PadKey: CGRect], displayFrame: CGRect,
                     typed: String, pressed: PadKey, latched: Bool, scale: CGFloat) {
        guard let snapshot = ctx.makeImage() else { return }
        let ci = CIImage(cgImage: snapshot).clampedToExtent()
            .applyingGaussianBlur(sigma: 2.5 * scale).cropped(to: CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height))
        guard let blurred = CIContext().createCGImage(ci, from: ci.extent) else { return }

        func glass(_ rect: CGRect, radius: CGFloat, glow: Bool) {
            let r = rect.offsetBy(dx: origin.x, dy: origin.y)
            let rr = min(radius, r.height / 2)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.25).cgColor)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: rr, cornerHeight: rr, transform: nil))
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.05).cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: rr, cornerHeight: rr, transform: nil))
            ctx.clip()
            // Slight magnification, like the lens edge of Liquid Glass.
            let mag: CGFloat = 1.06
            let full = CGRect(origin: .zero, size: canvas)
            let zoomed = CGRect(x: r.midX - (r.midX - full.minX) * mag, y: r.midY - (r.midY - full.minY) * mag,
                                width: full.width * mag, height: full.height * mag)
            ctx.draw(blurred, in: zoomed)
            if glow {
                ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor)
                ctx.fill(r)
            }
            ctx.restoreGState()

            let sheen = GlassSheenView(frame: NSRect(origin: .zero, size: r.size), radius: radius)
            ctx.saveGState()
            ctx.translateBy(x: r.minX, y: r.minY)
            ctx.setBlendMode(.overlay)
            sheen.tinted.render(in: ctx)
            ctx.setBlendMode(.normal)
            sheen.hairline.render(in: ctx)
            ctx.restoreGState()
        }

        let shadow = GlassSheenView.legibilityShadow
        func text(_ s: String, _ font: NSFont, in rect: CGRect, align: NSTextAlignment = .center, color: NSColor = .white) {
            let p = NSMutableParagraphStyle()
            p.alignment = align
            let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p, .shadow: shadow])
            let h = a.size().height
            let r = rect.offsetBy(dx: origin.x, dy: origin.y)
            a.draw(in: CGRect(x: r.minX, y: r.midY - h / 2, width: r.width, height: h))
        }

        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (key, rect) in keyFrames {
            let r = key == pressed ? rect.insetBy(dx: -3.5, dy: -3.5) : rect
            glass(r, radius: 25, glow: key == pressed)
            text(key.label, key == .delete ? .systemFont(ofSize: 22) : NSFont.systemFont(ofSize: 24, weight: .medium).roundedVariant, in: r)
        }
        glass(displayFrame, radius: 20, glow: false)
        let d = displayFrame
        text("NUMPAD", .systemFont(ofSize: 10, weight: .semibold), in: CGRect(x: d.minX + 14, y: d.maxY - 24, width: 120, height: 14),
             align: .left, color: NSColor.white.withAlphaComponent(0.85))
        text(typed, NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .light).roundedVariant,
             in: CGRect(x: d.minX + 12, y: d.minY + 6, width: d.width - 26, height: 40), align: .right)
        if latched {
            let pill = CGRect(x: d.maxX - 14 - 58, y: d.maxY - 25, width: 58, height: 16).offsetBy(dx: origin.x, dy: origin.y)
            ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 8, cornerHeight: 8, transform: nil))
            ctx.setFillColor(NSColor.controlAccentColor.cgColor)
            ctx.fillPath()
            text("FIXIERT", .systemFont(ofSize: 9, weight: .bold), in: pill.offsetBy(dx: -origin.x, dy: -origin.y))
        }
    }
}
