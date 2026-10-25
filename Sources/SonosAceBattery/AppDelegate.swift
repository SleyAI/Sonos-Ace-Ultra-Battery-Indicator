import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var monitor: BatteryMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        handleLaunchArguments()

        let monitor = BatteryMonitor()
        let controller = StatusItemController(monitor: monitor)
        monitor.delegate = controller
        self.monitor = monitor
        self.statusController = controller
        monitor.start()
    }

    /// `open "Sonos Ace Battery.app" --args --launch-at-login` registers the login item
    /// without going through the menu. `--no-launch-at-login` removes it again.
    private func handleLaunchArguments() {
        let args = CommandLine.arguments
        let service = SMAppService.mainApp
        do {
            if args.contains("--launch-at-login"), service.status != .enabled {
                try service.register()
                Log.info("launch at login enabled (status \(service.status.rawValue))")
            } else if args.contains("--no-launch-at-login"), service.status == .enabled {
                try service.unregister()
                Log.info("launch at login disabled")
            }
        } catch {
            Log.info("launch at login change failed: \(error.localizedDescription)")
        }
    }
}
