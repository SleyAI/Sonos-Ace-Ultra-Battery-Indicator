import AppKit
import ServiceManagement

final class StatusItemController: NSObject, BatteryMonitorDelegate, NSMenuDelegate {
    private static let showPercentageKey = "showPercentage"
    private static let lowBatteryThreshold = 20

    private let monitor: BatteryMonitor
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var state: BatteryState = .searching
    private var tickTimer: Timer?

    private let headerItem = NSMenuItem()
    private let detailItem = NSMenuItem()
    private let percentageItem = NSMenuItem(title: "Show Percentage in Menu Bar", action: #selector(togglePercentage), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    private var showPercentage: Bool {
        get { UserDefaults.standard.object(forKey: Self.showPercentageKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.showPercentageKey) }
    }

    init(monitor: BatteryMonitor) {
        self.monitor = monitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        render()
        // Keep the "updated x ago" line and the icon fresh while idle.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.render()
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        headerItem.isEnabled = false
        detailItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(detailItem)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        percentageItem.target = self
        menu.addItem(percentageItem)

        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let forget = NSMenuItem(title: "Forget Headphones & Search Again", action: #selector(forget), keyEquivalent: "")
        forget.target = self
        menu.addItem(forget)

        let bluetoothSettings = NSMenuItem(title: "Open Bluetooth Settings…", action: #selector(openBluetoothSettings), keyEquivalent: "")
        bluetoothSettings.target = self
        menu.addItem(bluetoothSettings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Sonos Ace Battery", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        percentageItem.state = showPercentage ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        render()
    }

    // MARK: - BatteryMonitorDelegate

    func batteryMonitor(_ monitor: BatteryMonitor, didUpdate state: BatteryState) {
        self.state = state
        render()
    }

    // MARK: - Rendering

    private func render() {
        guard let button = statusItem.button else { return }

        var level: Int?
        var title = ""
        var tooltip: String
        var dimmed = false
        var header: String
        var detail: String

        switch state {
        case .bluetoothOff:
            dimmed = true
            header = "Bluetooth is off"
            detail = "Turn on Bluetooth to see the battery level."
            tooltip = header
        case .unauthorized:
            dimmed = true
            header = "Bluetooth access denied"
            detail = "Allow access in System Settings › Privacy & Security › Bluetooth."
            tooltip = header
        case .searching:
            dimmed = true
            header = "Looking for Sonos Ace…"
            detail = "Switch the headphones on and keep them nearby."
            tooltip = header
        case .connecting(let name):
            dimmed = true
            header = name
            detail = "Not connected"
            tooltip = "\(name): not connected"
        case .connected(let name, let lvl, let updated):
            header = name
            level = lvl
            if let lvl {
                title = "\(lvl)%"
                detail = "Battery \(lvl)%  ·  \(Self.relative(updated))"
                tooltip = "\(name): \(lvl)% battery"
            } else {
                detail = "Reading battery level…"
                tooltip = "\(name): reading battery level…"
            }
        }

        button.image = BatteryIcon.image(level: level)
        button.image?.size = BatteryIcon.size
        button.imagePosition = showPercentage && !title.isEmpty ? .imageLeading : .imageOnly
        button.appearsDisabled = dimmed
        button.toolTip = tooltip

        if showPercentage, !title.isEmpty {
            let isLow = (level ?? 100) <= Self.lowBatteryThreshold
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .regular), weight: .medium),
                .foregroundColor: isLow ? NSColor.systemRed : NSColor.labelColor,
                .baselineOffset: 0.5,
            ]
            button.attributedTitle = NSAttributedString(string: " " + title, attributes: attrs)
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }

        headerItem.title = header
        detailItem.title = detail
    }

    private static func relative(_ date: Date?) -> String {
        guard let date else { return "just now" }
        if Date().timeIntervalSince(date) < 45 { return "updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "updated " + formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Actions

    @objc private func refresh() {
        monitor.refresh()
    }

    @objc private func togglePercentage() {
        showPercentage.toggle()
        render()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func forget() {
        monitor.forgetDevice()
    }

    @objc private func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
