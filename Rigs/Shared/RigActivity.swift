import ActivityKit
import Foundation

/// The Live Activity shown while a session runs: Lock Screen and Dynamic Island.
struct RigActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// `lost`: the Bluetooth link dropped mid-session; the app is reconnecting.
        enum Phase: String, Codable, Hashable { case heating, holding, done, lost }
        var phase: Phase
        var temperatureF: Int
        var targetF: Int
        /// When the hold ends, so the countdown ticks without updates.
        var holdEnds: Date?
        var holdSeconds: Int
        /// Temperature when the session started, for the heat-up progress.
        var startF: Int?
    }

    var rigName: String
    var profile: String
    var unitsCelsius: Bool
}
