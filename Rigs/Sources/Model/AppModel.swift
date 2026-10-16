import Foundation
import Observation
import RigKit

/// Chooses between real Bluetooth and the in-package simulator.
/// The Simulator always uses the fake rig; on a phone, launch with `-mock`.
/// Add `-demo` to start a session a second after launch, and `-fresh` to
/// begin on the connect screen.
@MainActor @Observable
final class AppModel {
    let log = SessionLog()
    let bluetooth: BluetoothManager?
    let isMock: Bool

    private(set) var mockRig: Switch2Controller?
    private var simulator: Switch2Simulator?
    private(set) var mockConnecting = false

    init() {
        #if targetEnvironment(simulator)
        let mock = true
        #else
        let mock = ProcessInfo.processInfo.arguments.contains("-mock")
        #endif
        isMock = mock
        let info = Bundle.main.infoDictionary ?? [:]
        Diagnostics.shared.record(.app, "launch: Rigs \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?")) on \(Diagnostics.deviceModel)\(mock ? ", simulated rig" : "")")
        bluetooth = mock ? nil : BluetoothManager(log: log)
        if mock, !ProcessInfo.processInfo.arguments.contains("-fresh") {
            Task { await connectMock() }
        }
    }

    var rig: Switch2Controller? { isMock ? mockRig : bluetooth?.controller }
    var isSearching: Bool { isMock ? mockConnecting : bluetooth?.isSearching ?? false }
    var isReconnecting: Bool { bluetooth?.isReconnecting ?? false }
    var error: String? { isMock ? nil : bluetooth?.lastError }

    func connect() {
        if isMock { Task { await connectMock() } } else { bluetooth?.search() }
    }

    func forget() async {
        if isMock {
            await mockRig?.device?.disconnect()
            mockRig = nil
            simulator = nil
        } else {
            await bluetooth?.forget()
        }
    }

    // MARK: Siri, Shortcuts and controls

    /// Runs a command from an App Intent. The app may have just been launched
    /// in the background for it, so wait for the remembered rig to reattach.
    func perform(_ command: RigCommand) async throws -> String {
        Diagnostics.shared.record(.app, "intent: \(command)")
        let rig = try await readyRig()
        let units = Units(rawValue: UserDefaults.standard.string(forKey: Prefs.units) ?? "") ?? .f
        func temp(_ f: Int?) -> String { "\(formatTemp(f, units))°\(units.rawValue)" }

        do {
            switch command {
            case .start(let preset):
                if let preset, preset != rig.activeIndex {
                    try await rig.perform("Preset") { try await $0.setActivePreset(preset) }
                    try await waitFor(seconds: 3) { rig.activeIndex == preset }
                }
                if rig.isHeating { return "\(rig.name) is already heating." }
                try await rig.perform("Start") { try await $0.startSession() }
                return "Heating \(rig.name) to \(temp(rig.activePreset?.fahrenheit))."
            case .stop:
                guard rig.isHeating else { return "\(rig.name) isn't heating." }
                try await rig.perform("Stop") { try await $0.stopSession() }
                return "Stopped \(rig.name)."
            case .preset(let preset):
                try await rig.perform("Preset") { try await $0.setActivePreset(preset) }
                try await waitFor(seconds: 3) { rig.activeIndex == preset }
                return "\(rig.name) is on preset \(preset), \(temp(rig.activePreset?.fahrenheit))."
            case .status:
                guard let s = rig.status else { return "\(rig.name) is connected but hasn't reported yet." }
                let battery = "Battery \(s.batteryPercent)%\(s.charging ? ", charging" : "")"
                if s.sessionActive {
                    return "\(rig.name) is at \(temp(s.temperatureFahrenheit)), heating to \(temp(rig.activePreset?.fahrenheit)). \(battery)."
                }
                return "\(rig.name) is idle at \(temp(s.temperatureFahrenheit)), preset \(rig.activeIndex) (\(temp(rig.activePreset?.fahrenheit))). \(battery)."
            }
        } catch let e as RigIntentError {
            throw e
        } catch {
            throw RigIntentError("Couldn't reach \(rig.name): \(Switch2Controller.describe(error))")
        }
    }

    private func readyRig() async throws -> Switch2Controller {
        if isMock, mockRig == nil { await connectMock() }
        if !isMock, let bt = bluetooth, !bt.hasRemembered, bt.controller == nil {
            throw RigIntentError("Connect your Switch 2 in Rigs first.")
        }
        // Bluetooth powers on and reconnects on its own; give it time.
        try? await waitFor(seconds: 15) { self.rig?.isReady == true }
        guard let rig, rig.isReady else {
            throw RigIntentError("Couldn't reach your Switch 2. Is it on and nearby?")
        }
        return rig
    }

    private func waitFor(seconds: Double, _ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(seconds)
        while !condition() {
            guard Date.now < deadline else { throw RigKitError.timeout }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    private func connectMock() async {
        mockConnecting = true
        defer { mockConnecting = false }
        let sim = Switch2Simulator()
        simulator = sim
        let device = Switch2Device(transport: LoggingTransport(sim.transport))
        let ctl = Switch2Controller(name: "Switch 2", log: log)
        ctl.attach(device)
        try? await device.connect()
        mockRig = ctl
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            try? await Task.sleep(for: .seconds(1))
            ctl.startSession()
        }
    }
}
