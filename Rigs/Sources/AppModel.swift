import Foundation
import Observation
import RigKit

/// Chooses between real Bluetooth and the in-package simulators.
/// Launch with `-mock` (or on the simulator, where there is no Bluetooth)
/// to get two fake rigs that heat, cool, and answer every command.
@MainActor @Observable
final class AppModel {
    let bluetooth: BluetoothManager?
    let isMock: Bool

    private(set) var mockSwitch2: Switch2Controller?
    private(set) var mockPeakPro: PeakProController?
    // The simulators only hold weak references from their transports, so
    // the app must keep them alive.
    private var simulators: [AnyObject] = []

    init() {
        #if targetEnvironment(simulator)
        let mock = true
        #else
        let mock = ProcessInfo.processInfo.arguments.contains("-mock")
        #endif
        isMock = mock
        bluetooth = mock ? nil : BluetoothManager()
        if mock { Task { await startMocks() } }
    }

    var switch2: Switch2Controller? { isMock ? mockSwitch2 : bluetooth?.switch2 }
    var peakPro: PeakProController? { isMock ? mockPeakPro : bluetooth?.peakPro }
    var hasAnyRig: Bool { switch2 != nil || peakPro != nil }

    private func startMocks() async {
        let s = Switch2Simulator()
        simulators.append(s)
        let sDev = Switch2Device(transport: s.transport)
        let sCtl = Switch2Controller(device: sDev, name: "Switch 2")
        sCtl.start()
        try? await sDev.connect()
        mockSwitch2 = sCtl

        let p = PeakProSimulator()
        simulators.append(p)
        let pDev = PeakProDevice(transport: p.transport)
        let pCtl = PeakProController(device: pDev, name: "Peak Pro")
        pCtl.start()
        try? await pDev.connect()
        await pDev.startPolling()
        mockPeakPro = pCtl

        // `-demo`: start both fake rigs so screenshots show a live session.
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            try? await Task.sleep(for: .seconds(1))
            sCtl.startSession()
            pCtl.startSession()
        }
    }

    func disconnect(_ kind: RigKind) async {
        if isMock {
            switch kind {
            case .switch2: await mockSwitch2?.device.disconnect(); mockSwitch2 = nil
            case .peakPro: await mockPeakPro?.device.disconnect(); mockPeakPro = nil
            }
        } else {
            await bluetooth?.disconnect(kind)
        }
    }
}
