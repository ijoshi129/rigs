import Foundation
import Observation
import RigKit

struct TemperatureSample: Identifiable, Equatable, Sendable {
    let id = UUID()
    let time: Date
    let fahrenheit: Double
}

/// Main-actor view of one Switch 2: current state, a temperature history
/// for the curve, and fire-and-forget commands that surface errors.
@MainActor @Observable
final class Switch2Controller {
    let device: Switch2Device
    let name: String

    private(set) var state = Switch2.State()
    private(set) var history: [TemperatureSample] = []
    private(set) var connected = true
    var lastError: String?

    private var task: Task<Void, Never>?
    private var wasInSession = false

    init(device: Switch2Device, name: String) {
        self.device = device
        self.name = name
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            guard let device = self?.device else { return }
            for await s in device.updates {
                guard let self else { return }
                apply(s)
            }
        }
    }

    func markDisconnected() {
        connected = false
    }

    private func apply(_ s: Switch2.State) {
        state = s
        guard let status = s.status else { return }
        let inSession = status.sessionActive
        if inSession, !wasInSession { history.removeAll() }
        wasInSession = inSession
        let f = Double(status.temperatureFahrenheit)
        if inSession || history.last.map({ abs($0.fahrenheit - f) >= 1 }) ?? true {
            history.append(TemperatureSample(time: Date(), fahrenheit: f))
            if history.count > 900 { history.removeFirst(history.count - 900) }
        }
    }

    // MARK: Derived

    var status: Switch2.Status? { state.status }
    var isHeating: Bool { status?.sessionActive ?? false }
    var temperatureF: Double? { status.map { Double($0.temperatureFahrenheit) } }
    var activePreset: Switch2.Preset? { state.activePresetSettings }
    var targetF: Double? { activePreset?.fahrenheit.map(Double.init) }
    var userPresets: [Switch2.Preset] { Array(state.presets[1...5]) }
    var lightMode: Switch2.LightMode { Switch2.LightMode.named(status?.lightMode ?? 1) }

    // MARK: Commands

    private func run(_ label: String, _ op: @escaping @Sendable () async throws -> Void) {
        Task {
            do { try await op() } catch { lastError = "\(label): \(error)" }
        }
    }

    func startSession() { run("Start") { [device] in try await device.startSession() } }
    func stopSession() { run("Stop") { [device] in try await device.stopSession() } }
    func extend(_ steps: Int) { run("Extend") { [device] in try await device.extendSession(steps: steps) } }
    func selectPreset(_ i: Int) { run("Preset") { [device] in try await device.setActivePreset(i) } }
    func setLightMode(_ code: UInt8) { run("Lighting") { [device] in try await device.setLightMode(code) } }
    func setBrightness(_ p: Int) { run("Brightness") { [device] in try await device.setBrightness(p) } }
    func setAutoShutOff(_ m: Int) { run("Auto shut-off") { [device] in try await device.setAutoShutOff(minutes: m) } }
    func setHaptics(_ on: Bool) { run("Haptics") { [device] in try await device.setHapticFeedback(on) } }
    func setUnit(_ u: Switch2.TemperatureUnit) { run("Units") { [device] in try await device.setUnit(u) } }
    func cleaningAssist(_ on: Bool) { run("Cleaning") { [device] in try await device.setCleaningAssist(on) } }
    func savePreset(_ p: Switch2.Preset) { run("Save preset") { [device] in try await device.savePreset(p) } }
    func rename(_ n: String) { run("Rename") { [device] in try await device.setDeviceName(n) } }
}
