import CoreBluetooth
import Foundation
import Observation
import RigKit

enum RigKind: String, Codable, Sendable {
    case switch2, peakPro

    var displayName: String {
        switch self {
        case .switch2: "Switch 2"
        case .peakPro: "Peak Pro"
        }
    }

    /// Services the device advertises; used as the scan filter.
    var advertisedServices: [UUID] {
        switch self {
        case .switch2: [Switch2.UUIDs.controlService]
        case .peakPro: [Lorax.UUIDs.legacyService, Lorax.UUIDs.service]
        }
    }

    var servicesToDiscover: [UUID] {
        switch self {
        case .switch2: Switch2.UUIDs.optionalServices
        case .peakPro: Lorax.UUIDs.optionalServices
        }
    }
}

struct DiscoveredRig: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let kind: RigKind
    var rssi: Int
}

/// Scans, connects, and hands each connected peripheral to the right
/// controller. Everything here runs on the main actor; CoreBluetooth
/// callbacks are delivered on the main queue and hop in explicitly.
@MainActor @Observable
final class BluetoothManager: NSObject {
    private(set) var bluetoothState: CBManagerState = .unknown
    private(set) var discovered: [DiscoveredRig] = []
    private(set) var isScanning = false
    private(set) var connecting: UUID?
    var lastError: String?

    private(set) var switch2: Switch2Controller?
    private(set) var peakPro: PeakProController?

    private var central: CBCentralManager!
    private var transports: [UUID: PeripheralTransport] = [:]
    private var kinds: [UUID: RigKind] = [:]
    private var connectWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

    private let rememberedKey = "rememberedRigs"

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    var isReady: Bool { bluetoothState == .poweredOn }

    // MARK: Scanning

    func startScan() {
        guard isReady, !isScanning else { return }
        discovered.removeAll()
        isScanning = true
        let services = (RigKind.switch2.advertisedServices + RigKind.peakPro.advertisedServices).map { CBUUID(nsuuid: $0) }
        central.scanForPeripherals(withServices: services, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    // MARK: Connecting

    func connect(_ rig: DiscoveredRig) async {
        guard connecting == nil else { return }
        stopScan()
        connecting = rig.id
        lastError = nil
        defer { connecting = nil }
        do {
            try await connectPeripheral(id: rig.id, kind: rig.kind)
            remember(rig.id, kind: rig.kind)
        } catch {
            lastError = "\(rig.kind.displayName): \(describe(error))"
            if let t = transports.removeValue(forKey: rig.id) { await t.disconnect() }
        }
    }

    /// Tries the rigs connected last time, without scanning.
    func reconnectRemembered() async {
        guard isReady else { return }
        for (id, kind) in remembered() where transports[id] == nil {
            guard central.retrievePeripherals(withIdentifiers: [id]).first != nil else { continue }
            connecting = id
            do { try await connectPeripheral(id: id, kind: kind) } catch { /* not in range; fine */ }
            connecting = nil
        }
    }

    private func connectPeripheral(id: UUID, kind: RigKind) async throws {
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first else {
            throw RigKitError.unsupported("peripheral not found")
        }
        let transport = PeripheralTransport(peripheral: peripheral, central: central)
        transports[id] = transport
        kinds[id] = kind

        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            await self?.abandonConnect(id)
        }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            connectWaiters[id] = c
            central.connect(peripheral, options: nil)
        }
        timeout.cancel()
        try await transport.discover(services: kind.servicesToDiscover)

        switch kind {
        case .switch2:
            let chars: Switch2.Characteristics = transport.hasCharacteristic(Switch2.UUIDs.controlNotify) ? .control : .fallback
            let device = Switch2Device(transport: transport, characteristics: chars)
            let controller = Switch2Controller(device: device, name: peripheral.name ?? "Switch 2")
            controller.start()
            try await device.connect()
            switch2 = controller
        case .peakPro:
            let device = PeakProDevice(transport: transport)
            let controller = PeakProController(device: device, name: peripheral.name ?? "Peak Pro")
            controller.start()
            try await device.connect()
            await device.startPolling()
            peakPro = controller
        }
    }

    private func abandonConnect(_ id: UUID) {
        guard let c = connectWaiters.removeValue(forKey: id) else { return }
        if let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            central.cancelPeripheralConnection(p)
        }
        c.resume(throwing: RigKitError.timeout)
    }

    func disconnect(_ kind: RigKind) async {
        switch kind {
        case .switch2:
            await switch2?.device.disconnect()
            switch2 = nil
        case .peakPro:
            await peakPro?.device.disconnect()
            peakPro = nil
        }
        forget(kind)
    }

    // MARK: Remembered rigs

    private func remembered() -> [UUID: RigKind] {
        guard let data = UserDefaults.standard.data(forKey: rememberedKey),
              let map = try? JSONDecoder().decode([String: RigKind].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: map.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }

    private func remember(_ id: UUID, kind: RigKind) {
        var map = remembered().filter { $0.value != kind }
        map[id] = kind
        save(map)
    }

    private func forget(_ kind: RigKind) {
        save(remembered().filter { $0.value != kind })
    }

    private func save(_ map: [UUID: RigKind]) {
        let encodable = Dictionary(uniqueKeysWithValues: map.map { ($0.key.uuidString, $0.value) })
        UserDefaults.standard.set(try? JSONEncoder().encode(encodable), forKey: rememberedKey)
    }

    private func describe(_ error: any Error) -> String {
        switch error {
        case RigKitError.timeout: "timed out. Is it on, in range, and disconnected from the official app?"
        case RigKitError.authenticationFailed(let s): "handshake refused (status \(s))."
        case RigKitError.notConnected: "link dropped during setup."
        default: error.localizedDescription
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated {
            bluetoothState = state
            if state != .poweredOn { isScanning = false }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let kind: RigKind? = services.contains(CBUUID(nsuuid: Switch2.UUIDs.controlService)) ? .switch2
            : services.contains(where: { $0 == CBUUID(nsuuid: Lorax.UUIDs.legacyService) || $0 == CBUUID(nsuuid: Lorax.UUIDs.service) }) ? .peakPro
            : nil
        guard let kind else { return }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? kind.displayName
        let id = peripheral.identifier
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            if let i = discovered.firstIndex(where: { $0.id == id }) {
                discovered[i].rssi = rssi
            } else {
                discovered.append(DiscoveredRig(id: id, name: name, kind: kind, rssi: rssi))
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        MainActor.assumeIsolated { connectWaiters.removeValue(forKey: id)?.resume() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        let id = peripheral.identifier
        MainActor.assumeIsolated {
            connectWaiters.removeValue(forKey: id)?.resume(throwing: error ?? RigKitError.notConnected)
            transports.removeValue(forKey: id)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        let id = peripheral.identifier
        MainActor.assumeIsolated {
            transports.removeValue(forKey: id)?.linkDropped()
            connectWaiters.removeValue(forKey: id)?.resume(throwing: RigKitError.notConnected)
            if let kind = kinds.removeValue(forKey: id) {
                switch kind {
                case .switch2: switch2?.markDisconnected()
                case .peakPro: peakPro?.markDisconnected()
                }
            }
        }
    }
}
