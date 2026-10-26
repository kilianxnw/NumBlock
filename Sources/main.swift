import AppKit

let args = CommandLine.arguments

if args.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}

if args.contains("--probe") {
    // Prints every new finger contact with its position and mapped key.
    setvbuf(stdout, nil, _IOLBF, 0)
    Engine.shared.probe = true
    let n = Multitouch.start()
    print("TrackNum probe – \(n) Multitouch-Gerät(e). Finger aufs Trackpad legen, Ctrl-C beendet.")
    if let i = args.firstIndex(of: "--seconds"), i + 1 < args.count, let s = Double(args[i + 1]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { exit(0) }
    }
    dispatchMain()
}

if args.contains("--feedback") {
    // Plays a short burst of digit feedback (sound + strongest vibration) – finger on the trackpad to feel it.
    setvbuf(stdout, nil, _IOLBF, 0)
    Multitouch.start()
    let ids = Multitouch.deviceIDs
    Feedback.shared.haptics.reload(deviceIDs: ids)
    Feedback.shared.configure(sound: true, haptic: .strong)
    print("Feedback-Test – \(ids.count) Aktuator(en).")
    for i in 0..<6 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(i) * 0.16) {
            Feedback.shared.keyPressed(i == 5 ? .delete : .d1)
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { exit(0) }
    dispatchMain()
}

if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
    // Diagnostics: all designs offscreen into one PNG on a sample wallpaper.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let themes = ThemeID.allCases.filter { $0 != .auto }
    let samples: [(String, PadKey)] = [("1284", .d5), ("907", .d0), ("3,50", .delete), ("42", .d8), ("2026", .d3)]
    let scale: CGFloat = 2, margin: CGFloat = 36, cols = 3
    let rows = (themes.count + cols - 1) / cols
    let W = margin + CGFloat(cols) * (Overlay.width + margin)
    let H = margin + CGFloat(rows) * (Overlay.height + margin)
    let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    let wallpaper = CGGradient(colorsSpace: nil, colors: [
        NSColor(srgbRed: 0.10, green: 0.32, blue: 0.55, alpha: 1).cgColor,
        NSColor(srgbRed: 0.35, green: 0.62, blue: 0.70, alpha: 1).cgColor,
        NSColor(srgbRed: 0.93, green: 0.75, blue: 0.55, alpha: 1).cgColor,
    ] as CFArray, locations: nil)!
    ctx.drawLinearGradient(wallpaper, start: .zero, end: CGPoint(x: W, y: H), options: [])
    // Some shapes behind the designs, so blur and transparency are visible.
    let blobs: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0.80, 0.80, 110, NSColor(srgbRed: 0.55, green: 0.25, blue: 0.85, alpha: 1)),
        (0.93, 0.62, 80, .white),
        (0.70, 0.62, 60, NSColor(srgbRed: 1.0, green: 0.55, blue: 0.2, alpha: 1)),
        (0.88, 0.95, 70, NSColor(srgbRed: 0.2, green: 0.8, blue: 0.5, alpha: 1)),
        (0.25, 0.30, 90, NSColor(srgbRed: 1.0, green: 0.85, blue: 0.3, alpha: 1)),
    ]
    for (fx, fy, r, c) in blobs {
        ctx.setFillColor(c.cgColor)
        ctx.fillEllipse(in: CGRect(x: fx * W - r, y: fy * H - r, width: 2 * r, height: 2 * r))
    }
    ctx.setFillColor(NSColor(white: 0.1, alpha: 0.9).cgColor)
    ctx.fill(CGRect(x: W * 0.68, y: H * 0.70, width: 140, height: 18))
    ctx.fill(CGRect(x: W * 0.68, y: H * 0.66, width: 200, height: 18))
    for (n, th) in themes.enumerated() {
        let o = Overlay(theme: th)
        let x = margin + CGFloat(n % cols) * (Overlay.width + margin)
        let y = H - CGFloat(n / cols + 1) * (Overlay.height + margin)
        o.render(into: ctx, at: CGPoint(x: x, y: y), typed: samples[n].0, pressed: samples[n].1, latched: n % 2 == 0, scale: scale)
        let label = NSAttributedString(string: th.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white,
        ])
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        label.draw(at: NSPoint(x: x + 4, y: y - 22))
    }
    let url = URL(fileURLWithPath: args[i + 1])
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    exit(CGImageDestinationFinalize(dest) ? 0 : 1)
}

if args.contains("--showcase") {
    // Diagnostics: every design side by side for a few seconds.
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    var overlays: [Overlay] = []
    DispatchQueue.main.async {
        let vf = NSScreen.main!.visibleFrame
        let themes = ThemeID.allCases.filter { $0 != .auto }
        let samples: [(String, PadKey)] = [("1284", .d5), ("907", .d0), ("3,50", .delete), ("42", .d8), ("2026", .d3)]
        for (i, th) in themes.enumerated() {
            let o = Overlay(theme: th)
            let x = vf.minX + 30 + CGFloat(i % 3) * (Overlay.width + 30)
            let y = vf.maxY - CGFloat(i / 3 + 1) * (Overlay.height + 30)
            o.showcase(at: NSPoint(x: x, y: y), typed: samples[i].0, pressed: samples[i].1, latched: i % 2 == 0)
            overlays.append(o)
        }
    }
    let seconds = args.firstIndex(of: "--seconds").flatMap { Double(args[$0 + 1]) } ?? 6
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
    app.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

enum SelfTest {
    static func run() -> Bool {
        let layout = PadLayout()
        let cases: [(Float, Float, PadKey?)] = [
            // left half: ⌫ on top, 0 at the bottom
            (0.10, 0.90, .delete), (0.45, 0.55, .delete), (0.02, 0.98, .delete),
            (0.10, 0.10, .d0), (0.45, 0.45, .d0), (0.30, -0.05, .d0),
            // right half: full-height 3×3
            (0.55, 0.10, .d1), (0.75, 0.10, .d2), (0.95, 0.10, .d3),
            (0.55, 0.50, .d4), (0.75, 0.50, .d5), (0.95, 0.50, .d6),
            (0.55, 0.90, .d7), (0.75, 0.90, .d8), (0.95, 0.90, .d9),
            (1.02, -0.02, .d3),  // slightly out of range is clamped
            (0.50, 0.00, .d1),
            (1.00, 1.00, .d9),
            (0.49, 0.10, .d0),
        ]
        var ok = true
        for (x, y, expected) in cases {
            let got = layout.key(x: x, y: y)
            let pass = got == expected
            ok = ok && pass
            print("\(pass ? "✓" : "✗")  (\(x), \(y)) → \(got?.label ?? "–")  erwartet \(expected?.label ?? "–")")
        }
        let codes = Set(PadKey.allCases.map(\.keyCode))
        if codes.count != PadKey.allCases.count { print("✗ doppelte Keycodes"); ok = false }
        print(ok ? "Alle Tests bestanden." : "Tests fehlgeschlagen.")
        return ok
    }
}
