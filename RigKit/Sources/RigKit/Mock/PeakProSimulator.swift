import Foundation

/// A fake Peak Pro: a Lorax path store behind a `MockTransport`, with the
/// real handshake check and a simulated heat cycle.
public final class PeakProSimulator: @unchecked Sendable {
    public let transport = MockTransport()

    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var seed = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    private var unlocked = false
    private var heater: Task<Void, Never>?
    private var celsius: Float = 22
    private var elapsed: Float = 0
    public var speed: Double = 1
    public var requireAuthentication = true

    public init() {
        files[Lorax.Path.deviceName] = Data("Peak Pro".utf8)
        files[Lorax.Path.serialNumber] = Data("SIMPEAK0001".utf8)
        files[Lorax.Path.hardwareRevision] = Data("3".utf8)
        files[Lorax.Path.modelCode] = Data("21".utf8)
        files[Lorax.Path.firmwareRevision] = .le(UInt32(28))     // "AG"
        files[Lorax.Path.operatingState] = Data([Lorax.OperatingState.idle.rawValue])
        files[Lorax.Path.chamberTemperature] = .le(celsius)
        files[Lorax.Path.commandedTemperature] = .le(Float(0))
        files[Lorax.Path.elapsed] = .le(Float(0))
        files[Lorax.Path.total] = .le(Float(0))
        files[Lorax.Path.activeProfile] = Data([1])
        files[Lorax.Path.chamberType] = Data([Lorax.ChamberType.xl.rawValue])
        files[Lorax.Path.batteryLevel] = Data([64])
        files[Lorax.Path.chargeState] = Data([Lorax.ChargeState.disconnected.rawValue])
        files[Lorax.Path.totalDabs] = .le(UInt32(1342))
        files[Lorax.Path.tripDabs] = .le(UInt32(17))
        files[Lorax.Path.dabsRemaining] = .le(UInt32(9))
        files[Lorax.Path.stealthMode] = Data([0])
        files[Lorax.Path.lanternCommand] = Data([0])
        files[Lorax.Path.lanternColor] = Lorax.Color(red: 0, green: 180, blue: 255).encoded
        let defaults: [(String, Float, Float, Lorax.Color)] = [
            ("Low", 232, 60, Lorax.Color(red: 0, green: 200, blue: 120)),
            ("Medium", 260, 60, Lorax.Color(red: 0, green: 120, blue: 255)),
            ("High", 288, 60, Lorax.Color(red: 255, green: 120, blue: 0)),
            ("Peak", 315, 75, Lorax.Color(red: 255, green: 0, blue: 80)),
        ]
        for (i, d) in defaults.enumerated() {
            files[Lorax.Path.profileName(i)] = Data(d.0.utf8)
            files[Lorax.Path.profileTemperature(i)] = .le(d.1)
            files[Lorax.Path.profileTime(i)] = .le(d.2)
            files[Lorax.Path.profileColor(i)] = d.3.encoded
            files[Lorax.Path.profileBoostTemperature(i)] = .le(Float(5))
            files[Lorax.Path.profileBoostTime(i)] = .le(Float(10))
        }
        transport.onWrite = { [weak self] c, d in self?.receive(c, d) }
        transport.onRead = { [weak self] c in try self?.readChar(c) ?? Data() }
    }

    private func readChar(_ c: UUID) throws -> Data {
        switch c {
        case Lorax.UUIDs.version: return .le(UInt16(1))
        case Lorax.UUIDs.pupAppVersion: return Data([1, 0, 0, 0])
        default: throw RigKitError.unsupported("read \(c)")
        }
    }

    private func reply(_ seq: UInt16, _ status: UInt8, _ payload: Data = Data()) {
        transport.emit(Data.le(seq) + Data([status]) + payload, on: Lorax.UUIDs.reply)
    }

    private func receive(_ c: UUID, _ d: Data) {
        guard c == Lorax.UUIDs.command, d.count >= 3, let seq = d.prefix(2).leUInt16,
              let op = Lorax.Opcode(rawValue: d.byte(2)) else { return }
        let payload = Data(d.dropFirst(3))
        switch op {
        case .getAccessSeed:
            reply(seq, 0, lock.withLock { seed })
        case .unlockAccess:
            let expected = try? Lorax.authToken(seed: lock.withLock { seed })
            let ok = payload == expected
            lock.withLock { unlocked = ok }
            reply(seq, ok ? 0 : 1)
        case .getLimits:
            reply(seq, 0, Data.le(UInt16(240)) + Data([32, 32]))
        case .readShort:
            guard authorized else { reply(seq, 5); return }
            let path = String(decoding: payload.dropFirst(4), as: UTF8.self)
            if let v = lock.withLock({ files[path] }) { reply(seq, 0, v) } else { reply(seq, 2) }
        case .writeShort:
            guard authorized else { reply(seq, 5); return }
            let body = payload.dropFirst(3)
            guard let nul = body.firstIndex(of: 0) else { reply(seq, 3); return }
            let path = String(decoding: body[body.startIndex..<nul], as: UTF8.self)
            let value = Data(body[(nul + 1)...])
            lock.withLock { files[path] = value }
            reply(seq, 0)
            if path == Lorax.Path.modeCommand, let cmd = Lorax.ModeCommand(rawValue: value.byte(0)) { handleMode(cmd) }
        default:
            reply(seq, 4)
        }
    }

    private var authorized: Bool { !requireAuthentication || lock.withLock { unlocked } }

    // MARK: Heat cycle

    private func handleMode(_ cmd: Lorax.ModeCommand) {
        switch cmd {
        case .heatCycleStart: startCycle()
        case .heatCycleAbort: abortCycle()
        case .heatCycleBoost:
            lock.withLock {
                let slot = Int(files[Lorax.Path.activeProfile]?.byte(0) ?? 0)
                let add = files[Lorax.Path.profileBoostTime(slot)]?.leFloat32 ?? 10
                let total = files[Lorax.Path.total]?.leFloat32 ?? 0
                files[Lorax.Path.total] = .le(total + add)
            }
        default: break
        }
    }

    private func setState(_ s: Lorax.OperatingState) { lock.withLock { files[Lorax.Path.operatingState] = Data([s.rawValue]) } }

    private func startCycle() {
        heater?.cancel()
        let (target, duration): (Float, Float) = lock.withLock {
            let slot = Int(files[Lorax.Path.activeProfile]?.byte(0) ?? 0)
            return (files[Lorax.Path.profileTemperature(slot)]?.leFloat32 ?? 260, files[Lorax.Path.profileTime(slot)]?.leFloat32 ?? 60)
        }
        lock.withLock {
            elapsed = 0
            files[Lorax.Path.total] = .le(duration)
            files[Lorax.Path.elapsed] = .le(Float(0))
            files[Lorax.Path.commandedTemperature] = .le(target)
        }
        setState(.preheat)
        heater = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let phase: Lorax.OperatingState = lock.withLock {
                    if celsius < target {
                        celsius = min(target, celsius + Float(12 * speed))
                        files[Lorax.Path.chamberTemperature] = .le(celsius)
                        return .preheat
                    }
                    elapsed += Float(0.25 * speed)
                    files[Lorax.Path.elapsed] = .le(elapsed)
                    let total = files[Lorax.Path.total]?.leFloat32 ?? duration
                    if elapsed >= total {
                        let n = files[Lorax.Path.totalDabs]?.leUInt32 ?? 0
                        files[Lorax.Path.totalDabs] = .le(n + 1)
                        return .fade
                    }
                    return .active
                }
                setState(phase)
                if phase == .fade { break }
                try? await Task.sleep(for: .milliseconds(Int(250 / speed)))
            }
            if !Task.isCancelled { await coolDown() }
        }
    }

    private func abortCycle() {
        heater?.cancel()
        setState(.fade)
        heater = Task { [weak self] in await self?.coolDown() }
    }

    private func coolDown() async {
        while !Task.isCancelled {
            let cool: Bool = lock.withLock {
                celsius = max(22, celsius - Float(6 * speed))
                files[Lorax.Path.chamberTemperature] = .le(celsius)
                return celsius <= 22
            }
            if cool { break }
            try? await Task.sleep(for: .milliseconds(Int(500 / speed)))
        }
        setState(.idle)
    }

    /// Test hook: the value currently stored at a path.
    public func value(at path: String) -> Data? { lock.withLock { files[path] } }
}
