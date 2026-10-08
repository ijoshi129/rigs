import Foundation

/// A fake Switch 2 behind a `MockTransport`. Answers the clock sync with a
/// full state dump, echoes preset writes, and runs a believable heating
/// cycle when a session starts. Good enough for UI work and tests.
public final class Switch2Simulator: @unchecked Sendable {
    public let transport = MockTransport()
    public let characteristics: Switch2.Characteristics

    private let lock = NSLock()
    private var presets: [Switch2.Preset]
    private var settings = Switch2.Settings()
    private var temperature = 72          // °F
    private var sessionRemaining = 0
    private var battery = 87
    private var charging = false
    private var cleaning = false
    private var name = "Switch 2"
    private var heater: Task<Void, Never>?
    public var speed: Double = 1          // >1 makes heating faster for tests

    public init(characteristics: Switch2.Characteristics = .control) {
        self.characteristics = characteristics
        presets = (0...5).map { i in
            var p = Switch2.Preset(index: i)
            p.fahrenheit = [500, 450, 500, 550, 600, 650][i]
            p.celsius = Temperature.fahrenheitToCelsius(p.fahrenheit!)
            p.holdSeconds = 30
            p.profile = .descent
            return p
        }
        settings.activePreset = 2
        settings.brightness = 60
        settings.lightMode = 10
        settings.hapticFeedback = true
        settings.autoShutOffMinutes = 15
        transport.onWrite = { [weak self] c, d in self?.receive(c, d) }
        transport.onRead = { [weak self] c in try self?.readInfo(c) ?? Data() }
    }

    // MARK: Inbound

    private func receive(_ characteristic: UUID, _ d: Data) {
        guard characteristic == characteristics.write, d.count >= 2 else { return }
        let op = d.byte(0)
        switch op {
        case 177: sendDump()
        case 178: sendAnalytics()
        case 179:
            let p = Int(d.byte(2))
            lock.withLock {
                guard presets.indices.contains(p) else { return }
                presets[p].fahrenheit = d.be16(3)
                presets[p].celsius = d.be16(5)
            }
            emit([163, 8, UInt8(p), d.byte(3), d.byte(4), d.byte(5), d.byte(6), 163])
        case 181:
            let p = Int(d.byte(2))
            lock.withLock { if presets.indices.contains(p) { presets[p].profile = Switch2.HeatingProfile(rawValue: d.byte(3)) } }
            emit([165, 5, UInt8(p), d.byte(3), 165])
        case 183:
            let p = Int(d.byte(2))
            lock.withLock { if presets.indices.contains(p) { presets[p].holdSeconds = d.be16(3) } }
            emit([167, 6, UInt8(p), d.byte(3), d.byte(4), 167])
        case 186, 187:
            let p = Int(d.byte(2))
            let start = op == 186 ? 0 : 3
            lock.withLock {
                guard presets.indices.contains(p) else { return }
                for i in 0..<3 {
                    let b = 3 + i * 5
                    presets[p].curve[start + i] = Switch2.CurvePoint(seconds: Int(d.byte(b + 4)), fahrenheit: d.be16(b), celsius: d.be16(b + 2))
                }
            }
            emit([op == 186 ? 170 : 171] + Array(d.dropFirst(1).dropLast(1)) + [op == 186 ? 170 : 171])
        case 185:
            applySettings(d)
        case 198:
            lock.withLock { cleaning = d.byte(2) == Switch2.flagOn }
            emit([241, 5, d.byte(2), 0, 241])
        case 209:
            lock.withLock { name = Data(d.dropFirst(2).dropLast(1)).cleanString }
        case 210:
            lock.withLock { name += Data(d.dropFirst(2).dropLast(1)).cleanString }
            sendName()
        default:
            break
        }
    }

    private func applySettings(_ d: Data) {
        let wasActive = lock.withLock { settings.sessionActive }
        lock.withLock {
            settings.activePreset = Int(d.byte(3))
            settings.lightMode = d.byte(6)
            settings.autoShutOffMinutes = Int(d.byte(8))
            settings.unit = Switch2.TemperatureUnit(rawValue: d.byte(9)) ?? .fahrenheit
            settings.sessionActive = d.byte(10) == Switch2.flagOn
            settings.hapticFeedback = d.byte(11) == Switch2.flagOn
            settings.sessionExtend = Int(d.byte(12))
            settings.brightness = Int(d.byte(13))
            if settings.sessionActive, settings.sessionExtend > 0 { sessionRemaining += settings.sessionExtend * 10 }
        }
        let nowActive = lock.withLock { settings.sessionActive }
        if nowActive, !wasActive { startHeating() } else if !nowActive, wasActive { stopHeating() }
        sendStatus()
    }

    private func readInfo(_ c: UUID) throws -> Data {
        switch c {
        case Switch2.UUIDs.modelNumber: Data("Switch 2".utf8)
        case Switch2.UUIDs.serialNumber: Data("SIM-000001".utf8)
        case Switch2.UUIDs.softwareRevision: Data("1.4.2".utf8)
        case Switch2.UUIDs.hardwareRevision: Data("B".utf8)
        case Switch2.UUIDs.manufacturer: Data("Dr. Dabber".utf8)
        case Switch2.UUIDs.batteryLevel: Data([UInt8(lock.withLock { battery })])
        default: throw RigKitError.unsupported("read \(c)")
        }
    }

    // MARK: Heating

    private func startHeating() {
        let preset = lock.withLock { presets[settings.activePreset] }
        lock.withLock { sessionRemaining = preset.holdSeconds ?? 30 }
        heater?.cancel()
        heater = Task { [weak self] in
            guard let self else { return }
            let target = preset.fahrenheit ?? 500
            // Preheat: ramp up, then hold while counting down.
            while !Task.isCancelled {
                let done: Bool = lock.withLock {
                    if temperature < target {
                        temperature = min(target, temperature + Int(60 * speed))
                        return false
                    }
                    sessionRemaining -= 1
                    temperature = max(target - 40, temperature - 2)
                    return sessionRemaining <= 0
                }
                sendStatus()
                if done { break }
                try? await Task.sleep(for: .milliseconds(Int(250 / speed)))
            }
            if !Task.isCancelled {
                lock.withLock { settings.sessionActive = false; sessionRemaining = 0 }
                sendStatus()
                await coolDown()
            }
        }
    }

    private func stopHeating() {
        heater?.cancel()
        lock.withLock { sessionRemaining = 0 }
        heater = Task { [weak self] in await self?.coolDown() }
    }

    private func coolDown() async {
        while !Task.isCancelled {
            let cool: Bool = lock.withLock {
                temperature = max(72, temperature - Int(15 * speed))
                return temperature <= 72
            }
            sendStatus()
            if cool { break }
            try? await Task.sleep(for: .milliseconds(Int(500 / speed)))
        }
    }

    // MARK: Outbound

    private func emit(_ bytes: [UInt8]) {
        transport.emit(Data(bytes), on: characteristics.notify)
    }

    private func sendStatus() {
        let (s, t, rem, bat, chg) = lock.withLock { (settings, temperature, sessionRemaining, battery, charging) }
        let temp = s.unit == .fahrenheit ? t : Temperature.fahrenheitToCelsius(t)
        emit([169, 20, 0, UInt8(s.activePreset), 0, 0, s.lightMode,
              s.sessionActive ? Switch2.flagOn : 0,
              UInt8(s.autoShutOffMinutes), UInt8(s.autoShutOffMinutes),
              UInt8(temp >> 8), UInt8(temp & 0xFF), s.unit.rawValue,
              UInt8(clamping: rem), s.hapticFeedback ? Switch2.flagOn : 0,
              UInt8(s.sessionExtend), UInt8(bat), chg ? Switch2.flagOn : 0, UInt8(s.brightness), 169])
    }

    private func sendName() {
        let bytes = Array(lock.withLock { name }.utf8)
        let first = Array(bytes.prefix(17)), rest = Array(bytes.dropFirst(17))
        emit([193, UInt8(first.count + 3)] + first + [193])
        emit([194, UInt8(rest.count + 3)] + rest + [194])
    }

    private func sendDump() {
        let now = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: Date())
        let y = now.year ?? 2026
        emit([161, 9, UInt8(y >> 8), UInt8(y & 0xFF), UInt8(now.month ?? 1), UInt8(now.day ?? 1), UInt8(now.hour ?? 0), UInt8(now.minute ?? 0), 161])
        let ps = lock.withLock { presets }
        for p in ps {
            let f = p.fahrenheit ?? 0, c = p.celsius ?? 0, h = p.holdSeconds ?? 30
            emit([163, 8, UInt8(p.index), UInt8(f >> 8), UInt8(f & 0xFF), UInt8(c >> 8), UInt8(c & 0xFF), 163])
            emit([165, 5, UInt8(p.index), p.profile?.rawValue ?? 193, 165])
            emit([167, 6, UInt8(p.index), UInt8(h >> 8), UInt8(h & 0xFF), 167])
        }
        emit([168, 4, UInt8(lock.withLock { settings.activePreset }), 168])
        emit([195, 11] + Array("G1.4.2   ".utf8) + [195])
        emit([196, 11] + Array("B2.0.1  ".utf8) + [196])
        emit([225, 7, 1, 0, 0, 0, 225])
        emit([241, 5, 0, 0, 241])
        sendName()
        sendStatus()
    }

    private func sendAnalytics() {
        let fav = 500, favC = 260
        emit([162, 20, UInt8(fav >> 8), UInt8(fav & 0xFF), UInt8(favC >> 8), UInt8(favC & 0xFF),
              0x01, 0x2C, 0, 9, 0, 48, 193, 10, 0x10, 0x00, 0, 2, 162])
        emit([162, 11, 0, 0x02, 0x9A, 0x6C, 0, 0x0F, 0x42, 0x40, 162])
        emit([162, 13, 0, 20, 0, 180, 0, 60, 0, 30, 0, 10, 162])
    }
}
