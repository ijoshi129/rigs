import AppIntents

/// App-only intents: these never run from a widget, so they live here.
struct SelectPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Preset"
    static let description = IntentDescription("Switches your Switch 2 to one of its five presets.")

    @Parameter(title: "Preset")
    var preset: PresetSlot

    static var parameterSummary: some ParameterSummary {
        Summary("Switch to \(\.$preset)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try await RigIntentBridge.run(.preset(preset.rawValue))
        return .result(dialog: "\(reply)")
    }
}

struct RigStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Rig Status"
    static let description = IntentDescription("Reads the temperature, preset and battery from your Switch 2.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let reply = try await RigIntentBridge.run(.status)
        return .result(value: reply, dialog: "\(reply)")
    }
}

/// Phrases Siri and Spotlight know without any setup.
struct RigShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSessionIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Heat up \(.applicationName)",
                "Start \(.applicationName) at \(\.$preset)",
            ],
            shortTitle: "Start Heating",
            systemImageName: "flame"
        )
        AppShortcut(
            intent: StopSessionIntent(),
            phrases: ["Stop \(.applicationName)", "Stop heating in \(.applicationName)"],
            shortTitle: "Stop Heating",
            systemImageName: "stop"
        )
        AppShortcut(
            intent: SelectPresetIntent(),
            phrases: ["Set \(.applicationName) to \(\.$preset)", "Switch \(.applicationName) to \(\.$preset)"],
            shortTitle: "Set Preset",
            systemImageName: "slider.horizontal.3"
        )
        AppShortcut(
            intent: RigStatusIntent(),
            phrases: ["How hot is \(.applicationName)", "Check \(.applicationName)", "\(.applicationName) status"],
            shortTitle: "Rig Status",
            systemImageName: "thermometer.medium"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}
