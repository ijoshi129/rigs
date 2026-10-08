import Foundation

/// One connected Switch 2. Owns the transport, keeps `state` current, and
/// paces writes the way the official app does.
///
/// `updates` is a single-consumer stream: read it from one place (the view model).
public actor Switch2Device {
    public let characteristics: Switch2.Characteristics
    private let transport: any BLETransport

    public private(set) var state = Switch2.State()
    public nonisolated let updates: AsyncStream<Switch2.State>
    private let continuation: AsyncStream<Switch2.State>.Continuation

    private var listener: Task<Void, Never>?
    private var lastWrite: ContinuousClock.Instant?
    private var connected = false

    public init(transport: any BLETransport, characteristics: Switch2.Characteristics = .control) {
        self.transport = transport
        self.characteristics = characteristics
        (updates, continuation) = AsyncStream.makeStream(of: Switch2.State.self, bufferingPolicy: .bufferingNewest(1))
    }

    public var isConnected: Bool { connected }

    // MARK: Connection

    /// Subscribes, syncs the clock, and asks for analytics. The device then
    /// streams its full state; watch `state.initialDumpComplete`.
    public func connect() async throws {
        let stream = try await transport.subscribe(to: characteristics.notify)
        connected = true
        listener = Task { [weak self] in
            for await packet in stream {
                await self?.handle(packet)
            }
            await self?.linkDropped()
        }
        try await send(Switch2.Command.syncClock())
        try await Task.sleep(for: Switch2.Limits.presetGap)
        try await send(Switch2.Command.requestAnalytics())
    }

    public func disconnect() async {
        listener?.cancel()
        listener = nil
        await transport.disconnect()
        linkDropped()
    }

    private func linkDropped() {
        connected = false
        continuation.yield(state)
    }

    private func handle(_ packet: Data) {
        guard let message = Switch2.Message.parse(packet) else { return }
        state.apply(message)
        continuation.yield(state)
    }

    // MARK: Writing

    private func send(_ data: Data) async throws {
        guard connected else { throw RigKitError.notConnected }
        if let last = lastWrite {
            let elapsed = ContinuousClock.now - last
            if elapsed < Switch2.Limits.writeGap {
                try await Task.sleep(for: Switch2.Limits.writeGap - elapsed)
            }
        }
        try await transport.write(data, to: characteristics.write, withResponse: false)
        lastWrite = .now
    }

    /// Current settings block, from the last status packet.
    private func currentSettings() throws -> Switch2.Settings {
        guard let s = state.status else { throw RigKitError.notConnected }
        return Switch2.Settings(status: s)
    }

    private func updateSettings(_ change: (inout Switch2.Settings) -> Void) async throws {
        var s = try currentSettings()
        change(&s)
        try await send(Switch2.Command.settings(s))
    }

    // MARK: Session

    public func startSession() async throws { try await updateSettings { $0.sessionActive = true } }
    public func stopSession() async throws { try await updateSettings { $0.sessionActive = false } }

    /// Adds `steps` × 10 s to the running hold. 0 to 9.
    public func extendSession(steps: Int) async throws { try await updateSettings { $0.sessionExtend = steps } }

    public func setActivePreset(_ preset: Int) async throws {
        guard Switch2.Limits.userPresets.contains(preset) else { throw RigKitError.invalidValue("preset \(preset)") }
        try await updateSettings { $0.activePreset = preset }
    }

    // MARK: Device settings

    public func setLightMode(_ code: UInt8) async throws { try await updateSettings { $0.lightMode = code } }
    public func setBrightness(_ percent: Int) async throws { try await updateSettings { $0.brightness = percent } }
    public func setAutoShutOff(minutes: Int) async throws { try await updateSettings { $0.autoShutOffMinutes = minutes } }
    public func setUnit(_ unit: Switch2.TemperatureUnit) async throws { try await updateSettings { $0.unit = unit } }
    public func setHapticFeedback(_ on: Bool) async throws { try await updateSettings { $0.hapticFeedback = on } }

    public func setCleaningAssist(_ on: Bool) async throws { try await send(Switch2.Command.cleaningAssist(on)) }

    public func setDeviceName(_ name: String) async throws {
        let (a, b) = try Switch2.Command.setDeviceName(name)
        try await send(a)
        try await send(b)
    }

    public func requestAnalytics() async throws { try await send(Switch2.Command.requestAnalytics()) }

    // MARK: Presets

    public func setPresetTemperature(preset: Int, fahrenheit: Int) async throws {
        try await send(Switch2.Command.setPresetTemperature(preset: preset, fahrenheit: fahrenheit))
    }

    public func setHoldTime(preset: Int, seconds: Int) async throws {
        try await send(Switch2.Command.setHoldTime(preset: preset, seconds: seconds))
    }

    public func setHeatingProfile(preset: Int, _ profile: Switch2.HeatingProfile) async throws {
        try await send(Switch2.Command.setHeatingProfile(preset: preset, profile))
    }

    /// Switches the preset to Custom and writes the curve, paced at 250 ms.
    public func setCustomCurve(preset: Int, points: [Switch2.CurvePoint]) async throws {
        let (a, b) = try Switch2.Command.setCustomCurve(preset: preset, points: points)
        try await setHeatingProfile(preset: preset, .custom)
        try await Task.sleep(for: Switch2.Limits.presetGap)
        try await send(a)
        try await Task.sleep(for: Switch2.Limits.presetGap)
        try await send(b)
    }

    /// Writes temperature, hold time, and profile for one preset with the
    /// 1 s spacing the official app uses. Curve is written only for Custom.
    public func savePreset(_ preset: Switch2.Preset) async throws {
        let gap: Duration = .seconds(1)
        if let f = preset.fahrenheit {
            try await setPresetTemperature(preset: preset.index, fahrenheit: f)
            try await Task.sleep(for: gap)
        }
        if let h = preset.holdSeconds {
            try await setHoldTime(preset: preset.index, seconds: h)
            try await Task.sleep(for: gap)
        }
        if let p = preset.profile {
            if p == .custom {
                try await setCustomCurve(preset: preset.index, points: preset.curvePoints)
            } else {
                try await setHeatingProfile(preset: preset.index, p)
            }
        }
    }
}
