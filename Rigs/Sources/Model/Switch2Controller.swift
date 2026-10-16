import Foundation
import Observation
import RigKit

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

    init(name: String, log: SessionLog) {
        advertisedName = name
        self.log = log
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
    }

    private func apply(_ s: Switch2.State, from source: Switch2Device) {
        guard source === device else { return }
        state = s
        guard let status = s.status else { return }
        liveActivity.update(s, rigName: name)
        log.track(heating: status.sessionActive, fahrenheit: status.temperatureFahrenheit) {
            let p = s.activePresetSettings
            return (p?.fahrenheit, p?.profile?.name, p?.holdSeconds, status.sessionExtend > 0)
        }
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
