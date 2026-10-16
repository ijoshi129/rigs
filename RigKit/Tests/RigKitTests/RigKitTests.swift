import Foundation
import Testing
@testable import RigKit

// MARK: - Switch 2 packets

@Suite struct Switch2CommandTests {
    @Test func clockSyncLayout() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 21, minute: 5))!
        #expect(Switch2.Command.syncClock(date).byteArray == [177, 9, 7, 234, 10, 8, 21, 5, 177])
    }

    @Test func analyticsRequest() {
        #expect(Switch2.Command.requestAnalytics().byteArray == [178, 4, 255, 178])
    }

    @Test func presetTemperatureSendsBothUnits() throws {
        // 500 °F → 260 °C
        let d = try Switch2.Command.setPresetTemperature(preset: 1, fahrenheit: 500)
        #expect(d.byteArray == [179, 8, 1, 1, 244, 1, 4, 179])
        #expect(throws: RigKitError.self) { try Switch2.Command.setPresetTemperature(preset: 1, fahrenheit: 700) }
        #expect(throws: RigKitError.self) { try Switch2.Command.setPresetTemperature(preset: 6, fahrenheit: 500) }
    }

    @Test func profileHoldAndCleaning() throws {
        #expect(try Switch2.Command.setHeatingProfile(preset: 3, .hill).byteArray == [181, 5, 3, 225, 181])
        #expect(try Switch2.Command.setHoldTime(preset: 2, seconds: 45).byteArray == [183, 6, 2, 0, 45, 183])
        #expect(Switch2.Command.cleaningAssist(true).byteArray == [198, 4, 170, 198])
        #expect(Switch2.Command.cleaningAssist(false).byteArray == [198, 4, 0, 198])
    }

    @Test func settingsPacketIsTwentyBytes() throws {
        var s = Switch2.Settings()
        s.activePreset = 3; s.lightMode = 12; s.autoShutOffMinutes = 15; s.unit = .fahrenheit
        s.sessionActive = true; s.hapticFeedback = true; s.sessionExtend = 2; s.brightness = 80
        let d = try Switch2.Command.settings(s)
        #expect(d.count == 20)
        #expect(d.byteArray == [185, 20, 0, 3, 0, 0, 12, 0, 15, 15, 170, 170, 2, 80, 0, 0, 0, 0, 0, 185])
    }

    @Test func nameSplitsAt17() throws {
        let (a, b) = try Switch2.Command.setDeviceName("My Favorite Rig Ever")
        #expect(a.count == 20 && b.count == 15)
        #expect(a.byte(0) == 209 && a.byte(19) == 209)
        #expect(String(decoding: a.dropFirst(2).dropLast(1), as: UTF8.self) == "My Favorite Rig E")
        #expect(String(decoding: b.dropFirst(2).dropLast(1).prefix(3), as: UTF8.self) == "ver")
        #expect(throws: RigKitError.self) { try Switch2.Command.setDeviceName("") }
        #expect(throws: RigKitError.self) { try Switch2.Command.setDeviceName("ünïcödé") }
    }

    @Test func customCurveSortsAndPads() throws {
        let pts = [Switch2.CurvePoint(seconds: 20, fahrenheit: 450), Switch2.CurvePoint(seconds: 5, fahrenheit: 550)]
        let (a, b) = try Switch2.Command.setCustomCurve(preset: 1, points: pts)
        #expect(a.count == 19 && b.count == 19)
        #expect(a.byteArray.prefix(8) == [186, 19, 1, 2, 38, 1, 32, 5])   // 550°F, 288°C, 5 s first
        #expect(b.byteArray == [187, 19, 1] + Array(repeating: 0, count: 15) + [187])
    }
}

@Suite struct Switch2UUIDTests {
    @Test func everyCharacteristicSetIsDiscoverable() {
        #expect(Switch2.Characteristics.all == [.control, .fallback, .go])
        #expect(Set(Switch2.Characteristics.all.map(\.write)).count == 3)
        #expect(Switch2.UUIDs.optionalServices.contains(Switch2.UUIDs.goService))
        #expect(!Switch2.UUIDs.optionalServices.contains(Switch2.UUIDs.otaService))
    }
}

@Suite struct Switch2MessageTests {
    @Test func statusParses() throws {
        let raw: [UInt8] = [169, 20, 0, 3, 0, 0, 12, 170, 15, 14, 1, 244, 15, 27, 170, 1, 87, 0, 60, 169]
        guard case let .status(s)? = Switch2.Message.parse(Data(raw)) else { Issue.record("no status"); return }
        #expect(s.activePreset == 3)
        #expect(s.lightMode == 12)
        #expect(s.sessionActive)
        #expect(s.temperature == 500 && s.unit == .fahrenheit)
        #expect(s.temperatureCelsius == 260)
        #expect(s.sessionSecondsRemaining == 27)
        #expect(s.hapticFeedback && !s.charging)
        #expect(s.batteryPercent == 87 && s.brightness == 60)
    }

    @Test func presetPacketsParse() {
        #expect(Switch2.Message.parse(Data([163, 8, 2, 2, 38, 1, 32, 163])) == .presetTemperature(preset: 2, fahrenheit: 550, celsius: 288))
        #expect(Switch2.Message.parse(Data([165, 5, 4, 241, 165])) == .presetProfile(preset: 4, profile: .custom))
        #expect(Switch2.Message.parse(Data([167, 6, 1, 0, 90, 167])) == .presetHoldTime(preset: 1, seconds: 90))
        #expect(Switch2.Message.parse(Data([168, 4, 5, 168])) == .activePreset(5))
    }

    @Test func analyticsLength20() {
        let raw: [UInt8] = [162, 20, 1, 244, 1, 4, 1, 44, 0, 9, 0, 48, 193, 10, 16, 0, 0, 2, 0, 162]
        guard case let .analytics(a)? = Switch2.Message.parse(Data(raw)) else { Issue.record("no analytics"); return }
        #expect(a.favoriteTempF == 500 && a.favoriteTempC == 260)
        #expect(a.totalHeatingCycles == 300 && a.mostCyclesInADay == 9 && a.totalChargeCycles == 48)
        #expect(a.favoriteHeatingProfile == .descent && a.favoriteLightMode == 10)
        #expect(a.totalTime == 4096 && a.totalDeviceResets == 2)
    }

    @Test func stateAssemblesNameAndCurve() {
        var s = Switch2.State()
        s.apply(.nameChunk(final: false, Data("My Favorite Rig E".utf8)))
        s.apply(.nameChunk(final: true, Data("ver".utf8)))
        #expect(s.name == "My Favorite Rig Ever")
        s.apply(.customCurve(preset: 1, startIndex: 3, points: [Switch2.CurvePoint(seconds: 40, fahrenheit: 400)]))
        #expect(s.presets[1].curve[3].fahrenheit == 400)
        #expect(s.presets[1].curvePoints.count == 1)
        #expect(!s.initialDumpComplete)
    }
}

// MARK: - Device actors against simulators

@Suite struct Switch2DeviceTests {
    @Test func connectReceivesDumpAndRunsSession() async throws {
        let sim = Switch2Simulator()
        sim.speed = 50
        let dev = Switch2Device(transport: sim.transport)
        try await dev.connect()

        var state = await dev.state
        for await s in dev.updates {
            state = s
            if s.initialDumpComplete, s.status != nil, s.name != nil { break }
        }
        #expect(state.name == "Switch 2")
        #expect(state.presets[2].fahrenheit == 500)
        #expect(state.presets[1].profile == .descent)
        #expect(state.status?.activePreset == 2)
        #expect(state.firmwareVersion == "G1.4.2")

        try await dev.startSession()
        for await s in dev.updates where s.status?.sessionActive == true { state = s; break }
        #expect(state.status?.sessionActive == true)
        for await s in dev.updates where (s.status?.temperature ?? 0) >= 500 { state = s; break }
        #expect(state.status?.temperature == 500)

        try await dev.stopSession()
        for await s in dev.updates where s.status?.sessionActive == false { state = s; break }
        #expect(state.status?.sessionActive == false)

        try await dev.setPresetTemperature(preset: 4, fahrenheit: 620)
        for await s in dev.updates where s.presets[4].fahrenheit == 620 { state = s; break }
        #expect(state.presets[4].celsius == 327)
        await dev.disconnect()
    }

    @Test func settingsNeedAStatusFirst() async throws {
        let dev = Switch2Device(transport: MockTransport())
        await #expect(throws: RigKitError.self) { try await dev.startSession() }
    }
}
