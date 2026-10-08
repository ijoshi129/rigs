import Foundation

public enum PeakPro {

    public struct Profile: Equatable, Sendable, Codable, Identifiable {
        /// 0...3
        public let slot: Int
        public var name: String = ""
        public var fahrenheit: Double?
        public var seconds: Double?
        public var color: Lorax.Color?
        public var boostFahrenheit: Double?
        public var boostSeconds: Double?

        public var id: Int { slot }
        public init(slot: Int) { self.slot = slot }
    }

    public struct State: Equatable, Sendable {
        public var name: String?
        public var model: String?
        public var serial: String?
        public var firmware: String?
        public var hardwareRevision: String?

        public var operatingState: Lorax.OperatingState = .idle
        public var temperatureFahrenheit: Double?
        public var commandedFahrenheit: Double?
        public var elapsedSeconds: Double?
        public var totalSeconds: Double?

        public var batteryPercent: Int?
        public var chargeState: Lorax.ChargeState?
        public var chamberType: Lorax.ChamberType?
        public var totalDabs: Int?
        public var tripDabs: Int?
        public var dabsRemaining: Int?

        public var activeProfile: Int = 0
        public var profiles: [Profile] = (0...3).map { Profile(slot: $0) }
        public var stealthMode = false
        public var lanternOn = false
        public var lanternColor: Lorax.Color?

        public var authenticated = false
        public var connected = false

        public init() {}

        public var isHeating: Bool { operatingState.isHeating }
        public var isCharging: Bool { chargeState?.isCharging ?? false }
        public var secondsRemaining: Double? {
            guard let t = totalSeconds, let e = elapsedSeconds else { return nil }
            return max(0, t - e)
        }
        public var activeProfileSettings: Profile { profiles[min(max(activeProfile, 0), 3)] }
    }
}
