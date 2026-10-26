import AppKit
import ApplicationServices
import ServiceManagement

final class Settings {
    private let d = UserDefaults.standard

    private func bool(_ key: String, default value: Bool) -> Bool {
        d.object(forKey: key) == nil ? value : d.bool(forKey: key)
    }

    var enabled: Bool {
        get { bool("enabled", default: true) }
        set { d.set(newValue, forKey: "enabled") }
    }
    var hotkey: Hotkey {
        get { Hotkey(rawValue: d.string(forKey: "hotkey") ?? "") ?? .rightCommand }
        set { d.set(newValue.rawValue, forKey: "hotkey") }
    }
    var trigger: Trigger {
        get { Trigger(rawValue: d.string(forKey: "trigger") ?? "") ?? .touch }
        set { d.set(newValue.rawValue, forKey: "trigger") }
    }
    var haptics: Bool {
        get { bool("haptics", default: true) }
        set { d.set(newValue, forKey: "haptics") }
    }
    var showOverlay: Bool {
        get { bool("showOverlay", default: true) }
        set { d.set(newValue, forKey: "showOverlay") }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private let overlay = Overlay()
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var deviceCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }

        let engine = Engine.shared
        engine.onModeChange = { [weak self] active, latched in self?.modeChanged(active: active, latched: latched) }
        engine.onKey = { [weak self] key in self?.keyFired(key) }
        applySettings()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon(active: false)

        deviceCount = Multitouch.start()
        startInputTap()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Engine.shared.unlatch()
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // Devices come back a moment after wake.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self?.deviceCount = Multitouch.restart()
                Engine.shared.resync()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        CGAssociateMouseAndMouseCursorPosition(1)
        Multitouch.stop()
    }

    // MARK: Engine callbacks (main queue)

    private func modeChanged(active: Bool, latched: Bool) {
        // Freeze the cursor while the pad is a numpad.
        CGAssociateMouseAndMouseCursorPosition(active ? 0 : 1)
        if active {
            if settings.showOverlay { overlay.show(latched: latched) }
        } else {
            overlay.hide()
        }
        updateIcon(active: active)
    }

    private func keyFired(_ key: PadKey) {
        if settings.showOverlay { overlay.flash(key) }
        if settings.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    // MARK: Permissions

    private func startInputTap() {
        if InputTap.start() { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if InputTap.start() {
                timer.invalidate()
                self?.permissionTimer = nil
            }
        }
    }

    // MARK: Menu

    private func applySettings() {
        Engine.shared.configure(enabled: settings.enabled, hotkey: settings.hotkey, trigger: settings.trigger)
    }

    private func updateIcon(active: Bool) {
        let name = active ? "number.square.fill" : "number.square"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "TrackNum")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.appearsDisabled = !settings.enabled
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !InputTap.isRunning {
            let warn = item("⚠︎ Bedienungshilfen-Zugriff fehlt…", #selector(openAccessibility))
            menu.addItem(warn)
            menu.addItem(.separator())
        }
        if deviceCount == 0 {
            menu.addItem(NSMenuItem(title: "⚠︎ Kein Trackpad gefunden", action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
        }

        menu.addItem(item("Numpad aktiv", #selector(toggleEnabled), on: settings.enabled))
        menu.addItem(.separator())

        let hotkeyMenu = NSMenu()
        for hk in Hotkey.allCases {
            let i = item(hk.title, #selector(selectHotkey(_:)), on: settings.hotkey == hk)
            i.representedObject = hk.rawValue
            hotkeyMenu.addItem(i)
        }
        let hotkeyItem = NSMenuItem(title: "Aktivierungstaste", action: nil, keyEquivalent: "")
        hotkeyItem.submenu = hotkeyMenu
        menu.addItem(hotkeyItem)

        let triggerMenu = NSMenu()
        let touch = item("Beim Berühren (schnellste)", #selector(selectTrigger(_:)), on: settings.trigger == .touch)
        touch.representedObject = Trigger.touch.rawValue
        let click = item("Beim Klicken", #selector(selectTrigger(_:)), on: settings.trigger == .click)
        click.representedObject = Trigger.click.rawValue
        triggerMenu.addItem(touch)
        triggerMenu.addItem(click)
        let triggerItem = NSMenuItem(title: "Auslösen", action: nil, keyEquivalent: "")
        triggerItem.submenu = triggerMenu
        menu.addItem(triggerItem)

        menu.addItem(item("Overlay anzeigen", #selector(toggleOverlay), on: settings.showOverlay))
        menu.addItem(item("Haptisches Feedback", #selector(toggleHaptics), on: settings.haptics))
        menu.addItem(item("Bei Anmeldung starten", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())

        let help = NSMenuItem(title: "\(settings.hotkey.title) halten = Numpad · kurz tippen = fixieren", action: nil, keyEquivalent: "")
        help.isEnabled = false
        menu.addItem(help)
        menu.addItem(item("TrackNum beenden", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, on: Bool = false, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.state = on ? .on : .off
        return i
    }

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        applySettings()
        updateIcon(active: false)
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let hk = Hotkey(rawValue: raw) else { return }
        settings.hotkey = hk
        applySettings()
    }

    @objc private func selectTrigger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let t = Trigger(rawValue: raw) else { return }
        settings.trigger = t
        applySettings()
    }

    @objc private func toggleOverlay() { settings.showOverlay.toggle() }
    @objc private func toggleHaptics() { settings.haptics.toggle() }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Autostart konnte nicht geändert werden"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func openAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
