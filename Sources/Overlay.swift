import AppKit
import QuartzCore

/// Small floating numpad HUD. Built once, then only ordered in/out – no animations.
final class Overlay {
    private static let pad: CGFloat = 12
    private static let gap: CGFloat = 6
    private static let cellW: CGFloat = 58
    private static let cellH: CGFloat = 44
    private static let displayH: CGFloat = 44
    private static let width = pad * 2 + cellW * 3 + gap * 2
    private static let height = pad * 2 + displayH + gap + cellH * 4 + gap * 3

    private let panel: NSPanel
    private let host: NSView
    private var cells: [PadKey: CALayer] = [:]
    private var textLayers: [CATextLayer] = []
    private var flashGeneration: [PadKey: Int] = [:]
    private let display = CATextLayer()
    private let badge = CATextLayer()
    private var typed = ""

    private let idleColor = NSColor.white.withAlphaComponent(0.10).cgColor

    init() {
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

        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.appearance = NSAppearance(named: .vibrantDark)
        fx.maskImage = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
            return true
        }
        panel.contentView = fx

        host = NSView(frame: fx.bounds)
        host.wantsLayer = true
        fx.addSubview(host)
        buildLayers()
    }

    private func buildLayers() {
        guard let root = host.layer else { return }
        let p = Self.pad, g = Self.gap, w = Self.cellW, h = Self.cellH

        func cell(_ key: PadKey, _ frame: CGRect) {
            let l = CALayer()
            l.frame = frame
            l.cornerRadius = 9
            l.backgroundColor = idleColor
            let t = makeText(key.label, size: 22, weight: .medium, in: l.bounds, align: .center)
            l.addSublayer(t)
            root.addSublayer(l)
            cells[key] = l
        }

        // Bottom-up, matching the trackpad: 1 2 3 / 4 5 6 / 7 8 9 / 0
        for row in 0..<3 {
            for col in 0..<3 {
                let key = PadKey(rawValue: row * 3 + col + 1)!
                cell(key, CGRect(x: p + CGFloat(col) * (w + g), y: p + CGFloat(row) * (h + g), width: w, height: h))
            }
        }
        cell(.d0, CGRect(x: p, y: p + 3 * (h + g), width: w * 3 + g * 2, height: h))

        let displayFrame = CGRect(x: p, y: p + 4 * (h + g), width: w * 3 + g * 2, height: Self.displayH)
        let bg = CALayer()
        bg.frame = displayFrame
        bg.cornerRadius = 9
        bg.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        root.addSublayer(bg)

        configureText(display, size: 26, weight: .regular, in: bg.bounds.insetBy(dx: 10, dy: 0), align: .right, monospaced: true)
        bg.addSublayer(display)
        configureText(badge, size: 10, weight: .semibold, in: CGRect(x: 8, y: bg.bounds.height - 16, width: 80, height: 14), align: .left)
        badge.foregroundColor = NSColor.controlAccentColor.cgColor
        badge.string = ""
        bg.addSublayer(badge)
    }

    private func makeText(_ s: String, size: CGFloat, weight: NSFont.Weight, in bounds: CGRect, align: CATextLayerAlignmentMode) -> CATextLayer {
        let t = CATextLayer()
        configureText(t, size: size, weight: weight, in: bounds, align: align)
        t.string = s
        return t
    }

    /// CATextLayer draws top-aligned; centre one line vertically inside `bounds`.
    private func configureText(_ t: CATextLayer, size: CGFloat, weight: NSFont.Weight, in bounds: CGRect,
                               align: CATextLayerAlignmentMode, monospaced: Bool = false) {
        let font = monospaced ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                              : NSFont.systemFont(ofSize: size, weight: weight)
        let lineH = ceil(font.ascender - font.descender + font.leading)
        t.font = font
        t.fontSize = size
        t.alignmentMode = align
        t.foregroundColor = NSColor.white.cgColor
        t.truncationMode = .start
        t.frame = CGRect(x: bounds.minX, y: bounds.midY - lineH / 2, width: bounds.width, height: lineH)
        textLayers.append(t)
    }

    // MARK: Public

    func show(latched: Bool) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = screen.backingScaleFactor
        for t in textLayers where t.contentsScale != scale { t.contentsScale = scale }
        badge.string = latched ? "FIXIERT" : ""
        CATransaction.commit()

        let vf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.maxX - Self.width - 20, y: vf.minY + 20))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel.orderOut(nil)
        typed = ""
        display.string = ""
    }

    func flash(_ key: PadKey) {
        typed.append(key.label)
        if typed.count > 24 { typed.removeFirst(typed.count - 24) }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        display.string = typed
        cells[key]?.backgroundColor = NSColor.controlAccentColor.cgColor
        CATransaction.commit()

        let gen = (flashGeneration[key] ?? 0) + 1
        flashGeneration[key] = gen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.flashGeneration[key] == gen else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.cells[key]?.backgroundColor = self.idleColor
            CATransaction.commit()
        }
    }
}
