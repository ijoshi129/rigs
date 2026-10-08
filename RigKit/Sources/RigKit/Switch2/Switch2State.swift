import Foundation

extension Switch2 {

    public struct Preset: Equatable, Sendable, Codable, Identifiable {
        /// 0...5 as the device numbers them. 1...5 are the buttons; 0 is the live slot.
        public let index: Int
        public var fahrenheit: Int?
        public var celsius: Int?
        public var holdSeconds: Int?
        public var profile: HeatingProfile?
        public var curve: [CurvePoint] = Array(repeating: CurvePoint(seconds: 0, fahrenheit: 0, celsius: 0), count: 6)

        public var id: Int { index }

        public var curvePoints: [CurvePoint] { curve.filter { !$0.isEmpty } }
    }

    /// Everything known about one Switch 2, built up from its packets.
    public struct State: Equatable, Sendable {
        public var status: Status?
        public var presets: [Preset] = (0...5).map { Preset(index: $0) }
        public var activePreset: Int?
        public var analytics = Analytics()
        public var firmwareVersion: String?
        public var secondaryVersion: String?
        public var name: String?
        public var hardware: HardwareStatus?
        public var cleaningActive = false
        public var factoryResetStatus: UInt8 = 0
        public var deviceClock: DateComponents?
        public var packetsReceived = 0

        var nameBuffer = Data()

        public init() {}

        /// The official app treats the post-clock-sync dump as done after 13 packets.
        public var initialDumpComplete: Bool { packetsReceived >= 13 }

        public var activePresetSettings: Preset? {
            guard let i = activePreset ?? status?.activePreset, presets.indices.contains(i) else { return nil }
            return presets[i]
        }

        public mutating func apply(_ m: Message) {
            packetsReceived += 1
            switch m {
            case let .clock(y, mo, d, h, mi):
                deviceClock = DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)
            case let .analytics(a):
                analytics.merge(a)
            case let .presetTemperature(p, f, c):
                guard presets.indices.contains(p) else { return }
                presets[p].fahrenheit = f
                presets[p].celsius = c
            case let .presetProfile(p, prof):
                guard presets.indices.contains(p) else { return }
                presets[p].profile = prof
            case let .presetHoldTime(p, s):
                guard presets.indices.contains(p) else { return }
                presets[p].holdSeconds = s
            case let .activePreset(p):
                activePreset = p
            case let .status(s):
                status = s
                activePreset = s.activePreset
            case let .customCurve(p, start, pts):
                guard presets.indices.contains(p) else { return }
                for (i, pt) in pts.enumerated() where start + i < 6 {
                    presets[p].curve[start + i] = pt
                }
            case let .nameChunk(final, chunk):
                if final {
                    nameBuffer.append(chunk)
                    name = nameBuffer.cleanString
                    nameBuffer = Data()
                } else {
                    nameBuffer = chunk
                }
            case let .firmwareVersion(v):
                firmwareVersion = v
            case let .secondaryVersion(v):
                secondaryVersion = v
            case let .hardware(h):
                hardware = h
            case let .maintenance(cleaning, reset):
                cleaningActive = cleaning
                factoryResetStatus = reset
            case .unknown:
                break
            }
        }
    }
}
