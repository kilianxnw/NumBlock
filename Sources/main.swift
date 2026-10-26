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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

enum SelfTest {
    static func run() -> Bool {
        let layout = PadLayout()
        let cases: [(Float, Float, PadKey?)] = [
            (0.30, 0.50, nil),   // left half ignored
            (0.49, 0.10, nil),
            (0.55, 0.10, .d1), (0.75, 0.10, .d2), (0.95, 0.10, .d3),
            (0.55, 0.37, .d4), (0.75, 0.37, .d5), (0.95, 0.37, .d6),
            (0.55, 0.62, .d7), (0.75, 0.62, .d8), (0.95, 0.62, .d9),
            (0.52, 0.90, .d0), (0.75, 0.80, .d0), (0.99, 0.99, .d0),
            (1.02, -0.02, .d3),  // slightly out of range is clamped
            (0.50, 0.00, .d1),
            (1.00, 0.749, .d9),
        ]
        var ok = true
        for (x, y, expected) in cases {
            let got = layout.key(x: x, y: y)
            let pass = got == expected
            ok = ok && pass
            print("\(pass ? "✓" : "✗")  (\(x), \(y)) → \(got?.label ?? "–")  erwartet \(expected?.label ?? "–")")
        }
        let codes = Set(PadKey.allCases.map(\.keyCode))
        if codes.count != 10 { print("✗ doppelte Keycodes"); ok = false }
        print(ok ? "Alle Tests bestanden." : "Tests fehlgeschlagen.")
        return ok
    }
}
