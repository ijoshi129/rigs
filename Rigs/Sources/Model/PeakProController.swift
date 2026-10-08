import Foundation
import Observation
import RigKit

/// Main-actor view of one Peak Pro.
@MainActor @Observable
final class PeakProController {
    let device: PeakProDevice
    let name: String

    private(set) var state = PeakPro.State()
    private(set) var history: [TemperatureSample] = []
    private(set) var connected = true
    var lastError: String?

    private var task: Task<Void, Never>?
    private var wasHeating = false

    init(device: PeakProDevice, name: String) {
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

    private func apply(_ s: PeakPro.State) {
        state = s
        connected = s.connected
        let heating = s.isHeating
        if heating, !wasHeating { history.removeAll() }
        wasHeating = heating
        guard let f = s.temperatureFahrenheit else { return }
        if heating || history.last.map({ abs($0.fahrenheit - f) >= 1 }) ?? true {
            history.append(TemperatureSample(time: Date(), fahrenheit: f))
            if history.count > 900 { history.removeFirst(history.count - 900) }
        }
    }

    // MARK: Derived

    var displayName: String { state.name ?? name }
    var isHeating: Bool { state.isHeating }
    var temperatureF: Double? { state.temperatureFahrenheit }
    var targetF: Double? { state.activeProfileSettings.fahrenheit }
    var profiles: [PeakPro.Profile] { state.profiles }
    var activeProfile: PeakPro.Profile { state.activeProfileSettings }

    // MARK: Commands

    private func run(_ label: String, _ op: @escaping @Sendable () async throws -> Void) {
        Task {
            do { try await op() } catch { lastError = "\(label): \(error)" }
        }
    }

    func startSession() { run("Start") { [device] in try await device.startSession() } }
    func stopSession() { run("Stop") { [device] in try await device.stopSession() } }
    func boost() { run("Boost") { [device] in try await device.boost() } }
    func selectProfile(_ slot: Int) { run("Profile") { [device] in try await device.setActiveProfile(slot) } }
    func setProfileTemperature(_ slot: Int, fahrenheit: Double) {
        run("Temperature") { [device] in try await device.setProfileTemperature(slot: slot, fahrenheit: fahrenheit) }
    }
    func setProfileDuration(_ slot: Int, seconds: Double) {
        run("Duration") { [device] in try await device.setProfileDuration(slot: slot, seconds: seconds) }
    }
    func setProfileName(_ slot: Int, _ name: String) { run("Name") { [device] in try await device.setProfileName(slot: slot, name) } }
    func setProfileColor(_ slot: Int, _ c: Lorax.Color) { run("Color") { [device] in try await device.setProfileColor(slot: slot, c) } }
    func setLantern(on: Bool, color: Lorax.Color? = nil) { run("Lantern") { [device] in try await device.setLantern(on: on, color: color) } }
    func setLanternBrightness(_ v: UInt8) { run("Brightness") { [device] in try await device.setLanternBrightness(v) } }
    func setStealth(_ on: Bool) { run("Stealth") { [device] in try await device.setStealthMode(on) } }
    func rename(_ n: String) { run("Rename") { [device] in try await device.setDeviceName(n) } }
}
