import CoreBluetooth
import Foundation
import RigKit

/// `BLETransport` over one `CBPeripheral`. Created by `BluetoothManager`
/// after the peripheral connects; call `discover` before anything else.
final class PeripheralTransport: NSObject, BLETransport, CBPeripheralDelegate, @unchecked Sendable {
    let peripheral: CBPeripheral
    private let central: CBCentralManager
    private let lock = NSLock()

    private var characteristics: [UUID: CBCharacteristic] = [:]
    private var notifyStreams: [UUID: AsyncStream<Data>.Continuation] = [:]
    private var notifyWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var readWaiters: [UUID: [CheckedContinuation<Data, any Error>]] = [:]
    private var writeWaiters: [UUID: [CheckedContinuation<Void, any Error>]] = [:]
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var discoveryWaiter: CheckedContinuation<Void, any Error>?
    private var pendingServices = 0
    private var alive = true

    init(peripheral: CBPeripheral, central: CBCentralManager) {
        self.peripheral = peripheral
        self.central = central
        super.init()
        peripheral.delegate = self
    }

    // MARK: Discovery

    /// Discovers the given services and every characteristic under them.
    func discover(services: [UUID]) async throws {
        try await withTimeout(.seconds(15)) { [self] in
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                lock.withLock { discoveryWaiter = cont }
                peripheral.discoverServices(services.map { CBUUID(nsuuid: $0) })
            }
        }
    }

    func hasCharacteristic(_ uuid: UUID) -> Bool {
        lock.withLock { characteristics[uuid] != nil }
    }

    func hasService(_ uuid: UUID) -> Bool {
        peripheral.services?.contains { expand($0.uuid) == uuid } ?? false
    }

    // MARK: BLETransport

    func subscribe(to characteristic: UUID) async throws -> AsyncStream<Data> {
        let c = try char(characteristic)
        let (stream, cont) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        lock.withLock {
            notifyStreams[characteristic]?.finish()
            notifyStreams[characteristic] = cont
        }
        if !c.isNotifying {
            try await withTimeout(.seconds(10)) { [self] in
                try await withCheckedThrowingContinuation { (w: CheckedContinuation<Void, any Error>) in
                    do {
                        let c = try char(characteristic)
                        lock.withLock { notifyWaiters[characteristic] = w }
                        peripheral.setNotifyValue(true, for: c)
                    } catch { w.resume(throwing: error) }
                }
            }
        }
        return stream
    }

    func write(_ data: Data, to characteristic: UUID, withResponse: Bool) async throws {
        let c = try char(characteristic)
        if withResponse {
            try await withTimeout(.seconds(10)) { [self] in
                try await withCheckedThrowingContinuation { (w: CheckedContinuation<Void, any Error>) in
                    do {
                        let c = try char(characteristic)
                        lock.withLock { writeWaiters[characteristic, default: []].append(w) }
                        peripheral.writeValue(data, for: c, type: .withResponse)
                    } catch { w.resume(throwing: error) }
                }
            }
        } else {
            if !peripheral.canSendWriteWithoutResponse {
                await withCheckedContinuation { (w: CheckedContinuation<Void, Never>) in
                    lock.withLock { readyWaiters.append(w) }
                }
            }
            guard lock.withLock({ alive }) else { throw RigKitError.notConnected }
            peripheral.writeValue(data, for: c, type: .withoutResponse)
        }
    }

    func read(from characteristic: UUID) async throws -> Data {
        try await withTimeout(.seconds(10)) { [self] in
            try await withCheckedThrowingContinuation { (w: CheckedContinuation<Data, any Error>) in
                do {
                    let c = try char(characteristic)
                    lock.withLock { readWaiters[characteristic, default: []].append(w) }
                    peripheral.readValue(for: c)
                } catch { w.resume(throwing: error) }
            }
        }
    }

    func disconnect() async {
        central.cancelPeripheralConnection(peripheral)
    }

    /// Called by the manager when CoreBluetooth reports the link gone.
    func linkDropped() {
        let (streams, notifies, reads, writes, ready, disc) = lock.withLock {
            alive = false
            defer {
                notifyStreams.removeAll(); notifyWaiters.removeAll(); readWaiters.removeAll()
                writeWaiters.removeAll(); readyWaiters.removeAll(); discoveryWaiter = nil
            }
            return (Array(notifyStreams.values), Array(notifyWaiters.values),
                    readWaiters.values.flatMap { $0 }, writeWaiters.values.flatMap { $0 }, readyWaiters, discoveryWaiter)
        }
        streams.forEach { $0.finish() }
        notifies.forEach { $0.resume(throwing: RigKitError.notConnected) }
        reads.forEach { $0.resume(throwing: RigKitError.notConnected) }
        writes.forEach { $0.resume(throwing: RigKitError.notConnected) }
        ready.forEach { $0.resume() }
        disc?.resume(throwing: RigKitError.notConnected)
    }

    // MARK: Helpers

    private func char(_ uuid: UUID) throws -> CBCharacteristic {
        guard lock.withLock({ alive }) else { throw RigKitError.notConnected }
        guard let c = lock.withLock({ characteristics[uuid] }) else { throw RigKitError.unsupported("characteristic \(uuid)") }
        return c
    }

    /// 16- and 32-bit CBUUIDs expanded to the Bluetooth base UUID.
    private func expand(_ cb: CBUUID) -> UUID {
        let s = cb.uuidString
        let full: String
        switch s.count {
        case 4: full = "0000\(s)-0000-1000-8000-00805F9B34FB"
        case 8: full = "\(s)-0000-1000-8000-00805F9B34FB"
        default: full = s
        }
        return UUID(uuidString: full) ?? UUID()
    }

    // MARK: CBPeripheralDelegate

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            lock.withLock { discoveryWaiter }?.resume(throwing: error)
            lock.withLock { discoveryWaiter = nil }
            return
        }
        let services = peripheral.services ?? []
        lock.withLock { pendingServices = services.count }
        if services.isEmpty {
            lock.withLock { discoveryWaiter }?.resume()
            lock.withLock { discoveryWaiter = nil }
            return
        }
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        let finished: CheckedContinuation<Void, any Error>? = lock.withLock {
            for c in service.characteristics ?? [] { characteristics[expand(c.uuid)] = c }
            pendingServices -= 1
            if pendingServices <= 0 {
                defer { discoveryWaiter = nil }
                return discoveryWaiter
            }
            return nil
        }
        finished?.resume()
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        let key = expand(characteristic.uuid)
        let w = lock.withLock { notifyWaiters.removeValue(forKey: key) }
        if let error { w?.resume(throwing: error) } else { w?.resume() }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        let key = expand(characteristic.uuid)
        let value = characteristic.value ?? Data()
        // A pending read claims the value; otherwise it is a notification.
        let reader: CheckedContinuation<Data, any Error>? = lock.withLock {
            guard var ws = readWaiters[key], !ws.isEmpty else { return nil }
            let first = ws.removeFirst()
            readWaiters[key] = ws
            return first
        }
        if let reader {
            if let error { reader.resume(throwing: error) } else { reader.resume(returning: value) }
            return
        }
        if error == nil { lock.withLock { notifyStreams[key] }?.yield(value) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        let key = expand(characteristic.uuid)
        let w: CheckedContinuation<Void, any Error>? = lock.withLock {
            guard var ws = writeWaiters[key], !ws.isEmpty else { return nil }
            let first = ws.removeFirst()
            writeWaiters[key] = ws
            return first
        }
        if let error { w?.resume(throwing: error) } else { w?.resume() }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        let ws = lock.withLock { let r = readyWaiters; readyWaiters.removeAll(); return r }
        ws.forEach { $0.resume() }
    }
}
