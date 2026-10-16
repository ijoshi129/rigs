import ActivityKit
import Foundation

/// The Live Activity shown while a session runs: Lock Screen and Dynamic Island.
struct RigActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable { case heating, holding, done }
        var phase: Phase
        var temperatureF: Int
        var targetF: Int
        /// When the hold ends, so the countdown ticks without updates.
        var holdEnds: Date?
        var holdSeconds: Int
    }

    var rigName: String
    var profile: String
    var unitsCelsius: Bool
}
