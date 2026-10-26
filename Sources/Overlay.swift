import AppKit
import QuartzCore

/// Floating numpad HUD mirroring the trackpad layout. Built once; showing it is only orderFront/orderOut.
///
///     ┌───────────────────────────────┐
///     │ NUMPAD                FIXIERT │
///     │                         1234  │
///     ├────────┬──────┬──────┬──────┤
///     │   ⌫    │  7   │  8   │  9   │
///     │        │  4   │  5   │  6   │
///     │   0    │  1   │  2   │  3   │
///     └────────┴──────┴──────┴──────┘
final class Overlay {
    private static let pad: CGFloat = 14
    private static let gap: CGFloat = 8
    private static let cellW: CGFloat = 58
    private static let cellH: CGFloat = 50
    private static let leftW: CGFloat = 72
    private static let displayH: CGFloat = 64
    private static let gridH = cellH * 3 + gap * 2
    static let width = pad * 2 + leftW + gap + cellW * 3 + gap * 2
    static let height = pad * 2 + displayH + gap + gridH
    private static let windowRadius: CGFloat = 24

    static let keyFrames: [PadKey: CGRect] = {
        let p = pad, g = gap, w = cellW, h = cellH
        let gridX = p + leftW + g
        var frames: [PadKey: CGRect] = [:]
        for row in 0..<3 {
            for col in 0..<3 {
                frames[PadKey(rawValue: row * 3 + col + 1)!] =
                    CGRect(x: gridX + CGFloat(col) * (w + g), y: p + CGFloat(row) * (h + g), width: w, height: h)
            }
        }
        let leftH = (gridH - g) / 2
        frames[.d0] = CGRect(x: p, y: p, width: leftW, height: leftH)
        frames[.delete] = CGRect(x: p, y: p + leftH + g, width: leftW, height: leftH)
        return frames
    }()
    static let displayFrame = CGRect(x: pad, y: pad + gridH + gap, width: width - 2 * pad, height: displayH)

    private struct KeyLayers {
        let bg: CALayer
        let text: CATextLayer
    }

    private let panel: NSPanel
    private let container: NSView
    private let host: NSView
    private var backgroundView: NSView?
    /// LiquidGlassBoard while the "Glas" design is active on macOS 26.
    private var glassBoard: NSView?
    @available(macOS 26.0, *)
    private var liquid: LiquidGlassBoard? { glassBoard as? LiquidGlassBoard }
    private var keys: [PadKey: KeyLayers] = [:]
    private var flashGeneration: [PadKey: Int] = [:]

    private let displayBG = CALayer()
    private let display = CATextLayer()
    private let caption = CATextLayer()
    private let pill = CALayer()
    private let pillText = CATextLayer()

    private var themeID: ThemeID
    private var theme: Theme
    private var typed = ""
    private var shownByMode = false
    private var previewHide: DispatchWorkItem?

    init(theme id: ThemeID) {
        themeID = id
        theme = id.resolved()
        let size = NSSize(width: Self.width, height: Self.height)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        container = NSView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = container
        host = NSView(frame: container.bounds)
        host.wantsLayer = true
        host.autoresizingMask = [.width, .height]

        buildLayers()
        applyTheme()
    }

    // MARK: Public

    func setTheme(_ id: ThemeID) {
        themeID = id
        theme = id.resolved()
        applyTheme()
    }

    /// Shown while the numpad mode is active.
    func show(latched: Bool) {
        shownByMode = true
        previewHide?.cancel()
        present(latched: latched)
    }

    func hide() {
        shownByMode = false
        previewHide?.cancel()
        panel.orderOut(nil)
        setTyped("")
    }

    func flash(_ key: PadKey) {
        if key == .delete {
            if !typed.isEmpty { typed.removeLast() }
        } else {
            typed.append(key.label)
            if typed.count > 18 { typed.removeFirst(typed.count - 18) }
        }
        setTyped(typed)
        press(key)
    }

    /// Short demo after picking a design in the menu.
    func preview() {
        guard !shownByMode else { return }
        present(latched: false)
        let demo: [PadKey] = [.d4, .d2, .d7, .delete, .d0]
        for (i, k) in demo.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(i) * 0.18) { [weak self] in
                guard let self, !self.shownByMode, self.panel.isVisible else { return }
                self.flash(k)
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.shownByMode else { return }
            self.hide()
        }
        previewHide?.cancel()
        previewHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    /// Diagnostics (`--showcase`): place at a fixed origin with sample content and one key held down.
    func showcase(at origin: NSPoint, typed sample: String, pressed: PadKey, latched: Bool) {
        present(latched: latched, origin: origin)
        setTyped(sample)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let k = keys[pressed] {
            k.bg.backgroundColor = theme.keyPressed.cgColor
            k.text.foregroundColor = theme.keyPressedText.cgColor
        }
        CATransaction.commit()
        if #available(macOS 26.0, *) { liquid?.hold(pressed) }
    }

    var frame: NSRect { panel.frame }

    /// Diagnostics (`--render`): draws the overlay offscreen into `ctx` at `origin` (points).
    /// Blur materials are approximated with flat translucent fills.
    func render(into ctx: CGContext, at origin: CGPoint, typed sample: String, pressed: PadKey, latched: Bool, scale: CGFloat) {
        setScale(scale)
        setTyped(sample)
        pill.isHidden = !latched
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let k = keys[pressed] {
            k.bg.backgroundColor = theme.keyPressed.cgColor
            k.text.foregroundColor = theme.keyPressedText.cgColor
        }
        CATransaction.commit()

        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        let rect = CGRect(x: 0, y: 0, width: Self.width, height: Self.height)
        let path = CGPath(roundedRect: rect, cornerWidth: Self.windowRadius, cornerHeight: Self.windowRadius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.01).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.clip()
        switch theme.background {
        case .material(let m):
            ctx.setFillColor((m == .popover ? NSColor(white: 0.96, alpha: 0.9) : NSColor(white: 0.13, alpha: 0.88)).cgColor)
            ctx.fill(rect)
        case .glass:
            ctx.setFillColor(NSColor(white: 1, alpha: 0.10).cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor(white: 1, alpha: 0.45).cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(path)
            ctx.strokePath()
        case .solid(let c):
            ctx.setFillColor(c.cgColor)
            ctx.fill(rect)
        case .gradient(let colors):
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map(\.cgColor) as CFArray, locations: nil)!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: rect.maxX, y: 0), options: [])
        }
        host.layer?.render(in: ctx)
        ctx.restoreGState()
    }

    // MARK: Layout

    private func buildLayers() {
        guard let root = host.layer else { return }
        for (k, frame) in Self.keyFrames {
            let bg = CALayer()
            bg.frame = frame
            bg.cornerCurve = .continuous
            let text = CATextLayer()
            text.alignmentMode = .center
            bg.addSublayer(text)
            root.addSublayer(bg)
            keys[k] = KeyLayers(bg: bg, text: text)
        }

        displayBG.frame = Self.displayFrame
        displayBG.cornerCurve = .continuous
        displayBG.cornerRadius = 14
        root.addSublayer(displayBG)

        display.alignmentMode = .right
        display.truncationMode = .start
        caption.alignmentMode = .left
        displayBG.addSublayer(display)
        displayBG.addSublayer(caption)

        pill.cornerCurve = .continuous
        pillText.alignmentMode = .center
        pill.addSublayer(pillText)
        displayBG.addSublayer(pill)
    }

    private func applyTheme() {
        installBackground()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let t = theme
        for (k, l) in keys {
            let b = l.bg.bounds
            l.bg.backgroundColor = t.keyFill.cgColor
            // Capsules use circular corners (continuous ones bulge at 50 %); the tall ⌫/0 keys keep the row's radius.
            l.bg.cornerRadius = t.capsuleKeys ? Self.cellH / 2 : t.keyRadius
            l.bg.cornerCurve = t.capsuleKeys ? .circular : .continuous
            l.bg.borderWidth = t.keyBorder == nil ? 0 : 0.75
            l.bg.borderColor = t.keyBorder?.cgColor
            if t.keyShadow {
                l.bg.shadowColor = NSColor.black.cgColor
                l.bg.shadowOpacity = 0.12
                l.bg.shadowRadius = 1.5
                l.bg.shadowOffset = CGSize(width: 0, height: -1)
                l.bg.shadowPath = CGPath(roundedRect: b, cornerWidth: l.bg.cornerRadius, cornerHeight: l.bg.cornerRadius, transform: nil)
            } else {
                l.bg.shadowOpacity = 0
            }
            let size: CGFloat = k == .delete ? 22 : 24
            let font = k == .delete ? NSFont.systemFont(ofSize: size, weight: .regular) : t.font(size: size, weight: t.keyFontWeight)
            l.text.string = k.label
            l.text.foregroundColor = t.keyText.cgColor
            place(l.text, font: font, in: b)
        }

        displayBG.backgroundColor = t.displayFill.cgColor
        let db = displayBG.bounds
        let digitFont = t.font(size: 32, weight: t.displayWeight, monospacedDigits: true)
        display.foregroundColor = t.displayText.cgColor
        place(display, font: digitFont, in: CGRect(x: 12, y: 4, width: db.width - 24, height: db.height - 22))

        let capFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        caption.string = NSAttributedString(string: "NUMPAD", attributes: [
            .font: capFont, .foregroundColor: t.captionText, .kern: 1.2,
        ])
        place(caption, font: capFont, in: CGRect(x: 12, y: db.height - 22, width: 120, height: 16), setFont: false)

        let pillFont = NSFont.systemFont(ofSize: 9, weight: .bold)
        pill.frame = CGRect(x: db.width - 12 - 58, y: db.height - 23, width: 58, height: 16)
        pill.cornerRadius = 8
        pill.backgroundColor = t.pillFill.cgColor
        pillText.string = NSAttributedString(string: "FIXIERT", attributes: [
            .font: pillFont, .foregroundColor: t.pillText, .kern: 0.8,
        ])
        place(pillText, font: pillFont, in: pill.bounds, setFont: false)
        CATransaction.commit()

        let scale = panel.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        setScale(scale)
        panel.invalidateShadow()
    }

    private func installBackground() {
        backgroundView?.removeFromSuperview()
        host.removeFromSuperview()
        glassBoard = nil
        panel.hasShadow = true
        let bounds = container.bounds
        let r = Self.windowRadius
        container.appearance = NSAppearance(named: theme.dark ? .darkAqua : .aqua)

        func plainLayerView() -> NSView {
            let v = NSView(frame: bounds)
            v.wantsLayer = true
            v.layer?.cornerRadius = r
            v.layer?.cornerCurve = .continuous
            v.layer?.masksToBounds = true
            v.layer?.borderWidth = 0.5
            v.layer?.borderColor = NSColor.white.withAlphaComponent(theme.dark ? 0.12 : 0.5).cgColor
            return v
        }

        func material(_ m: NSVisualEffectView.Material) -> NSView {
            let fx = NSVisualEffectView(frame: bounds)
            fx.material = m
            fx.blendingMode = .behindWindow
            fx.state = .active
            fx.maskImage = NSImage(size: bounds.size, flipped: false) { rect in
                NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
                return true
            }
            return fx
        }

        var view: NSView
        var hostInside = false
        switch theme.background {
        case .material(let m):
            view = material(m)
        case .glass:
            if #available(macOS 26.0, *) {
                // Floating glass keys, no slab; the glass casts its own shadow.
                let board = LiquidGlassBoard(frame: bounds, keyFrames: Self.keyFrames, displayFrame: Self.displayFrame)
                board.setTyped(typed)
                view = board
                glassBoard = board
                hostInside = true
                panel.hasShadow = false
            } else {
                view = material(.hudWindow)
            }
        case .solid(let color):
            view = plainLayerView()
            view.layer?.backgroundColor = color.cgColor
        case .gradient(let colors):
            view = plainLayerView()
            let g = CAGradientLayer()
            g.frame = bounds
            g.colors = colors.map(\.cgColor)
            g.startPoint = CGPoint(x: 0, y: 1)
            g.endPoint = CGPoint(x: 1, y: 0)
            view.layer?.addSublayer(g)
        }
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        if !hostInside {
            host.frame = container.bounds
            container.addSubview(host)
        }
        backgroundView = view
    }

    /// CATextLayer draws from the top; position it so the glyphs' cap height is centred in `rect`.
    private func place(_ t: CATextLayer, font: NSFont, in rect: CGRect, setFont: Bool = true) {
        if setFont {
            t.font = font
            t.fontSize = font.pointSize
        }
        let lineH = ceil(font.ascender - font.descender)
        let top = rect.midY - font.capHeight / 2 + font.ascender
        t.frame = CGRect(x: rect.minX, y: top - lineH, width: rect.width, height: lineH)
    }

    private func setScale(_ scale: CGFloat) {
        let texts = keys.values.map(\.text) + [display, caption, pillText]
        for t in texts where t.contentsScale != scale { t.contentsScale = scale }
    }

    // MARK: Showing

    private func present(latched: Bool, origin: NSPoint? = nil) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        if themeID == .auto {
            let resolved = themeID.resolved()
            if resolved.dark != theme.dark {
                theme = resolved
                applyTheme()
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setScale(screen.backingScaleFactor)
        pill.isHidden = !latched
        CATransaction.commit()
        if #available(macOS 26.0, *) { liquid?.setLatched(latched) }

        let vf = screen.visibleFrame
        panel.setFrameOrigin(origin ?? NSPoint(x: vf.maxX - Self.width - 20, y: vf.minY + 20))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func setTyped(_ s: String) {
        typed = s
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        display.string = s
        CATransaction.commit()
        if #available(macOS 26.0, *) { liquid?.setTyped(s) }
    }

    /// Instant highlight + squeeze, then a short spring back.
    private func press(_ key: PadKey) {
        if #available(macOS 26.0, *), let liquid {
            liquid.press(key)
            return
        }
        guard let l = keys[key] else { return }
        let t = theme
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.bg.removeAllAnimations()
        l.text.removeAllAnimations()
        l.bg.backgroundColor = t.keyPressed.cgColor
        l.text.foregroundColor = t.keyPressedText.cgColor
        l.bg.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        CATransaction.commit()

        let gen = (flashGeneration[key] ?? 0) + 1
        flashGeneration[key] = gen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            guard let self, self.flashGeneration[key] == gen else { return }
            self.release(l)
        }
    }

    private func release(_ l: KeyLayers) {
        let t = theme
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.92
        spring.toValue = 1.0
        spring.mass = 0.6
        spring.stiffness = 420
        spring.damping = 13
        spring.duration = spring.settlingDuration
        l.bg.transform = CATransform3DIdentity
        l.bg.add(spring, forKey: "scale")

        let fade = CABasicAnimation(keyPath: "backgroundColor")
        fade.fromValue = t.keyPressed.cgColor
        fade.toValue = t.keyFill.cgColor
        fade.duration = 0.22
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        l.bg.backgroundColor = t.keyFill.cgColor
        l.bg.add(fade, forKey: "fill")

        let textFade = CABasicAnimation(keyPath: "foregroundColor")
        textFade.fromValue = t.keyPressedText.cgColor
        textFade.toValue = t.keyText.cgColor
        textFade.duration = 0.22
        l.text.foregroundColor = t.keyText.cgColor
        l.text.add(textFade, forKey: "text")

        CATransaction.commit()
    }
}
