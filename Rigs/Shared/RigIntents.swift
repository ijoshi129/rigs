import AppIntents
import Foundation

/// The actions that can run without the app on screen: from Siri, Shortcuts,
/// the Action button, Control Center, and the Live Activity.
///
/// This file is built into the app and the widget extension, because controls
/// and Live Activity buttons need the intent types. They are Live Activity
/// intents, so the system always runs `perform` in the app's process, where
/// the Bluetooth link lives. The app installs `RigIntentBridge.handler` at launch.

enum RigCommand: Sendable {
    case start(preset: Int?)
    case stop
    case preset(Int)
    case status
}

@MainActor
enum RigIntentBridge {
    static var handler: ((RigCommand) async throws -> String)?

    static func run(_ command: RigCommand) async throws -> String {
        guard let handler else { throw RigIntentError("Open Rigs once, then try again.") }
        return try await handler(command)
    }
}

struct RigIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

/// The five preset buttons on the rig.
enum PresetSlot: Int, AppEnum {
    case one = 1, two, three, four, five

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Preset"
    static let caseDisplayRepresentations: [PresetSlot: DisplayRepresentation] = [
        .one: "Preset 1", .two: "Preset 2", .three: "Preset 3", .four: "Preset 4", .five: "Preset 5",
    ]
}

struct StartSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Heating"
    static let description = IntentDescription("Starts a session on your Switch 2, optionally switching preset first.")

    @Parameter(title: "Preset", description: "Leave empty to use the rig's current preset.")
    var preset: PresetSlot?

    static var parameterSummary: some ParameterSummary {
        Summary("Start heating at \(\.$preset)")
    }

    init() {}
    init(preset: PresetSlot?) { self.preset = preset }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try await RigIntentBridge.run(.start(preset: preset?.rawValue))
        return .result(dialog: "\(reply)")
    }
}

struct StopSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Heating"
    static let description = IntentDescription("Stops the session running on your Switch 2.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try await RigIntentBridge.run(.stop)
        return .result(dialog: "\(reply)")
    }
}
