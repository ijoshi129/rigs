import Foundation
import Observation
import RigKit

/// What the rig told us last time, shown while it resends everything on
/// connect (about six seconds on a real Switch 2).
struct RigSnapshot: Codable, Equatable {
    var name: String?
    var presets: [Switch2.Preset]
    var activePreset: Int?
    var firmwareVersion: String?
    var secondaryVersion: String?
    var analytics: Switch2.Analytics

    init(_ s: Switch2.State) {
        name = s.name
        presets = s.presets
        activePreset = s.status?.activePreset ?? s.activePreset
        firmwareVersion = s.firmwareVersion
        secondaryVersion = s.secondaryVersion
        analytics = s.analytics
    }

    /// Live values win; anything the rig hasn't resent yet comes from here.
    /// Status is never filled in: an old temperature would be wrong.
    func underlay(_ live: Switch2.State) -> Switch2.State {
        var m = live
        m.name = live.name ?? name
        m.activePreset = live.activePreset ?? activePreset
        m.firmwareVersion = live.firmwareVersion ?? firmwareVersion
        m.secondaryVersion = live.secondaryVersion ?? secondaryVersion
        if m.analytics == Switch2.Analytics() { m.analytics = analytics }
        for (i, old) in presets.enumerated() where m.presets.indices.contains(i) {
            if m.presets[i].fahrenheit == nil { m.presets[i].fahrenheit = old.fahrenheit; m.presets[i].celsius = old.celsius }
            if m.presets[i].holdSeconds == nil { m.presets[i].holdSeconds = old.holdSeconds }
            if m.presets[i].profile == nil { m.presets[i].profile = old.profile; m.presets[i].curve = old.curve }
        }
        return m
    }
}

/// Main-actor view of the Switch 2. Survives reconnects: each new link
/// attaches a fresh `Switch2Device`, and the screens keep reading from here.
@MainActor @Observable
final class Switch2Controller {
    private(set) var device: Switch2Device?
    private(set) var state = Switch2.State()
    private(set) var connected = false
    let advertisedName: String
    var lastError: String?

    private let log: SessionLog
    private let liveActivity = LiveActivityController()
    private var task: Task<Void, Never>?
    private let remembers: Bool
    private var snapshot: RigSnapshot?
    private static let snapshotKey = "rigs.lastState"

    /// `remembers` saves what the rig reports and shows it on the next
    /// connect until the rig resends it. The simulated rig doesn't.
    init(name: String, log: SessionLog, remembers: Bool = false) {
        advertisedName = name
        self.log = log
        self.remembers = remembers
        if remembers, let data = UserDefaults.standard.data(forKey: Self.snapshotKey) {
            snapshot = try? JSONDecoder().decode(RigSnapshot.self, from: data)
            if let snapshot { state = snapshot.underlay(state) }
        }
    }

    /// Forgetting the rig drops what we saved about it.
    static func forgetSnapshot() {
        UserDefaults.standard.removeObject(forKey: snapshotKey)
    }

    /// Starts listening to a newly connected device. Call before `device.connect()`.
    func attach(_ device: Switch2Device) {
        task?.cancel()
        self.device = device
        connected = true
        lastError = nil
        task = Task { [weak self] in
            for await s in device.updates {
                guard let self else { return }
                apply(s, from: device)
            }
        }
    }

    func markDisconnected() {
        connected = false
        liveActivity.linkLost()
    }

    private func apply(_ s: Switch2.State, from source: Switch2Device) {
        guard source === device else { return }
        if s.initialDumpComplete {
            state = s
            if remembers { save(s) }
        } else {
            state = snapshot?.underlay(s) ?? s
        }
        // After a drop the device reports its last state once more; that's
        // stale, so keep the Live Activity on "Reconnecting…".
        guard let status = s.status, connected else { return }
        liveActivity.update(s, rigName: name)
        log.track(heating: status.sessionActive, fahrenheit: status.temperatureFahrenheit) {
            let p = s.activePresetSettings
            return (p?.fahrenheit, p?.profile?.name, p?.holdSeconds, status.sessionExtend > 0)
        }
    }

    private func save(_ s: Switch2.State) {
        let fresh = RigSnapshot(s)
        guard fresh != snapshot else { return }
        snapshot = fresh
        UserDefaults.standard.set(try? JSONEncoder().encode(fresh), forKey: Self.snapshotKey)
    }

    // MARK: Derived

    var name: String { state.name ?? advertisedName }
    var status: Switch2.Status? { state.status }
    var isReady: Bool { connected && status != nil }
    var isHeating: Bool { status?.sessionActive ?? false }
    var temperatureF: Int? { status?.temperatureFahrenheit }
    var activeIndex: Int { status?.activePreset ?? state.activePreset ?? 1 }
    var activePreset: Switch2.Preset? { state.activePresetSettings }
    var userPresets: [Switch2.Preset] { Array(state.presets[1...5]) }
    var extend: Int { status?.sessionExtend ?? 0 }

    /// Preset indexes from coolest to hottest.
    var presetsByTemperature: [Int] {
        (1...5).sorted { a, b in
            let fa = state.presets[a].fahrenheit ?? 0, fb = state.presets[b].fahrenheit ?? 0
            return fa != fb ? fa < fb : a < b
        }
    }

    // MARK: Commands

    private func run(_ label: String, _ op: @escaping @Sendable (Switch2Device) async throws -> Void) {
        guard let device else { return }
        Task {
            do {
                try await op(device)
                lastError = nil
            } catch {
                lastError = "\(label): \(Self.describe(error))"
                Diagnostics.shared.record(.error, "\(label) failed: \(error)")
            }
        }
    }

    private func note(_ action: String) { Diagnostics.shared.record(.app, action) }

    func startSession() { note("tap: start session"); run("Start") { try await $0.startSession() } }
    func stopSession() { note("tap: stop session"); run("Stop") { try await $0.stopSession() } }
    func extend(to steps: Int) { note("tap: extend to \(steps)"); run("Extend") { try await $0.extendSession(steps: steps) } }
    func selectPreset(_ i: Int) { note("tap: preset \(i)"); run("Preset") { try await $0.setActivePreset(i) } }
    func setLightMode(_ code: UInt8) { run("Light mode") { try await $0.setLightMode(code) } }
    func setBrightness(_ p: Int) { run("Brightness") { try await $0.setBrightness(p) } }
    func setAutoShutOff(_ m: Int) { run("Auto shut-off") { try await $0.setAutoShutOff(minutes: m) } }
    func setHaptics(_ on: Bool) { run("Haptics") { try await $0.setHapticFeedback(on) } }
    func cleaningAssist(_ on: Bool) { run("Cleaning") { try await $0.setCleaningAssist(on) } }
    func rename(_ n: String) { run("Rename") { try await $0.setDeviceName(n) } }

    /// Runs a command and waits for the write, for Siri and Shortcuts.
    func perform(_ label: String, _ op: @Sendable (Switch2Device) async throws -> Void) async throws {
        guard let device, connected else { throw RigKitError.notConnected }
        do {
            try await op(device)
        } catch {
            Diagnostics.shared.record(.error, "\(label) failed: \(error)")
            throw error
        }
    }

    /// Writes a preset and waits for it, so the editor can show "Saving…".
    func savePreset(_ p: Switch2.Preset) async {
        guard let device else { return }
        do {
            try await device.savePreset(p)
            lastError = nil
        } catch {
            lastError = "Save preset: \(Self.describe(error))"
            Diagnostics.shared.record(.error, "Save preset \(p.index) failed: \(error)")
        }
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case RigKitError.timeout: "the Switch 2 didn't answer in time."
        case RigKitError.notConnected: "the Switch 2 isn't connected."
        case RigKitError.invalidValue(let v): v
        default: error.localizedDescription
        }
    }
}
