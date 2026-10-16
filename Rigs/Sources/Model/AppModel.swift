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
