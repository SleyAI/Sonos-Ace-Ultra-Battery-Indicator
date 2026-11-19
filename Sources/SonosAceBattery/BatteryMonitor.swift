import CoreBluetooth
import Foundation

/// Snapshot of what the monitor currently knows.
enum BatteryState: Equatable {
    case bluetoothOff
    case unauthorized
    /// The headphones' audio link to this Mac is down, so we stay off LE (see AudioLinkWatcher).
    case audioNotConnected(name: String?)
    case searching
    case connecting(name: String)
    case connected(name: String, level: Int?, updated: Date?)

    var deviceName: String? {
        switch self {
        case .connecting(let n), .connected(let n, _, _): return n
        case .audioNotConnected(let n): return n
        default: return nil
        }
    }
}

protocol BatteryMonitorDelegate: AnyObject {
    func batteryMonitor(_ monitor: BatteryMonitor, didUpdate state: BatteryState)
}

/// Reads the standard GATT Battery Service (0x180F) that the Sonos Ace headphones
/// expose over Bluetooth Low Energy. macOS does not surface this value for classic
/// audio devices, so we read it ourselves. No private APIs involved.
///
/// The LE connection is only held while the headphones' classic audio link to this Mac is
/// up. Connecting over LE first makes macOS hide them from the Sound menu.
final class BatteryMonitor: NSObject {
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevelCharacteristic = CBUUID(string: "2A19")
    /// Sonos, Inc. 16-bit member service UUID, present in the Ace's advertisements.
    private static let sonosService = CBUUID(string: "FE07")
    private static let savedIdentifierKey = "peripheralIdentifier"
    private static let savedNameKey = "peripheralName"
    private static let pollInterval: TimeInterval = 120
    /// Give macOS time to finish setting up the audio device before we add our LE link.
    private static let audioSettleDelay: TimeInterval = 5

    weak var delegate: BatteryMonitorDelegate?

    private(set) var state: BatteryState = .searching {
        didSet {
            guard state != oldValue else { return }
            Log.info("state -> \(state)")
            delegate?.batteryMonitor(self, didUpdate: state)
        }
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var levelCharacteristic: CBCharacteristic?
    private var pollTimer: Timer?
    private let audioLink = AudioLinkWatcher()
    private var audioLinkUp = false
    private var settleWork: DispatchWorkItem?

    var lastKnownName: String? {
        UserDefaults.standard.string(forKey: Self.savedNameKey)
    }

    func start() {
        audioLink.onChange = { [weak self] name in self?.audioLinkChanged(name) }
        Log.info("starting, Bluetooth authorization = \(CBManager.authorization.rawValue) (0 not determined, 1 restricted, 2 denied, 3 allowed)")
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
        audioLink.start()
    }

    private func audioLinkChanged(_ name: String?) {
        settleWork?.cancel()
        settleWork = nil
        if let name {
            Log.info("audio link up (\(name)), connecting over LE in \(Int(Self.audioSettleDelay)) s")
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.audioLink.connectedName != nil else { return }
                self.audioLinkUp = true
                self.beginSearch()
            }
            settleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.audioSettleDelay, execute: work)
        } else {
            Log.info("audio link down, releasing LE connection")
            audioLinkUp = false
            beginSearch()
        }
    }

    /// Re-read the battery level right now.
    func refresh() {
        if let peripheral, let levelCharacteristic, peripheral.state == .connected {
            peripheral.readValue(for: levelCharacteristic)
        } else {
            beginSearch()
        }
    }

    /// Drop the remembered headphones and look for a pair again.
    func forgetDevice() {
        UserDefaults.standard.removeObject(forKey: Self.savedIdentifierKey)
        UserDefaults.standard.removeObject(forKey: Self.savedNameKey)
        dropPeripheral()
        beginSearch()
    }

    // MARK: - Connection management

    private func beginSearch() {
        guard central.state == .poweredOn else { return }
        central.stopScan()

        guard audioLinkUp else {
            dropPeripheral()
            state = .audioNotConnected(name: lastKnownName)
            return
        }

        // 1. The system may already hold an LE link to the headphones.
        if let p = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
            .first(where: { Self.looksLikeSonosAce($0.name) }) {
            adopt(p)
            return
        }

        // 2. Ask for the pair we used last time. The connect request stays pending
        //    until the headphones are switched on and in range, which gives us
        //    automatic reconnection for free.
        if let saved = UserDefaults.standard.string(forKey: Self.savedIdentifierKey),
           let id = UUID(uuidString: saved),
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            adopt(p)
        }

        // 3. Also scan, in case the headphones were re-paired or this is the first run.
        //    Scanning stops as soon as we connect.
        central.scanForPeripherals(withServices: [Self.sonosService], options: nil)
        if peripheral == nil { state = .searching }
    }

    static func looksLikeSonosAce(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return name.contains("sonos") && name.contains("ace")
    }

    private func adopt(_ p: CBPeripheral) {
        if let current = peripheral, current.identifier != p.identifier {
            central.cancelPeripheralConnection(current)
        }
        peripheral = p
        p.delegate = self
        let name = p.name ?? lastKnownName ?? "Sonos Ace"
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.savedIdentifierKey)
        UserDefaults.standard.set(name, forKey: Self.savedNameKey)

        if p.state == .connected {
            state = .connected(name: name, level: nil, updated: nil)
            p.discoverServices([Self.batteryService])
        } else {
            state = .connecting(name: name)
            central.connect(p, options: nil)
        }
    }

    private func dropPeripheral() {
        stopPolling()
        levelCharacteristic = nil
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        peripheral = nil
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        pollTimer?.tolerance = 15
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func handleLevel(_ data: Data?) {
        guard let data, let raw = data.first else { return }
        let level = min(max(Int(raw), 0), 100)
        let name = peripheral?.name ?? lastKnownName ?? "Sonos Ace"
        state = .connected(name: name, level: level, updated: Date())
    }
}

// MARK: - CBCentralManagerDelegate

extension BatteryMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Log.info("central state = \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            beginSearch()
        case .unauthorized:
            dropPeripheral()
            state = .unauthorized
        case .poweredOff, .resetting, .unsupported, .unknown:
            dropPeripheral()
            state = .bluetoothOff
        @unknown default:
            state = .bluetoothOff
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover p: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        Log.info("discovered \(p.name ?? advertisedName ?? "?") (\(p.identifier.uuidString))")
        guard Self.looksLikeSonosAce(p.name ?? advertisedName) else { return }
        // Stick with the pair we already have unless we have none.
        if let current = peripheral, current.identifier != p.identifier, current.state != .disconnected {
            return
        }
        central.stopScan()
        adopt(p)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        central.stopScan()
        let name = p.name ?? lastKnownName ?? "Sonos Ace"
        if let n = p.name { UserDefaults.standard.set(n, forKey: Self.savedNameKey) }
        state = .connected(name: name, level: nil, updated: nil)
        p.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        Log.info("failed to connect: \(error?.localizedDescription ?? "unknown error")")
        guard p.identifier == peripheral?.identifier, audioLinkUp else { return }
        state = .connecting(name: p.name ?? lastKnownName ?? "Sonos Ace")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.audioLinkUp, self.peripheral?.identifier == p.identifier else { return }
            self.central.connect(p, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        Log.info("disconnected: \(error?.localizedDescription ?? "no error")")
        guard p.identifier == peripheral?.identifier else { return }
        stopPolling()
        levelCharacteristic = nil
        guard audioLinkUp else {
            peripheral = nil
            state = .audioNotConnected(name: p.name ?? lastKnownName)
            return
        }
        // The audio link is still up, so only the LE link dropped: reconnect right away.
        state = .connecting(name: p.name ?? lastKnownName ?? "Sonos Ace")
        central.connect(p, options: nil)
    }
}

// MARK: - CBPeripheralDelegate

extension BatteryMonitor: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        Log.info("services: \((p.services ?? []).map { $0.uuid.uuidString }.joined(separator: ",")) error: \(error?.localizedDescription ?? "none")")
        guard let service = p.services?.first(where: { $0.uuid == Self.batteryService }) else {
            // Some firmware takes a moment to populate the GATT table; try once more.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak p] in
                p?.discoverServices([Self.batteryService])
            }
            return
        }
        p.discoverCharacteristics([Self.batteryLevelCharacteristic], for: service)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let ch = service.characteristics?.first(where: { $0.uuid == Self.batteryLevelCharacteristic }) else { return }
        levelCharacteristic = ch
        p.readValue(for: ch)
        if ch.properties.contains(.notify) {
            p.setNotifyValue(true, for: ch)
        }
        startPolling()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if let error { Log.info("read error: \(error.localizedDescription)") }
        guard ch.uuid == Self.batteryLevelCharacteristic, error == nil else { return }
        handleLevel(ch.value)
    }

    func peripheral(_ p: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        if invalidatedServices.contains(where: { $0.uuid == Self.batteryService }) {
            levelCharacteristic = nil
            p.discoverServices([Self.batteryService])
        }
    }
}
