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
            lastError = bluetoothState == .unauthorized
                ? "Rigs isn't allowed to use Bluetooth. Turn it on in Settings › Rigs."
                : "Bluetooth is off. Turn it on in Control Center."
            return
        }
        stopSearch()
        nearby.removeAll()
        listAll = everything
        isSearching = true
        lastError = nil
        forgotten = false
        // No service filter: the rig doesn't always put its service in the advertisement.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        if !everything {
            searchTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, isSearching else { return }
                stopSearch()
                lastError = "No Switch 2 found. Is it on, with pairing turned on?"
            }
        }
    }

    func stopSearch() {
        searchTimeout?.cancel()
        if isSearching { central.stopScan() }
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
        Task { await connectAndSetUp(p, userInitiated: false) }
    }

    /// Forgets the rig: disconnects and stops reconnecting.
    func forget() async {
        forgotten = true
        rememberedID = nil
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
            guard let chars = Switch2.Characteristics.all.first(where: { t.hasCharacteristic($0.notify) && t.hasCharacteristic($0.write) }) else {
                throw RigKitError.unsupported("This doesn't look like a Switch 2: none of its Bluetooth services match.")
            }
            let device = Switch2Device(transport: t, characteristics: chars)
            let ctl = controller ?? Switch2Controller(name: p.name ?? "Switch 2", log: log)
            ctl.attach(device)
            controller = ctl
            try await device.connect()
            rememberedID = p.identifier
            isReconnecting = false
            lastError = nil
        } catch {
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
        MainActor.assumeIsolated {
            guard isSearching else { return }
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
            connectWaiter?.resume()
            connectWaiter = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        MainActor.assumeIsolated {
            connectWaiter?.resume(throwing: error ?? RigKitError.notConnected)
            connectWaiter = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        MainActor.assumeIsolated {
            transport?.linkDropped()
            transport = nil
            connectWaiter?.resume(throwing: RigKitError.notConnected)
            connectWaiter = nil
            controller?.markDisconnected()
            if !forgotten { reconnectRemembered() }
        }
    }
}
