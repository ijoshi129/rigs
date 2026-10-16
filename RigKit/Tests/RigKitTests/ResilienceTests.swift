import Foundation
import Testing
@testable import RigKit

// MARK: - Helpers

/// The first update matching `condition`, or a timeout instead of a hung test.
private func next(_ dev: Switch2Device, _ condition: @escaping @Sendable (Switch2.State) -> Bool) async throws -> Switch2.State {
    try await withTimeout(.seconds(5)) {
        for await s in dev.updates where condition(s) { return s }
        throw RigKitError.notConnected
    }
}

/// Every update left until the stream ends; fails if it never does.
private func drain(_ dev: Switch2Device) async throws -> [Switch2.State] {
    try await withTimeout(.seconds(5)) {
        var all: [Switch2.State] = []
        for await s in dev.updates { all.append(s) }
        return all
    }
}

private func connected(_ sim: Switch2Simulator) async throws -> Switch2Device {
    let dev = Switch2Device(transport: sim.transport)
    try await dev.connect()
    _ = try await next(dev) { $0.initialDumpComplete && $0.status != nil }
    return dev
}

private func fastSim() -> Switch2Simulator {
    let sim = Switch2Simulator()
    sim.speed = 50
    return sim
}

// MARK: - Malformed packets

@Suite struct MalformedPacketTests {
    /// Packets captured from a real Switch 2 ("Zuko"), 2026-10-16.
    @Test func realRigPacketsParse() throws {
        let status = Data([0xa9, 0x14, 0x00, 0x02, 0x00, 0x01, 0x21, 0x00, 0x0f, 0x00, 0x00, 0x47, 0x0f, 0x00, 0xaa, 0x00, 0x52, 0x00, 0x35, 0xa9])
        guard case let .status(s)? = Switch2.Message.parse(status) else { Issue.record("no status"); return }
        #expect(s.activePreset == 2 && s.lightMode == 33 && !s.sessionActive)
        #expect(s.temperatureFahrenheit == 71 && s.batteryPercent == 82 && s.brightness == 53)

        #expect(Switch2.Message.parse(Data([0xa3, 0x08, 0x03, 0x01, 0xf3, 0x01, 0x03, 0xa3])) == .presetTemperature(preset: 3, fahrenheit: 499, celsius: 259))
        #expect(Switch2.Message.parse(Data([0xa5, 0x05, 0x01, 0xc1, 0xa5])) == .presetProfile(preset: 1, profile: .descent))
        #expect(Switch2.Message.parse(Data([0xc3, 0x0b] + Array("22680412".utf8) + [0xc3])) == .firmwareVersion("22680412"))
        #expect(Switch2.Message.parse(Data([0xad, 0x06, 0xff, 0x00, 0x00, 0xad])) == .unknown(opcode: 173, Data([0xad, 0x06, 0xff, 0x00, 0x00, 0xad])))
    }

    @Test func badFramingIsDropped() {
        let status: [UInt8] = [169, 20, 0, 3, 0, 0, 12, 170, 15, 14, 1, 244, 15, 27, 170, 1, 87, 0, 60, 169]
        #expect(Switch2.Message.parse(Data()) == nil)
        #expect(Switch2.Message.parse(Data([169])) == nil)
        #expect(Switch2.Message.parse(Data([169, 20])) == nil)
        #expect(Switch2.Message.parse(Data(status.prefix(10))) == nil, "truncated")
        #expect(Switch2.Message.parse(Data(status.dropLast() + [0])) == nil, "wrong trailer")
        var wrongLength = status
        wrongLength[1] = 19
        #expect(Switch2.Message.parse(Data(wrongLength)) == nil, "length byte disagrees")
        // A cut-off preset packet used to read as "preset 2 is 0 °F".
        #expect(Switch2.Message.parse(Data([163, 8, 2])) == nil)
    }

    @Test func outOfRangeIndexesLeaveStateAlone() {
        var s = Switch2.State()
        s.apply(.presetTemperature(preset: 2, fahrenheit: 500, celsius: 260))
        let before = s.presets
        s.apply(.presetTemperature(preset: 9, fahrenheit: 650, celsius: 343))
        s.apply(.presetHoldTime(preset: 200, seconds: 90))
        s.apply(.presetProfile(preset: 6, profile: .hill))
        s.apply(.unknown(opcode: 173, Data([173, 6, 255, 0, 0, 173])))
        #expect(s.presets == before)
    }

    @Test func garbageMidStreamDoesNotCorruptState() async throws {
        let sim = fastSim()
        let dev = try await connected(sim)
        let notify = Switch2.Characteristics.control.notify
        sim.transport.emit(Data([163, 8, 2]), on: notify)                    // cut-off preset temperature
        sim.transport.emit(Data([169, 20, 0, 5]), on: notify)                // cut-off status
        sim.transport.emit(Data((0..<20).map { _ in UInt8.random(in: 0...255) }), on: notify)
        sim.transport.emit(Data(), on: notify)
        // A good packet afterwards still lands.
        sim.transport.emit(Data([168, 4, 4, 168]), on: notify)
        let s = try await next(dev) { $0.activePreset == 4 }
        #expect(s.presets[2].fahrenheit == 500)
        #expect(s.status?.activePreset == 2)
        await dev.disconnect()
    }
}

// MARK: - Link drops and reconnects

@Suite struct LinkDropTests {
    @Test func dropMidHeatEndsUpdatesAndFailsWrites() async throws {
        let sim = fastSim()
        let dev = try await connected(sim)
        try await dev.startSession()
        _ = try await next(dev) { $0.status?.sessionActive == true }

        sim.transport.dropLink()
        let rest = try await drain(dev)
        #expect(rest.last?.status?.sessionActive == true, "last known state is still reported once")
        #expect(await !dev.isConnected)

        // Commands fail at once instead of hanging.
        await #expect(throws: RigKitError.notConnected) { try await dev.stopSession() }
        await #expect(throws: RigKitError.notConnected) { try await dev.setPresetTemperature(preset: 1, fahrenheit: 400) }
    }

    @Test func reconnectMidHeatPicksUpTheRunningSession() async throws {
        let sim = fastSim()
        let first = try await connected(sim)
        try await first.startSession()
        _ = try await next(first) { $0.status?.sessionActive == true }
        sim.transport.dropLink()
        _ = try await drain(first)

        // The rig keeps heating on its own while the phone is away.
        sim.transport.reopen()
        let second = try await connected(sim)
        let s = await second.state
        #expect(s.status?.sessionActive == true)
        #expect((s.status?.temperature ?? 0) > 72)

        try await second.stopSession()
        let stopped = try await next(second) { $0.status?.sessionActive == false }
        #expect(stopped.status?.sessionActive == false)
        // The old device stays dead.
        await #expect(throws: RigKitError.notConnected) { try await first.startSession() }
        await second.disconnect()
    }

    @Test func requestedDisconnectEndsUpdatesOnce() async throws {
        let sim = fastSim()
        let dev = try await connected(sim)
        await dev.disconnect()
        let rest = try await drain(dev)
        #expect(rest.count <= 1)
        // A second disconnect is harmless.
        await dev.disconnect()
        #expect(await !dev.isConnected)
    }

    @Test func dropRightAfterConnectDoesNotHang() async throws {
        let sim = Switch2Simulator()
        let dev = Switch2Device(transport: sim.transport)
        try await dev.connect()
        sim.transport.dropLink()
        _ = try await drain(dev)
        await #expect(throws: RigKitError.notConnected) { try await dev.startSession() }
    }
}
