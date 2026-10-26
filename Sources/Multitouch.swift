import Foundation

/// Thin runtime binding to the private MultitouchSupport.framework.
/// Delivers raw finger frames for every trackpad, system-wide, on the framework's own thread.
enum Multitouch {
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias RegisterFn = @convention(c) (MTDeviceRef?, MTFrameCallback?) -> Void
    private typealias StartFn = @convention(c) (MTDeviceRef?, Int32) -> Void
    private typealias StopFn = @convention(c) (MTDeviceRef?) -> Void
    private typealias IsBuiltInFn = @convention(c) (MTDeviceRef?) -> Bool
    private typealias FamilyFn = @convention(c) (MTDeviceRef?, UnsafeMutablePointer<Int32>?) -> Int32
    private typealias DeviceIDFn = @convention(c) (MTDeviceRef?, UnsafeMutablePointer<UInt64>?) -> Int32

    /// External Magic Trackpad families; Magic Mouse (0x70/0x71) is deliberately excluded.
    private static let magicTrackpadFamilies: Set<Int32> = [0x80, 0x81, 0x82, 0x83]

    private struct API {
        let createList: CreateListFn
        let register: RegisterFn
        let unregister: RegisterFn
        let start: StartFn
        let stop: StopFn
        let isBuiltIn: IsBuiltInFn
        let family: FamilyFn
        let deviceID: DeviceIDFn
    }

    private static let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)

    /// Looks up a framework function and casts it to the given `@convention(c)` type.
    static func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let handle, let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private static let api: API? = {
        guard let createList = sym("MTDeviceCreateList", CreateListFn.self),
              let register = sym("MTRegisterContactFrameCallback", RegisterFn.self),
              let unregister = sym("MTUnregisterContactFrameCallback", RegisterFn.self),
              let start = sym("MTDeviceStart", StartFn.self),
              let stop = sym("MTDeviceStop", StopFn.self),
              let isBuiltIn = sym("MTDeviceIsBuiltIn", IsBuiltInFn.self),
              let family = sym("MTDeviceGetFamilyID", FamilyFn.self),
              let deviceID = sym("MTDeviceGetDeviceID", DeviceIDFn.self)
        else { return nil }
        return API(createList: createList, register: register, unregister: unregister, start: start, stop: stop,
                   isBuiltIn: isBuiltIn, family: family, deviceID: deviceID)
    }()

    private static func isTrackpad(_ api: API, _ dev: MTDeviceRef) -> Bool {
        if api.isBuiltIn(dev) { return true }
        var family: Int32 = 0
        _ = api.family(dev, &family)
        return magicTrackpadFamilies.contains(family)
    }

    private static let callback: MTFrameCallback = { _, touches, count, _, _ in
        Engine.shared.handleFrame(touches, Int(count))
        return 0
    }

    // Device lists are kept alive for the process lifetime; releasing them has been known to crash.
    private static var lists: [CFArray] = []
    private static var devices: [MTDeviceRef] = []

    /// Multitouch IDs of the registered trackpads (used to open their haptic actuators).
    static var deviceIDs: [UInt64] {
        guard let api else { return [] }
        return devices.compactMap { dev in
            var id: UInt64 = 0
            return api.deviceID(dev, &id) == 0 ? id : nil
        }
    }

    /// Registers the frame callback on all multitouch devices. Returns the number of devices.
    @discardableResult
    static func start() -> Int {
        guard let api, devices.isEmpty, let list = api.createList()?.takeRetainedValue() else { return devices.count }
        lists.append(list)
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            guard isTrackpad(api, dev) else { continue }
            api.register(dev, callback)
            api.start(dev, 0)
            devices.append(dev)
        }
        return devices.count
    }

    static func stop() {
        guard let api else { return }
        for dev in devices {
            api.unregister(dev, callback)
            api.stop(dev)
        }
        devices.removeAll()
    }

    /// Needed after sleep/wake or when a trackpad is (re)connected.
    @discardableResult
    static func restart() -> Int {
        stop()
        return start()
    }
}
