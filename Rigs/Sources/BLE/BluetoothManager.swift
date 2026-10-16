import CoreBluetooth
import Foundation
import Observation
import RigKit

struct DiscoveredPeripheral: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    var rssi: Int
    let looksLikeSwitch2: Bool
}

/// Finds, connects, and keeps hold of the Switch 2.
///
/// Connect scans and takes the first rig it hears. After that the rig is
/// remembered, and a pending `connect` is always outstanding while it is out
/// of range or off, so it reattaches on its own with no timeout. CoreBluetooth
/// callbacks arrive on the main queue and hop onto the main actor.
@MainActor @Observable
final class BluetoothManager: NSObject {
    private(set) var bluetoothState: CBManagerState = .unknown
    /// Every nearby peripheral, for the "show every nearby device" list.
    private(set) var nearby: [DiscoveredPeripheral] = []
    private(set) var isSearching = false
    private(set) var isReconnecting = false
    /// The rig's name from when it's found until it's set up, for the connect screen.
    private(set) var connectingTo: String?
    var lastError: String?

    private(set) var controller: Switch2Controller?

    private let log: SessionLog
    private var central: CBCentralManager!
    private var transport: PeripheralTransport?
    private var peripheral: CBPeripheral?
    private var connectWaiter: CheckedContinuation<Void, any Error>?
    private var searchTimeout: Task<Void, Never>?
    private var listAll = false
    private var forgotten = false

    private let rememberedKey = "rigs.remembered"
    private let diag = Diagnostics.shared

    init(log: SessionLog) {
        self.log = log
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    var isReady: Bool { bluetoothState == .poweredOn }
    var hasRemembered: Bool { rememberedID != nil }

    private var rememberedID: UUID? {
        get { UserDefaults.standard.string(forKey: rememberedKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: rememberedKey) }
    }

    // MARK: Finding the rig

    /// Scans and connects to the first Switch 2 it hears. With `everything`,
    /// lists every nearby peripheral instead so the user can pick.
    func search(everything: Bool = false) {
        guard isReady else {
            diag.record(.error, "search refused: Bluetooth is \(Self.describe(bluetoothState))")
            lastError = bluetoothState == .unauthorized
                ? "Rigs isn't allowed to use Bluetooth. Turn it on in Settings › Rigs."
                : "Bluetooth is off. Turn it on in Control Center."
            return
        }
        // A second tap while the link opens would start a scan nobody stops.
        guard connectingTo == nil, transport == nil else {
            diag.record(.app, "search ignored: already connecting")
            return
        }
        stopSearch()
        nearby.removeAll()
        listAll = everything
        isSearching = true
        lastError = nil
        forgotten = false
        diag.record(.ble, everything ? "scan started (listing every device)" : "scan started")
        // No service filter: the rig doesn't always put its service in the advertisement.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        if !everything {
            searchTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, isSearching else { return }
                stopSearch()
                diag.record(.error, "scan timed out after 15 s with no Switch 2")
                lastError = "No Switch 2 found. Is it on, with pairing turned on?"
            }
        }
    }

    func stopSearch() {
        searchTimeout?.cancel()
        if isSearching {
            central.stopScan()
            diag.record(.ble, "scan stopped")
        }
        isSearching = false
    }

    /// Connects to a peripheral picked from the `nearby` list.
    func connect(to id: UUID) {
        stopSearch()
        guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        Task { await connectAndSetUp(p, userInitiated: true) }
    }

    // MARK: Reconnecting

    /// Called when Bluetooth powers on, and after every unexpected drop.
    private func reconnectRemembered() {
        guard isReady, !forgotten, let id = rememberedID, transport == nil,
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        isReconnecting = true
        diag.record(.ble, "reconnecting to remembered rig \(Self.short(id))")
        Task { await connectAndSetUp(p, userInitiated: false) }
    }

    /// Forgets the rig: disconnects and stops reconnecting.
    func forget() async {
        forgotten = true
        diag.record(.app, "rig forgotten")
        rememberedID = nil
        Switch2Controller.forgetSnapshot()
        stopSearch()
        isReconnecting = false
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        await controller?.device?.disconnect()
        controller = nil
        transport = nil
        peripheral = nil
    }

    // MARK: Connection

    private func connectAndSetUp(_ p: CBPeripheral, userInitiated: Bool) async {
        peripheral = p
        if userInitiated { connectingTo = p.name ?? "your rig" }
        defer { connectingTo = nil }
        diag.record(.ble, "connecting to \(p.name ?? "unnamed") \(Self.short(p.identifier))\(userInitiated ? "" : " (background)")")
        let t = PeripheralTransport(peripheral: p, central: central)
        transport = t
        do {
            // A user-initiated connect gives up after 20 s; a reconnect waits for as long as it takes.
            let timeout = userInitiated ? Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                self?.abandonConnect()
            } : nil
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                connectWaiter = c
                central.connect(p, options: nil)
            }
            timeout?.cancel()

            try await t.discover(services: Switch2.UUIDs.optionalServices)
            diag.record(.ble, t.discoveredSummary())
            guard let chars = Switch2.Characteristics.all.first(where: { t.hasCharacteristic($0.notify) && t.hasCharacteristic($0.write) }) else {
                throw RigKitError.unsupported("This doesn't look like a Switch 2: none of its Bluetooth services match.")
            }
            diag.record(.ble, "using \(Diagnostics.name(chars.write)) / \(Diagnostics.name(chars.notify))")
            let device = Switch2Device(transport: LoggingTransport(t), characteristics: chars)
            let ctl = controller ?? Switch2Controller(name: p.name ?? "Switch 2", log: log, remembers: true)
            ctl.attach(device)
            controller = ctl
            try await device.connect()
            rememberedID = p.identifier
            isReconnecting = false
            lastError = nil
            diag.record(.ble, "set up; waiting for the rig's state dump")
        } catch {
            diag.record(.error, "connect failed: \(error)")
            transport = nil
            if userInitiated {
                central.cancelPeripheralConnection(p)
                lastError = describe(error)
            } else {
                // Keep trying in the background.
                try? await Task.sleep(for: .seconds(3))
                reconnectRemembered()
            }
        }
    }

    private func abandonConnect() {
        guard let c = connectWaiter else { return }
        connectWaiter = nil
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        c.resume(throwing: RigKitError.timeout)
    }

    private static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }

    nonisolated static func describe(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: "on"
        case .poweredOff: "off"
        case .unauthorized: "not allowed"
        case .unsupported: "unsupported"
        case .resetting: "resetting"
        default: "unknown"
        }
    }

    private func describe(_ error: any Error) -> String {
        switch error {
        case RigKitError.timeout: "The Switch 2 timed out. Is it on, nearby, and closed in the Dr. Dabber app?"
        case RigKitError.notConnected: "The Switch 2 dropped the connection during setup. Try again."
        case RigKitError.unsupported(let why): why
        default: "Couldn't connect: \(error.localizedDescription)"
        }
    }

    nonisolated fileprivate static func looksLikeSwitch2(name: String?, services: [CBUUID]) -> Bool {
        let known = [Switch2.UUIDs.controlService, Switch2.UUIDs.fallbackService, Switch2.UUIDs.goService].map { CBUUID(nsuuid: $0) }
        if services.contains(where: known.contains) { return true }
        guard let name else { return false }
        return ["Switch", "SW2", "Dr", "DD"].contains { name.hasPrefix($0) }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated {
            bluetoothState = state
            diag.record(.ble, "Bluetooth is \(Self.describe(state))")
            if state == .poweredOn {
                reconnectRemembered()
            } else {
                isSearching = false
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let id = peripheral.identifier
        let rssi = RSSI.intValue
        let match = Self.looksLikeSwitch2(name: name, services: services)
        let serviceList = services.map(\.uuidString).joined(separator: ", ")
        MainActor.assumeIsolated {
            guard isSearching else { return }
            diag.record(.ble, "heard \(name ?? "unnamed") \(Self.short(id)) \(rssi) dBm services [\(serviceList)]\(match ? " ← Switch 2" : "")")
            if listAll {
                guard name != nil || match else { return }
                if let i = nearby.firstIndex(where: { $0.id == id }) {
                    nearby[i].rssi = rssi
                } else {
                    nearby.append(DiscoveredPeripheral(id: id, name: name ?? "Unnamed", rssi: rssi, looksLikeSwitch2: match))
                    nearby.sort { ($0.looksLikeSwitch2 ? 1 : 0, $0.rssi) > ($1.looksLikeSwitch2 ? 1 : 0, $1.rssi) }
                }
            } else if match, let p = self.central.retrievePeripherals(withIdentifiers: [id]).first {
                stopSearch()
                Task { await connectAndSetUp(p, userInitiated: true) }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            diag.record(.ble, "link up")
            connectWaiter?.resume()
            connectWaiter = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        let reason = error.map { "\($0.localizedDescription)" } ?? "no reason given"
        MainActor.assumeIsolated {
            diag.record(.error, "failed to connect: \(reason)")
            connectWaiter?.resume(throwing: error ?? RigKitError.notConnected)
            connectWaiter = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        let reason = error.map { "\($0.localizedDescription)" } ?? "clean disconnect"
        MainActor.assumeIsolated {
            diag.record(error == nil ? .ble : .error, "link down: \(reason)")
            transport?.linkDropped()
            transport = nil
            connectWaiter?.resume(throwing: RigKitError.notConnected)
            connectWaiter = nil
            controller?.markDisconnected()
            if !forgotten { reconnectRemembered() }
        }
    }
}
