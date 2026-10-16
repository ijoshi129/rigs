import Foundation

/// Dr. Dabber Switch 2 wire protocol.
///
/// Packets are `[opcode, length, payload..., opcode]`, big-endian, unencrypted.
/// Everything here was read from the official web app at drdabber.app.
public enum Switch2 {

    // MARK: UUIDs

    public enum UUIDs {
        public static let controlService = UUID(uuidString: "0000FEE7-0000-1000-8000-00805F9B34FB")!
        public static let controlWrite = UUID(uuidString: "0000FEC1-0000-1000-8000-00805F9B34FB")!
        public static let controlNotify = UUID(uuidString: "0000FEC2-0000-1000-8000-00805F9B34FB")!

        public static let fallbackService = UUID(uuidString: "F56598FA-3FFA-41A7-9726-3FC69BAECA1D")!
        public static let fallbackWrite = UUID(uuidString: "2C759C29-A73C-45AB-A799-31D6A032F6AF")!
        public static let fallbackNotify = UUID(uuidString: "744C98FF-83C6-45D5-BD0C-52A50589215B")!

        /// The set the official app uses for the Switch Go; same packets.
        public static let goService = UUID(uuidString: "55535343-FE7D-4AE5-8FA9-9FAFD205E455")!
        public static let goWrite = UUID(uuidString: "49535343-8841-43F4-A8D4-ECBE34729BB3")!
        public static let goNotify = UUID(uuidString: "49535343-1E4D-4BD9-BA61-23C647249616")!

        public static let otaService = UUID(uuidString: "E5C7A653-7E52-4B06-AF32-960455084AE3")!

        public static let deviceInformation = UUID(uuidString: "0000180A-0000-1000-8000-00805F9B34FB")!
        public static let modelNumber = UUID(uuidString: "00002A24-0000-1000-8000-00805F9B34FB")!
        public static let serialNumber = UUID(uuidString: "00002A25-0000-1000-8000-00805F9B34FB")!
        public static let hardwareRevision = UUID(uuidString: "00002A27-0000-1000-8000-00805F9B34FB")!
        public static let softwareRevision = UUID(uuidString: "00002A28-0000-1000-8000-00805F9B34FB")!
        public static let manufacturer = UUID(uuidString: "00002A29-0000-1000-8000-00805F9B34FB")!
        public static let batteryService = UUID(uuidString: "0000180F-0000-1000-8000-00805F9B34FB")!
        public static let batteryLevel = UUID(uuidString: "00002A19-0000-1000-8000-00805F9B34FB")!

        /// Services to discover on connect. The OTA service is deliberately absent.
        public static let optionalServices = [deviceInformation, batteryService, controlService, fallbackService, goService]
    }

    /// The write/notify pair in use. `control` is the normal one.
    public struct Characteristics: Sendable, Equatable {
        public let write: UUID
        public let notify: UUID
        public static let control = Characteristics(write: UUIDs.controlWrite, notify: UUIDs.controlNotify)
        public static let fallback = Characteristics(write: UUIDs.fallbackWrite, notify: UUIDs.fallbackNotify)
        public static let go = Characteristics(write: UUIDs.goWrite, notify: UUIDs.goNotify)
        /// Every write/notify pair the official app knows, in the order it prefers them.
        public static let all: [Characteristics] = [control, fallback, go]
    }

    // MARK: Enumerations

    public enum HeatingProfile: UInt8, CaseIterable, Sendable, Codable {
        case steady = 161
        case ascent = 177
        case descent = 193
        case valley = 209
        case hill = 225
        case custom = 241

        public var name: String {
            switch self {
            case .steady: "Steady"
            case .ascent: "Ascent"
            case .descent: "Descent"
            case .valley: "Valley"
            case .hill: "Hill"
            case .custom: "Custom"
            }
        }

        public var summary: String {
            switch self {
            case .steady: "Holds the set temperature regardless of load or inhale."
            case .ascent: "Rises through the hold, like torching while you inhale."
            case .descent: "Cools over the hold, like a banger's natural decay."
            case .valley: "Dips to preserve terpenes, then rises to finish."
            case .hill: "Climbs for vapor, then eases down for a smooth finish."
            case .custom: "Your own curve of up to six points."
            }
        }
    }

    public struct LightMode: Hashable, Sendable, Codable, Identifiable {
        public let code: UInt8
        public let name: String
        public var id: UInt8 { code }

        public static let all: [LightMode] = [
            (0, "Stealth"), (1, "Calm"), (2, "Purple"), (3, "Blue"), (4, "Cyan"),
            (5, "Green"), (6, "Yellow"), (7, "Orange"), (8, "Red"), (9, "Pink"),
            (10, "Cali Sunset"), (11, "Purple Haze"), (12, "Northern Lights"),
            (13, "Vegas Nights"), (14, "Blue Dream"), (15, "Strawberry Cough"),
            (16, "Florida Groves"), (17, "Lime Light"),
            (24, "Blue Cheese"), (25, "Golden Goat"), (26, "Grape Ape"), (27, "Miami Vice"),
            (28, "Purple Urkle"), (29, "Candy Corn"), (30, "Redrum"), (31, "Skull & Bones"),
            (32, "Witches Brew"), (33, "Jack-O-Lantern"),
        ].map { LightMode(code: $0.0, name: $0.1) }

        public static func named(_ code: UInt8) -> LightMode {
            all.first { $0.code == code } ?? LightMode(code: code, name: "Mode \(code)")
        }
    }

    public enum TemperatureUnit: UInt8, Sendable, Codable {
        case fahrenheit = 15
        case celsius = 12
    }

    /// 170 (`0xAA`) means on for session, haptic, charging, and cleaning flags.
    public static let flagOn: UInt8 = 170

    public enum Limits {
        public static let fahrenheit = 250...650
        public static let celsius = 121...343
        public static let holdSeconds = 10...90
        public static let autoShutOffMinutes = 0...60
        public static let sessionExtend = 0...9
        public static let brightness = 0...100
        public static let nameLength = 1...29
        public static let userPresets = 1...5
        public static let curvePoints = 6
        /// Minimum gap between any two writes.
        public static let writeGap: Duration = .milliseconds(100)
        /// Gap between consecutive preset writes.
        public static let presetGap: Duration = .milliseconds(250)
    }

    // MARK: Models

    public struct CurvePoint: Equatable, Sendable, Codable {
        public var seconds: Int
        public var fahrenheit: Int
        public var celsius: Int

        public init(seconds: Int, fahrenheit: Int, celsius: Int? = nil) {
            self.seconds = seconds
            self.fahrenheit = fahrenheit
            self.celsius = celsius ?? Temperature.fahrenheitToCelsius(fahrenheit)
        }

        public var isEmpty: Bool { fahrenheit == 0 && celsius == 0 }
    }

    /// The whole settings block. Opcode 185 always rewrites every field, so
    /// build this from the last `Status` before changing one value.
    public struct Settings: Equatable, Sendable, Codable {
        public var activePreset: Int = 1
        public var lightMode: UInt8 = 1
        public var autoShutOffMinutes: Int = 0
        public var unit: TemperatureUnit = .fahrenheit
        public var sessionActive: Bool = false
        public var hapticFeedback: Bool = false
        public var sessionExtend: Int = 0
        public var brightness: Int = 100

        public init() {}

        public init(status s: Status) {
            activePreset = (1...5).contains(s.activePreset) ? s.activePreset : 1
            lightMode = s.lightMode <= 33 ? s.lightMode : 1
            autoShutOffMinutes = s.autoShutOffMinutes
            unit = s.unit
            sessionActive = s.sessionActive
            hapticFeedback = s.hapticFeedback
            sessionExtend = s.sessionExtend
            brightness = Limits.brightness.contains(s.brightness) ? s.brightness : 100
        }
    }

    /// Opcode 169: the live status packet.
    public struct Status: Equatable, Sendable, Codable {
        public var activePreset: Int
        public var lightMode: UInt8
        public var sessionActive: Bool
        public var autoShutOffMinutes: Int
        public var autoShutOffRemainingMinutes: Int
        /// Live chamber temperature in `unit`.
        public var temperature: Int
        public var unit: TemperatureUnit
        public var sessionSecondsRemaining: Int
        public var hapticFeedback: Bool
        public var sessionExtend: Int
        public var batteryPercent: Int
        public var charging: Bool
        public var brightness: Int

        public var temperatureFahrenheit: Int {
            unit == .fahrenheit ? temperature : Temperature.celsiusToFahrenheit(temperature)
        }
        public var temperatureCelsius: Int {
            unit == .celsius ? temperature : Temperature.fahrenheitToCelsius(temperature)
        }
    }

    public struct Analytics: Equatable, Sendable, Codable {
        public var favoriteTempF: Int?
        public var favoriteTempC: Int?
        public var totalHeatingCycles: Int?
        public var mostCyclesInADay: Int?
        public var totalChargeCycles: Int?
        public var favoriteHeatingProfile: HeatingProfile?
        public var favoriteLightMode: UInt8?
        public var totalTime: Int?
        public var totalOperationTime: Int?
        public var totalDeviceResets: Int?
        public var favoriteHoldTime: Int?
        public var presetCycles: [Int]?   // presets 1...5

        public init() {}

        mutating func merge(_ o: Analytics) {
            favoriteTempF = o.favoriteTempF ?? favoriteTempF
            favoriteTempC = o.favoriteTempC ?? favoriteTempC
            totalHeatingCycles = o.totalHeatingCycles ?? totalHeatingCycles
            mostCyclesInADay = o.mostCyclesInADay ?? mostCyclesInADay
            totalChargeCycles = o.totalChargeCycles ?? totalChargeCycles
            favoriteHeatingProfile = o.favoriteHeatingProfile ?? favoriteHeatingProfile
            favoriteLightMode = o.favoriteLightMode ?? favoriteLightMode
            totalTime = o.totalTime ?? totalTime
            totalOperationTime = o.totalOperationTime ?? totalOperationTime
            totalDeviceResets = o.totalDeviceResets ?? totalDeviceResets
            favoriteHoldTime = o.favoriteHoldTime ?? favoriteHoldTime
            presetCycles = o.presetCycles ?? presetCycles
        }
    }

    public struct HardwareStatus: Equatable, Sendable, Codable {
        public var activeChamber: UInt8
        public var chamberStatus: UInt8
        public var pcbStatus: UInt8
        public var batteryStatus: UInt8
    }

    // MARK: Commands (app → device)

    public enum Command {
        static func packet(_ opcode: UInt8, _ payload: [UInt8]) -> Data {
            Data([opcode, UInt8(payload.count + 3)] + payload + [opcode])
        }

        static func hi(_ v: Int) -> UInt8 { UInt8((v >> 8) & 0xFF) }
        static func lo(_ v: Int) -> UInt8 { UInt8(v & 0xFF) }

        static func checkPreset(_ p: Int, allowZero: Bool = false) throws {
            let range = allowZero ? 0...5 : Limits.userPresets
            guard range.contains(p) else { throw RigKitError.invalidValue("preset \(p)") }
        }

        /// Opcode 177. Sent once after subscribing; the device answers with its full state.
        public static func syncClock(_ date: Date = Date()) -> Data {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let y = c.year ?? 2000
            return packet(177, [hi(y), lo(y), UInt8(c.month ?? 1), UInt8(c.day ?? 1), UInt8(c.hour ?? 0), UInt8(c.minute ?? 0)])
        }

        /// Opcode 178. The device replies with opcode 162 packets.
        public static func requestAnalytics() -> Data { packet(178, [255]) }

        /// Opcode 179. Preset 0 is accepted as well as 1...5.
        public static func setPresetTemperature(preset: Int, fahrenheit: Int) throws -> Data {
            try checkPreset(preset, allowZero: true)
            guard Limits.fahrenheit.contains(fahrenheit) else { throw RigKitError.invalidValue("temperature \(fahrenheit)°F") }
            let c = Temperature.fahrenheitToCelsius(fahrenheit)
            return packet(179, [UInt8(preset), hi(fahrenheit), lo(fahrenheit), hi(c), lo(c)])
        }

        /// Opcode 181.
        public static func setHeatingProfile(preset: Int, _ profile: HeatingProfile) throws -> Data {
            try checkPreset(preset)
            return packet(181, [UInt8(preset), profile.rawValue])
        }

        /// Opcode 183.
        public static func setHoldTime(preset: Int, seconds: Int) throws -> Data {
            try checkPreset(preset)
            guard Limits.holdSeconds.contains(seconds) else { throw RigKitError.invalidValue("hold \(seconds)s") }
            return packet(183, [UInt8(preset), hi(seconds), lo(seconds)])
        }

        /// Opcodes 186 and 187. Send `setHeatingProfile(.custom)` first, then
        /// these two with 250 ms between every packet.
        public static func setCustomCurve(preset: Int, points: [CurvePoint]) throws -> (first: Data, second: Data) {
            try checkPreset(preset)
            guard points.count <= Limits.curvePoints else { throw RigKitError.invalidValue("too many curve points") }
            let sorted = points.filter { !$0.isEmpty }.sorted { $0.seconds < $1.seconds }
            func bytes(_ i: Int) -> [UInt8] {
                guard i < sorted.count else { return [0, 0, 0, 0, 0] }
                let p = sorted[i]
                return [hi(p.fahrenheit), lo(p.fahrenheit), hi(p.celsius), lo(p.celsius), UInt8(clamping: p.seconds)]
            }
            let first = packet(186, [UInt8(preset)] + bytes(0) + bytes(1) + bytes(2))
            let second = packet(187, [UInt8(preset)] + bytes(3) + bytes(4) + bytes(5))
            return (first, second)
        }

        /// Opcode 198. Heats the insert to 100 °F for 30 s to ease cleaning.
        public static func cleaningAssist(_ on: Bool) -> Data { packet(198, [on ? flagOn : 0]) }

        /// Opcodes 209 and 210. Send the second 100 ms after the first.
        public static func setDeviceName(_ name: String) throws -> (first: Data, second: Data) {
            let ascii = Array(name.utf8)
            guard Limits.nameLength.contains(ascii.count), ascii.allSatisfy({ (0x20...0x7E).contains($0) }) else {
                throw RigKitError.invalidValue("name must be 1 to 29 printable ASCII characters")
            }
            func at(_ i: Int) -> UInt8 { i < ascii.count ? ascii[i] : 0 }
            let first = packet(209, (0..<17).map(at))
            let second = packet(210, (17..<29).map(at))
            return (first, second)
        }

        /// Opcode 185. Rewrites every setting at once.
        public static func settings(_ s: Settings) throws -> Data {
            guard Limits.userPresets.contains(s.activePreset) else { throw RigKitError.invalidValue("preset \(s.activePreset)") }
            guard s.lightMode <= 33 else { throw RigKitError.invalidValue("light mode \(s.lightMode)") }
            guard Limits.autoShutOffMinutes.contains(s.autoShutOffMinutes) else { throw RigKitError.invalidValue("auto shut-off \(s.autoShutOffMinutes)") }
            guard Limits.sessionExtend.contains(s.sessionExtend) else { throw RigKitError.invalidValue("extend \(s.sessionExtend)") }
            guard Limits.brightness.contains(s.brightness) else { throw RigKitError.invalidValue("brightness \(s.brightness)") }
            return packet(185, [
                0, UInt8(s.activePreset), 0, 0, s.lightMode, 0,
                UInt8(s.autoShutOffMinutes), s.unit.rawValue,
                s.sessionActive ? flagOn : 0, s.hapticFeedback ? flagOn : 0,
                UInt8(s.sessionExtend), UInt8(s.brightness),
                0, 0, 0, 0, 0,
            ])
        }

        /// Opcode 184. Not public: destructive and never exposed in the UI.
        static func factoryReset() -> Data { packet(184, [255]) }
    }

    // MARK: Messages (device → app)

    public enum Message: Equatable, Sendable {
        case clock(year: Int, month: Int, day: Int, hour: Int, minute: Int)
        case analytics(Analytics)
        case presetTemperature(preset: Int, fahrenheit: Int, celsius: Int)
        case presetProfile(preset: Int, profile: HeatingProfile?)
        case presetHoldTime(preset: Int, seconds: Int)
        case activePreset(Int)
        case status(Status)
        /// `startIndex` 0 for points 1–3, 3 for points 4–6, 6 for opcode 172.
        case customCurve(preset: Int, startIndex: Int, points: [CurvePoint])
        case nameChunk(final: Bool, Data)
        case firmwareVersion(String)
        case secondaryVersion(String)
        case hardware(HardwareStatus)
        case maintenance(cleaningActive: Bool, factoryResetStatus: UInt8)
        case unknown(opcode: UInt8, Data)

        /// Every packet is framed as `[op, length, …, op]`, with `length` the
        /// whole packet's size (true of every packet seen from a real rig).
        /// Anything else is a truncated or corrupt notification and is dropped,
        /// so it can't overwrite good state with zeros.
        public static func parse(_ d: Data) -> Message? {
            guard d.count >= 3, Int(d.byte(1)) == d.count, d.byte(0) == d.byte(d.count - 1) else { return nil }
            let op = d.byte(0)
            switch op {
            case 161:
                return .clock(year: d.be16(2), month: Int(d.byte(4)), day: Int(d.byte(5)), hour: Int(d.byte(6)), minute: Int(d.byte(7)))
            case 162:
                return .analytics(parseAnalytics(d))
            case 163:
                return .presetTemperature(preset: Int(d.byte(2)), fahrenheit: d.be16(3), celsius: d.be16(5))
            case 165:
                return .presetProfile(preset: Int(d.byte(2)), profile: HeatingProfile(rawValue: d.byte(3)))
            case 167:
                return .presetHoldTime(preset: Int(d.byte(2)), seconds: d.be16(3))
            case 168:
                return .activePreset(Int(d.byte(2)))
            case 169:
                guard d.count >= 19 else { return nil }
                return .status(Status(
                    activePreset: Int(d.byte(3)),
                    lightMode: d.byte(6),
                    sessionActive: d.byte(7) == flagOn,
                    autoShutOffMinutes: Int(d.byte(8)),
                    autoShutOffRemainingMinutes: Int(d.byte(9)),
                    temperature: d.be16(10),
                    unit: TemperatureUnit(rawValue: d.byte(12)) ?? .fahrenheit,
                    sessionSecondsRemaining: Int(d.byte(13)),
                    hapticFeedback: d.byte(14) == flagOn,
                    sessionExtend: Int(d.byte(15)),
                    batteryPercent: Int(d.byte(16)),
                    charging: d.byte(17) == flagOn,
                    brightness: Int(d.byte(18))
                ))
            case 170, 171, 172:
                let start = op == 170 ? 0 : op == 171 ? 3 : 6
                var pts: [CurvePoint] = []
                for i in 0..<3 {
                    let b = 3 + i * 5
                    pts.append(CurvePoint(seconds: Int(d.byte(b + 4)), fahrenheit: d.be16(b), celsius: d.be16(b + 2)))
                }
                return .customCurve(preset: Int(d.byte(2)), startIndex: start, points: pts)
            case 193, 194:
                let body = d.count > 3 ? d.subdata(in: (d.startIndex + 2)..<(d.endIndex - 1)) : Data()
                return .nameChunk(final: op == 194, body)
            case 195:
                let len = d.byte(2) == 71 ? 9 : 8
                return .firmwareVersion(d.dropFirst(2).prefix(len).cleanString)
            case 196:
                return .secondaryVersion(d.dropFirst(2).prefix(8).cleanString)
            case 225:
                return .hardware(HardwareStatus(activeChamber: d.byte(2), chamberStatus: d.byte(3), pcbStatus: d.byte(4), batteryStatus: d.byte(5)))
            case 241:
                return .maintenance(cleaningActive: d.byte(2) == flagOn, factoryResetStatus: d.byte(3))
            default:
                return .unknown(opcode: op, d)
            }
        }

        static func parseAnalytics(_ d: Data) -> Analytics {
            var a = Analytics()
            switch d.byte(1) {
            case 20:
                a.favoriteTempF = d.be16(2); a.favoriteTempC = d.be16(4)
                a.totalHeatingCycles = d.be16(6); a.mostCyclesInADay = d.be16(8)
                a.totalChargeCycles = d.be16(10)
                a.favoriteHeatingProfile = HeatingProfile(rawValue: d.byte(12)); a.favoriteLightMode = d.byte(13)
                a.totalTime = d.be16(14); a.totalDeviceResets = d.be16(16)
            case 17, 19:
                a.favoriteTempF = d.be16(2); a.favoriteTempC = d.be16(4)
                a.totalHeatingCycles = d.be16(6); a.mostCyclesInADay = d.be16(8)
                a.totalChargeCycles = d.be16(10)
                a.favoriteHeatingProfile = HeatingProfile(rawValue: d.byte(12)); a.favoriteLightMode = d.byte(13)
                a.totalDeviceResets = d.be16(14)
                if d.byte(1) == 19 { a.favoriteHoldTime = d.be16(16) }
            case 7:
                a.totalTime = d.be32(2)
            case 11:
                a.totalTime = d.be32(2); a.totalOperationTime = d.be32(6)
            case 13:
                a.presetCycles = (0..<5).map { d.be16(2 + $0 * 2) }
            default:
                break
            }
            return a
        }
    }
}
