import CryptoKit
import Foundation

/// Puffco's Lorax protocol: a virtual file system over two characteristics,
/// unlocked by a SHA-256 challenge-response. Firmware AG and later.
public enum Lorax {

    // MARK: UUIDs

    public enum UUIDs {
        public static let service = UUID(uuidString: "E276967F-EA8A-478A-A92E-D78F5DD15DD5")!
        public static let command = UUID(uuidString: "60133D5C-5727-4F2C-9697-D842C5292A3C")!
        public static let reply = UUID(uuidString: "8DC5EC05-8F7D-45AD-99DB-3FBDE65DBD9C")!
        public static let event = UUID(uuidString: "43312CD1-7D34-46CE-A7D3-0A98FD9B4CB8")!
        public static let version = UUID(uuidString: "05434BCA-CC7F-4EF6-BBB3-B1C520B9800C")!

        /// Advertised on every firmware; usable as the scan filter.
        public static let legacyService = UUID(uuidString: "06CAF9C0-74D3-454F-9BE9-E30CD999C17A")!

        /// Reading this characteristic needs an encrypted link, which makes the OS pair.
        public static let pupService = UUID(uuidString: "420B9B40-457D-4ABE-A3BF-71609D79581B")!
        public static let pupAppVersion = UUID(uuidString: "58B0A7AA-D89F-4BF2-961D-0D892D7439D8")!

        public static let deviceInformation = UUID(uuidString: "0000180A-0000-1000-8000-00805F9B34FB")!

        public static let optionalServices = [deviceInformation, service, legacyService, pupService]
    }

    // MARK: Opcodes

    public enum Opcode: UInt8, Sendable {
        case getAccessSeed = 0
        case unlockAccess = 1
        case getLimits = 2
        case ackEvents = 3
        case readShort = 16
        case writeShort = 17
        case statShort = 18
        case unlink = 19
        case open = 32
        case read = 33
        case write = 34
        case watch = 35
        case unwatch = 36
        case stat = 37
        case close = 38
    }

    // MARK: Framing

    /// `[seq_lo, seq_hi, opcode, payload...]`
    public static func packCommand(seq: UInt16, opcode: Opcode, payload: Data = Data()) -> Data {
        Data.le(seq) + Data([opcode.rawValue]) + payload
    }

    public struct Reply: Equatable, Sendable {
        public let seq: UInt16
        public let status: UInt8
        public let payload: Data
        public var ok: Bool { status == 0 }
    }

    /// `[seq_lo, seq_hi, status, payload...]`
    public static func unpackReply(_ d: Data) throws -> Reply {
        guard d.count >= 3, let seq = d.prefix(2).leUInt16 else { throw RigKitError.malformedPacket }
        return Reply(seq: seq, status: d.byte(2), payload: Data(d.dropFirst(3)))
    }

    /// Payload for READ_SHORT: `uint16 offset, uint16 max_len, path`.
    public static func readShortPayload(path: String, maxLength: UInt16 = 240) -> Data {
        Data.le(UInt16(0)) + Data.le(maxLength) + Data(path.utf8)
    }

    /// Payload for WRITE_SHORT: `uint16 offset, uint8 flags, path, 0x00, value`.
    public static func writeShortPayload(path: String, value: Data) -> Data {
        Data.le(UInt16(0)) + Data([0]) + Data(path.utf8) + Data([0]) + value
    }

    // MARK: Authentication

    /// Base64 `ZMZFYlbyb1scoSc3pd1x+w==`.
    public static let masterKey = Data([
        0x64, 0xC6, 0x45, 0x62, 0x56, 0xF2, 0x6F, 0x5B,
        0x1C, 0xA1, 0x27, 0x37, 0xA5, 0xDD, 0x71, 0xFB,
    ])

    /// `SHA256(masterKey ‖ seed[0..<16])[0..<16]`
    public static func authToken(seed: Data) throws -> Data {
        guard seed.count >= 16 else { throw RigKitError.malformedPacket }
        let digest = SHA256.hash(data: masterKey + seed.prefix(16))
        return Data(digest.prefix(16))
    }

    // MARK: Paths

    public enum Path {
        public static let operatingState = "/p/app/stat/id"
        public static let elapsed = "/p/app/stat/elap"
        public static let total = "/p/app/stat/tott"
        public static let modeCommand = "/p/app/mc"
        public static let chamberTemperature = "/p/app/htr/temp"
        public static let commandedTemperature = "/p/app/htr/tcmd"
        public static let activeProfile = "/p/app/hcs"
        public static let temperatureOverride = "/p/app/tmpo"
        public static let timeOverride = "/p/app/timo"
        public static let chamberType = "/p/htr/chmt"

        public static let batteryLevel = "/p/bat/soc"
        public static let chargeState = "/p/bat/chg/stat"
        public static let chargeTimeToFull = "/p/bat/chg/etf"
        public static let totalDabs = "/p/app/odom/0/nc"
        public static let totalHeatTime = "/p/app/odom/0/tm"
        public static let tripDabs = "/p/app/odom/1/nc"
        public static let dabsPerDay = "/p/app/info/dpd"
        public static let dabsRemaining = "/p/app/info/drem"
        public static let uptime = "/p/sys/uptm"

        public static let lanternCommand = "/p/app/ltrn/cmd"
        public static let lanternColor = "/p/app/ltrn/colr"
        public static let lanternTime = "/p/app/ltrn/time"
        public static let lanternBrightness = "/u/app/ui/lbrt"
        public static let ledBrightness = "/u/app/ui/brt"
        public static let stealthMode = "/u/app/ui/stlm"

        public static let deviceName = "/u/sys/name"
        public static let birthday = "/u/sys/bday"
        public static let modelCode = "/p/sys/hw/mdcd"
        public static let serialNumber = "/p/sys/hw/ser"
        public static let hardwareRevision = "/p/sys/hw/ver"
        public static let firmwareRevision = "/p/sys/fw/ver"
        public static let firmwareGitHash = "/p/sys/fw/gith"

        public static func profileName(_ slot: Int) -> String { "/u/app/hc/\(slot)/name" }
        public static func profileTemperature(_ slot: Int) -> String { "/u/app/hc/\(slot)/temp" }
        public static func profileTime(_ slot: Int) -> String { "/u/app/hc/\(slot)/time" }
        public static func profileColor(_ slot: Int) -> String { "/u/app/hc/\(slot)/colr" }
        public static func profileBoostTemperature(_ slot: Int) -> String { "/u/app/hc/\(slot)/btmp" }
        public static func profileBoostTime(_ slot: Int) -> String { "/u/app/hc/\(slot)/btim" }
    }

    // MARK: Enumerations

    public enum OperatingState: UInt8, Sendable, Codable {
        case initMemory = 0, initVersion = 1, initBattery = 2
        case masterOff = 3, sleep = 4, idle = 5, temperatureSelect = 6
        case preheat = 7, active = 8, fade = 9
        case versionDisplay = 10, batteryDisplay = 11, factoryTest = 12, bonding = 13

        public var isHeating: Bool { self == .preheat || self == .active || self == .fade }

        public var name: String {
            switch self {
            case .preheat: "Preheating"
            case .active: "Ready"
            case .fade: "Cooling"
            case .idle, .initMemory, .bonding: "Idle"
            case .sleep: "Asleep"
            case .masterOff: "Off"
            case .temperatureSelect: "Selecting"
            default: "Busy"
            }
        }
    }

    /// Only start, abort, and boost are used; the rest are listed for decoding.
    public enum ModeCommand: UInt8, Sendable {
        case masterOff = 0, sleep = 1, idle = 2
        case temperatureSelectBegin = 3, temperatureSelectStop = 4
        case showBattery = 5, showVersion = 6
        case heatCycleStart = 7, heatCycleAbort = 8, heatCycleBoost = 9
        case factoryTest = 10, bonding = 11
    }

    public enum ChamberType: UInt8, Sendable, Codable {
        case none = 0, classic = 1, herbal = 2, performance = 3, xl = 4, toad = 5
        public var name: String {
            switch self {
            case .none: "No chamber"
            case .classic: "Classic"
            case .herbal: "Herbal"
            case .performance: "3D"
            case .xl: "3DXL"
            case .toad: "Proxy"
            }
        }
    }

    public enum ChargeState: UInt8, Sendable, Codable {
        case bulk = 0, topUp = 1, full = 2, overTemperature = 3, disconnected = 4
        public var isCharging: Bool { self == .bulk || self == .topUp }
        public var onDock: Bool { self != .disconnected }
    }

    public enum LanternMode: UInt8, Sendable, Codable, CaseIterable {
        case preserve = 0, `static` = 1, breathing = 5, rising = 6, circling = 7, circlingSlow = 21
    }

    public struct Color: Equatable, Sendable, Codable {
        public var red: UInt8, green: UInt8, blue: UInt8
        public var mode: LanternMode
        public init(red: UInt8, green: UInt8, blue: UInt8, mode: LanternMode = .static) {
            self.red = red; self.green = green; self.blue = blue; self.mode = mode
        }
        /// `[r, g, b, 0, mode, 0, 0, 0]`
        public var encoded: Data { Data([red, green, blue, 0, mode.rawValue, 0, 0, 0]) }
        public static func decode(_ d: Data) -> Color? {
            guard d.count >= 3 else { return nil }
            return Color(red: d.byte(0), green: d.byte(1), blue: d.byte(2), mode: LanternMode(rawValue: d.byte(4)) ?? .static)
        }
        /// Puffco's built-in animations ignore the RGB bytes.
        public static let disco = Data([255, 255, 0, 0, 1, 0, 0, 0])
        public static let pulsing = Data([255, 255, 0, 0, 5, 0, 0, 0])
        public static let rotating = Data([255, 255, 0, 0, 21, 0, 0, 0])
    }

    public static let lanternSeconds: Float = 7200

    // MARK: Codecs

    public enum Codec {
        /// Temperature in °F from a path value. Peak Pro sends float32 °C;
        /// Proxy sends int32 tenths of °C. Returns nil when implausible.
        public static func fahrenheit(_ d: Data) -> Double? {
            guard d.count >= 4 else { return nil }
            if let f = d.leFloat32, f.isFinite, (5...450).contains(f) {
                return Temperature.fahrenheit(fromCelsius: Double(f))
            }
            if let i = d.leInt32 {
                if (50...4500).contains(i) { return Temperature.fahrenheit(fromCelsius: Double(i) / 10) }
                if (5...450).contains(i) { return Temperature.fahrenheit(fromCelsius: Double(i)) }
            }
            return nil
        }

        public static func encodeCelsius(_ c: Double) -> Data { .le(Float(c)) }

        /// Percent 0–100 from 1-byte, uint32, or float32.
        public static func battery(_ d: Data) -> Int? {
            if d.count == 1 { return min(100, Int(d.byte(0))) }
            guard let u = d.leUInt32 else { return nil }
            if u <= 100 { return Int(u) }
            if u <= 10_000 { return min(100, Int((Double(u) / 100).rounded())) }
            if let f = d.leFloat32, f.isFinite, (0...100).contains(f) { return Int(f.rounded()) }
            return nil
        }

        /// A count that may be stored as uint32 or as an integral float32.
        public static func count(_ d: Data) -> Int? {
            switch d.count {
            case 1: return Int(d.byte(0))
            case 2: return d.leUInt16.map(Int.init)
            default:
                guard let u = d.leUInt32 else { return nil }
                if let f = d.leFloat32, f.isFinite, f >= 1, f < 1_000_000, f == f.rounded() { return Int(f) }
                return Int(u)
            }
        }

        /// Seconds stored as either uint32 or float32. Values above 300 are
        /// taken as milliseconds (puffco-py's rule for elapsed/total).
        public static func seconds(_ d: Data, millisecondsAbove: Double? = nil) -> Double? {
            guard let u = d.leUInt32 else { return nil }
            var v: Double
            if u <= 100_000 {
                v = Double(u)
            } else if let f = d.leFloat32, f.isFinite, f >= 0 {
                v = Double(f)
            } else {
                return nil
            }
            if let limit = millisecondsAbove, v > limit { v /= 1000 }
            return v
        }

        /// Firmware integer → letter code, alphabet of 21 letters, 1-indexed.
        public static func firmwareLetters(_ rev: Int) -> String {
            let chars = Array("ABCDEFGHJKMNPRTUVWXYZ")
            guard rev > 0 else { return "X*" }
            var i = rev - 1
            var out = ""
            while i >= 0 {
                out = String(chars[i % chars.count]) + out
                i = i / chars.count - 1
            }
            return out
        }

        public static let modelNames: [String: String] = [
            "0": "Peak Pro", "21": "Peak Pro", "51": "Peak Pro", "4294967295": "Peak Pro",
            "1": "Opal Peak Pro", "22": "Opal Peak Pro",
            "2": "Indiglow Peak Pro",
            "4": "Guardian Peak Pro", "25": "Guardian Peak Pro", "26": "Guardian Peak Pro",
            "12": "Peach White Peak Pro", "72": "Peach White Peak Pro",
            "13": "Peach Black Peak Pro", "71": "Peach Black Peak Pro",
            "15": "Peach Desert Peak Pro", "74": "Peach Desert Peak Pro",
        ]
    }
}
