import Foundation
import IOBluetooth

/// Watches the classic Bluetooth (audio) link between this Mac and the Sonos Ace.
///
/// If our Low Energy connection comes up before macOS has re-established the classic
/// audio link, macOS still routes audio to the headphones but leaves them out of the
/// Sound menu and Sound settings. So the battery monitor only connects over LE while the
/// audio link is up, and lets go when it drops.
final class AudioLinkWatcher: NSObject {
    /// Called on the main queue with the device name while connected, nil when not.
    var onChange: ((String?) -> Void)?

    private(set) var connectedName: String?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    func start() {
        // Fires for devices that connect from now on (and, on most systems, for those
        // already connected). The explicit sweep below covers the rest.
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? []
        where device.isConnected() {
            handleConnected(device)
        }
        if connectedName == nil {
            Log.info("audio link: Sonos Ace not connected to this Mac")
        }
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        handleConnected(device)
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString ?? ""
        disconnectNotifications.removeValue(forKey: address)?.unregister()
        Log.info("audio link down: \(device.name ?? address)")
        // Another Sonos Ace might still be connected.
        // Skip the device that just dropped: our own LE link can keep it "connected".
        if let remaining = connectedAces().first(where: { $0.addressString != address }) {
            update(remaining.name ?? "Sonos Ace")
        } else {
            update(nil)
        }
    }

    private func handleConnected(_ device: IOBluetoothDevice) {
        guard BatteryMonitor.looksLikeSonosAce(device.name) else { return }
        let address = device.addressString ?? ""
        if disconnectNotifications[address] == nil {
            disconnectNotifications[address] = device.register(
                forDisconnectNotification: self,
                selector: #selector(deviceDisconnected(_:device:))
            )
        }
        Log.info("audio link up: \(device.name ?? address)")
        update(device.name ?? "Sonos Ace")
    }

    private func connectedAces() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() ?? [])
            .compactMap { $0 as? IOBluetoothDevice }
            .filter { $0.isConnected() && BatteryMonitor.looksLikeSonosAce($0.name) }
    }

    private func update(_ name: String?) {
        guard name != connectedName else { return }
        connectedName = name
        onChange?(name)
    }
}
