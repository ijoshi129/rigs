import Foundation

/// One connected Peak Pro over Lorax. Handles the handshake, matches replies
/// to commands by sequence number, and polls the paths a dashboard needs.
///
/// `updates` is a single-consumer stream: read it from one place.
public actor PeakProDevice {
    private let transport: any BLETransport

    public private(set) var state = PeakPro.State()
    public nonisolated let updates: AsyncStream<PeakPro.State>
    private let continuation: AsyncStream<PeakPro.State>.Continuation

    private var seq: UInt16 = 0
    private var pending: [UInt16: CheckedContinuation<Lorax.Reply, any Error>] = [:]
    private var replyListener: Task<Void, Never>?
    private var eventListener: Task<Void, Never>?
    private var poller: Task<Void, Never>?

    public var protocolVersion: UInt16?
    public var maxPayload: Int = 240

    public init(transport: any BLETransport) {
        self.transport = transport
        (updates, continuation) = AsyncStream.makeStream(of: PeakPro.State.self, bufferingPolicy: .bufferingNewest(1))
    }

    // MARK: Connection

    /// Subscribe, read version, nudge pairing, get limits, authenticate, load state.
    public func connect() async throws {
        let replies = try await transport.subscribe(to: Lorax.UUIDs.reply)
        replyListener = Task { [weak self] in
            for await d in replies { await self?.handleReply(d) }
            await self?.linkDropped()
        }
        if let events = try? await transport.subscribe(to: Lorax.UUIDs.event) {
            eventListener = Task { for await _ in events {} }
        }
        state.connected = true

        if let v = try? await transport.read(from: Lorax.UUIDs.version), let ver = v.leUInt16 {
            protocolVersion = ver
            if ver > 255 { throw RigKitError.unsupported("Lorax protocol version \(ver)") }
        }

        // Reading an encrypted characteristic makes the OS pair the link.
        _ = try? await transport.read(from: Lorax.UUIDs.pupAppVersion)

        if let limits = try? await send(.getLimits, timeout: .seconds(3)), limits.ok, limits.payload.count >= 2 {
            // Layout is not documented; keep the default unless the first
            // uint16 looks like a sane payload size.
            if let p = limits.payload.prefix(2).leUInt16, (20...512).contains(p) { maxPayload = Int(p) }
        }

        try await authenticate()
        try await refreshIdentity()
        try await refreshSlow()
        try await refreshFast()
        publish()
    }

    public func disconnect() async {
        poller?.cancel(); poller = nil
        replyListener?.cancel(); replyListener = nil
        eventListener?.cancel(); eventListener = nil
        await transport.disconnect()
        linkDropped()
    }

    private func linkDropped() {
        state.connected = false
        state.authenticated = false
        for (_, c) in pending { c.resume(throwing: RigKitError.notConnected) }
        pending.removeAll()
        publish()
    }

    private func publish() { continuation.yield(state) }

    private func authenticate() async throws {
        let seedReply = try await send(.getAccessSeed, timeout: .seconds(10))
        guard seedReply.ok, seedReply.payload.count >= 16 else {
            throw RigKitError.authenticationFailed(status: seedReply.status)
        }
        let token = try Lorax.authToken(seed: seedReply.payload)
        let unlock = try await send(.unlockAccess, token, timeout: .seconds(5))
        guard unlock.ok else { throw RigKitError.authenticationFailed(status: unlock.status) }
        state.authenticated = true
    }

    // MARK: Lorax transport

    private func handleReply(_ d: Data) {
        guard let r = try? Lorax.unpackReply(d) else { return }
        if let c = pending.removeValue(forKey: r.seq) { c.resume(returning: r) }
    }

    private func fail(_ s: UInt16, _ error: any Error) {
        if let c = pending.removeValue(forKey: s) { c.resume(throwing: error) }
    }

    private func send(_ opcode: Lorax.Opcode, _ payload: Data = Data(), timeout: Duration = .milliseconds(1500)) async throws -> Lorax.Reply {
        guard state.connected else { throw RigKitError.notConnected }
        seq &+= 1
        if seq == 0 { seq = 1 }
        let s = seq
        let packet = Lorax.packCommand(seq: s, opcode: opcode, payload: payload)
        let transport = self.transport
        return try await withCheckedThrowingContinuation { cont in
            pending[s] = cont
            Task { [weak self] in
                do {
                    try await transport.write(packet, to: Lorax.UUIDs.command, withResponse: false)
                } catch {
                    await self?.fail(s, error)
                    return
                }
                try? await Task.sleep(for: timeout)
                await self?.fail(s, RigKitError.timeout)
            }
        }
    }

    /// Reads a path. Returns nil on any failure, so polling never throws.
    public func read(_ path: String) async -> Data? {
        guard let r = try? await send(.readShort, Lorax.readShortPayload(path: path, maxLength: UInt16(maxPayload))), r.ok else { return nil }
        return r.payload
    }

    @discardableResult
    public func write(_ path: String, _ value: Data) async throws -> Bool {
        let r = try await send(.writeShort, Lorax.writeShortPayload(path: path, value: value))
        guard r.ok else { throw RigKitError.commandFailed(status: r.status) }
        return true
    }

    private func readString(_ path: String) async -> String? {
        guard let d = await read(path) else { return nil }
        let s = d.cleanString
        return s.isEmpty ? nil : s
    }

    // MARK: Refresh

    private func refreshIdentity() async throws {
        state.name = await readString(Lorax.Path.deviceName)
        state.serial = await readString(Lorax.Path.serialNumber)
        state.hardwareRevision = await readString(Lorax.Path.hardwareRevision)
        if let m = await readString(Lorax.Path.modelCode) {
            state.model = Lorax.Codec.modelNames[m] ?? "Peak Pro (\(m))"
        }
        if let d = await read(Lorax.Path.firmwareRevision), let rev = Lorax.Codec.count(d) {
            state.firmware = Lorax.Codec.firmwareLetters(rev)
        }
    }

    /// State and temperature. Cheap; call often while heating.
    public func refreshFast() async throws {
        if let d = await read(Lorax.Path.operatingState), let s = Lorax.OperatingState(rawValue: d.byte(0)) {
            state.operatingState = s
        }
        if let d = await read(Lorax.Path.chamberTemperature), let f = Lorax.Codec.fahrenheit(d) {
            state.temperatureFahrenheit = f
        }
        if state.isHeating {
            if let d = await read(Lorax.Path.commandedTemperature), let f = Lorax.Codec.fahrenheit(d) {
                state.commandedFahrenheit = f
            }
            let e = await read(Lorax.Path.elapsed).flatMap { Lorax.Codec.seconds($0, millisecondsAbove: 300) }
            let t = await read(Lorax.Path.total).flatMap { Lorax.Codec.seconds($0, millisecondsAbove: 300) }
            state.elapsedSeconds = e
            state.totalSeconds = t
        } else {
            state.elapsedSeconds = nil
            state.totalSeconds = nil
        }
        publish()
    }

    /// Battery, chamber, odometers, profiles, lighting. Every ~10 s is plenty.
    public func refreshSlow() async throws {
        if let d = await read(Lorax.Path.batteryLevel) { state.batteryPercent = Lorax.Codec.battery(d) }
        if let d = await read(Lorax.Path.chargeState) { state.chargeState = Lorax.ChargeState(rawValue: d.byte(0)) }
        if let d = await read(Lorax.Path.chamberType) { state.chamberType = Lorax.ChamberType(rawValue: d.byte(0)) }
        if let d = await read(Lorax.Path.totalDabs) { state.totalDabs = Lorax.Codec.count(d) }
        if let d = await read(Lorax.Path.tripDabs) { state.tripDabs = Lorax.Codec.count(d) }
        if let d = await read(Lorax.Path.dabsRemaining) { state.dabsRemaining = Lorax.Codec.count(d) }
        if let d = await read(Lorax.Path.activeProfile) { state.activeProfile = Int(d.byte(0)) }
        if let d = await read(Lorax.Path.stealthMode) { state.stealthMode = d.byte(0) != 0 }
        if let d = await read(Lorax.Path.lanternCommand) { state.lanternOn = d.byte(0) != 0 }
        if let d = await read(Lorax.Path.lanternColor) { state.lanternColor = Lorax.Color.decode(d) }
        for slot in 0...3 { await refreshProfile(slot) }
        publish()
    }

    public func refreshProfile(_ slot: Int) async {
        var p = state.profiles[slot]
        if let n = await readString(Lorax.Path.profileName(slot)) { p.name = n }
        if let d = await read(Lorax.Path.profileTemperature(slot)) { p.fahrenheit = Lorax.Codec.fahrenheit(d) }
        if let d = await read(Lorax.Path.profileTime(slot)) { p.seconds = Lorax.Codec.seconds(d) }
        if let d = await read(Lorax.Path.profileColor(slot)) { p.color = Lorax.Color.decode(d) }
        if let d = await read(Lorax.Path.profileBoostTemperature(slot)) { p.boostFahrenheit = Lorax.Codec.fahrenheit(d) }
        if let d = await read(Lorax.Path.profileBoostTime(slot)) { p.boostSeconds = Lorax.Codec.seconds(d) }
        state.profiles[slot] = p
    }

    /// Polls fast paths at 250 ms while heating, 1 s idle; slow paths every 10 s.
    public func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                try? await self.refreshFast()
                if tick % 10 == 0 { try? await self.refreshSlow() }
                tick += 1
                let heating = await self.state.isHeating
                try? await Task.sleep(for: heating ? .milliseconds(250) : .seconds(1))
            }
        }
    }

    public func stopPolling() { poller?.cancel(); poller = nil }

    // MARK: Session

    private func mode(_ c: Lorax.ModeCommand) async throws {
        try await write(Lorax.Path.modeCommand, Data([c.rawValue]))
        try await refreshFast()
    }

    public func startSession() async throws { try await mode(.heatCycleStart) }
    public func stopSession() async throws { try await mode(.heatCycleAbort) }
    public func boost() async throws { try await mode(.heatCycleBoost) }

    public func setActiveProfile(_ slot: Int) async throws {
        guard (0...3).contains(slot) else { throw RigKitError.invalidValue("profile \(slot)") }
        try await write(Lorax.Path.activeProfile, Data([UInt8(slot)]))
        state.activeProfile = slot
        publish()
    }

    // MARK: Profiles

    public func setProfileTemperature(slot: Int, fahrenheit: Double) async throws {
        guard (0...3).contains(slot) else { throw RigKitError.invalidValue("profile \(slot)") }
        let c = Temperature.celsius(fromFahrenheit: fahrenheit)
        try await write(Lorax.Path.profileTemperature(slot), Lorax.Codec.encodeCelsius(c))
        state.profiles[slot].fahrenheit = fahrenheit
        publish()
    }

    /// 15 to 180 s. Written as float32, matching the official app.
    public func setProfileDuration(slot: Int, seconds: Double) async throws {
        guard (0...3).contains(slot) else { throw RigKitError.invalidValue("profile \(slot)") }
        guard (15...180).contains(seconds) else { throw RigKitError.invalidValue("duration \(seconds)s") }
        try await write(Lorax.Path.profileTime(slot), .le(Float(seconds)))
        state.profiles[slot].seconds = seconds
        publish()
    }

    public func setProfileName(slot: Int, _ name: String) async throws {
        guard (0...3).contains(slot) else { throw RigKitError.invalidValue("profile \(slot)") }
        try await write(Lorax.Path.profileName(slot), Data(name.utf8.prefix(32)))
        state.profiles[slot].name = name
        publish()
    }

    public func setProfileColor(slot: Int, _ color: Lorax.Color) async throws {
        guard (0...3).contains(slot) else { throw RigKitError.invalidValue("profile \(slot)") }
        try await write(Lorax.Path.profileColor(slot), color.encoded)
        state.profiles[slot].color = color
        publish()
    }

    public func setBoost(slot: Int, fahrenheit: Double? = nil, seconds: Double? = nil) async throws {
        guard (0...3).contains(slot) else { throw RigKitError.invalidValue("profile \(slot)") }
        if let f = fahrenheit {
            try await write(Lorax.Path.profileBoostTemperature(slot), Lorax.Codec.encodeCelsius(Temperature.celsius(fromFahrenheit: f)))
            state.profiles[slot].boostFahrenheit = f
        }
        if let s = seconds {
            try await write(Lorax.Path.profileBoostTime(slot), .le(Float(s)))
            state.profiles[slot].boostSeconds = s
        }
        publish()
    }

    // MARK: Lighting

    /// Sets color and mode, then turns the lantern on with the 2-hour timer the official app uses.
    public func setLantern(on: Bool, color: Lorax.Color? = nil) async throws {
        if let color {
            try await write(Lorax.Path.lanternColor, color.encoded)
            state.lanternColor = color
        }
        if on, !state.lanternOn {
            try await write(Lorax.Path.lanternTime, .le(Lorax.lanternSeconds))
        }
        try await write(Lorax.Path.lanternCommand, Data([on ? 1 : 0]))
        state.lanternOn = on
        publish()
    }

    /// One of Puffco's built-in animations (`Lorax.Color.disco` etc.).
    public func setLanternAnimation(_ raw: Data) async throws {
        try await write(Lorax.Path.lanternColor, raw)
        if !state.lanternOn {
            try await write(Lorax.Path.lanternTime, .le(Lorax.lanternSeconds))
            try await write(Lorax.Path.lanternCommand, Data([1]))
            state.lanternOn = true
        }
        publish()
    }

    /// 0...255, applied to all four LED zones.
    public func setLanternBrightness(_ value: UInt8) async throws {
        try await write(Lorax.Path.lanternBrightness, Data(repeating: value, count: 4))
    }

    public func setStealthMode(_ on: Bool) async throws {
        try await write(Lorax.Path.stealthMode, Data([on ? 1 : 0]))
        state.stealthMode = on
        publish()
    }

    public func setDeviceName(_ name: String) async throws {
        try await write(Lorax.Path.deviceName, Data(name.utf8.prefix(32)))
        state.name = name
        publish()
    }
}
