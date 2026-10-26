import AVFoundation
import AppKit
import os

enum HapticStrength: String, CaseIterable {
    case off, light, medium, strong

    /// Taptic Engine waveform IDs (MTActuatorActuate)
    var actuationID: Int32? {
        switch self {
        case .off: nil
        case .light: 3
        case .medium: 4
        case .strong: 6
        }
    }

    var title: String {
        switch self {
        case .off: "Aus"
        case .light: "Leicht"
        case .medium: "Mittel"
        case .strong: "Stark"
        }
    }
}

/// Per-digit feedback, called directly on the thread that fired the key (no main-queue hop).
final class Feedback {
    static let shared = Feedback()

    private struct Config {
        var sound = true
        var haptic = HapticStrength.strong
    }

    let haptics = Haptics()
    let sound = ClickSound()
    private let config = OSAllocatedUnfairLock(initialState: Config())

    func configure(sound: Bool, haptic: HapticStrength) {
        config.withLock { $0 = Config(sound: sound, haptic: haptic) }
    }

    func keyPressed() {
        let c = config.withLock { $0 }
        haptics.actuate(c.haptic)
        if c.sound { sound.play() }
    }

    /// Spins up the audio engine as the numpad opens, so the first digit is not delayed.
    func modeActivated() {
        if config.withLock({ $0.sound }) { sound.warmUp() }
    }
}

// MARK: - Haptics

/// Drives the trackpad's Taptic Engine directly: much stronger than NSHapticFeedbackManager
/// and independent of which app is in front.
final class Haptics {
    private typealias CreateFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias OpenCloseFn = @convention(c) (CFTypeRef?) -> Int32
    private typealias ActuateFn = @convention(c) (CFTypeRef?, Int32, UInt32, Float, Float) -> Int32

    private let create = Multitouch.sym("MTActuatorCreateFromDeviceID", CreateFn.self)
    private let open = Multitouch.sym("MTActuatorOpen", OpenCloseFn.self)
    private let close = Multitouch.sym("MTActuatorClose", OpenCloseFn.self)
    private let actuateFn = Multitouch.sym("MTActuatorActuate", ActuateFn.self)

    private let actuators = OSAllocatedUnfairLock<[CFTypeRef]>(uncheckedState: [])

    /// (Re)opens the actuators of the given trackpads; call after Multitouch.start/restart.
    func reload(deviceIDs: [UInt64]) {
        guard let create, let open, let close else { return }
        let fresh: [CFTypeRef] = deviceIDs.compactMap { id in
            guard let a = create(id)?.takeRetainedValue(), open(a) == 0 else { return nil }
            return a
        }
        let old = actuators.withLockUnchecked { list in
            defer { list = fresh }
            return list
        }
        for a in old { _ = close(a) }
    }

    func actuate(_ strength: HapticStrength) {
        guard let id = strength.actuationID else { return }
        let done = actuators.withLockUnchecked { list -> Bool in
            guard let actuateFn, !list.isEmpty else { return false }
            for a in list { _ = actuateFn(a, id, 0, 1.0, 2.0) }
            return true
        }
        if !done {
            DispatchQueue.main.async {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        }
    }
}

// MARK: - Sound

/// Short synthesized "thock" (soft low body + bright click transient), played through AVAudioEngine
/// with pre-rendered buffers. Follows the system volume and mute.
final class ClickSound {
    private let queue = DispatchQueue(label: "TrackNum.Sound", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [AVAudioPCMBuffer] = []
    private var next = 0
    private var idleStop: DispatchWorkItem?
    /// Keep the audio device awake only while in use.
    private let idleTimeout = 15.0

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        // Slight pitch variation per voice so fast typing does not sound like a machine gun.
        for (i, pitch) in [1.0, 0.96, 1.04].enumerated() {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
            buffers.append(Self.synthesize(format: format, pitch: pitch, seed: UInt32(i + 1)))
        }
    }

    func warmUp() {
        queue.async {
            _ = self.ensureRunning()
            self.scheduleIdleStop()
        }
    }

    func play() {
        queue.async {
            guard self.ensureRunning() else { return }
            let i = self.next
            self.next = (i + 1) % self.players.count
            self.players[i].scheduleBuffer(self.buffers[i], at: nil, options: .interrupts)
            self.scheduleIdleStop()
        }
    }

    private func ensureRunning() -> Bool {
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return false }
        }
        for p in players where !p.isPlaying { p.play() }
        return true
    }

    private func scheduleIdleStop() {
        idleStop?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            for p in self.players { p.stop() }
            self.engine.stop()
        }
        idleStop = work
        queue.asyncAfter(deadline: .now() + idleTimeout, execute: work)
    }

    static func synthesize(format: AVAudioFormat, pitch: Double, seed: UInt32) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(sr * 0.07)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]

        var rng = seed &* 2_654_435_761
        var phase = 0.0
        var prevNoise = 0.0, hp = 0.0
        var peak = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            // Body: low sine with a quick downward pitch sweep – the "thock"
            let f = (150 + 110 * exp(-t / 0.006)) * pitch
            phase += 2 * .pi * f / sr
            let body = sin(phase) * exp(-t / 0.016) * 0.6
            // Tock: short mid resonance, like a keycap
            let tock = sin(2 * .pi * 1250 * pitch * t) * exp(-t / 0.0045) * 0.28
            // Click: high-passed noise burst, ~1 ms
            rng = rng &* 1_664_525 &+ 1_013_904_223
            let noise = Double(rng >> 8) / Double(1 << 24) * 2 - 1
            hp = 0.85 * (hp + noise - prevNoise)
            prevNoise = noise
            let click = hp * exp(-t / 0.0011) * 0.35
            // 0.3 ms fade-in avoids a DC pop
            let s = (body + tock + click) * min(1, t / 0.0003)
            out[i] = Float(s)
            peak = max(peak, abs(s))
        }
        let gain = Float(0.7 / max(peak, 1e-6))
        for i in 0..<Int(frames) { out[i] *= gain }
        return buffer
    }
}
