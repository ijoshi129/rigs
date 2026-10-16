import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button controls. Each one wakes the
/// app in the background, which reconnects to the rig and sends the command.
struct StartHeatingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.monklabs.rigsapp.start") {
            ControlWidgetButton(action: StartSessionIntent()) {
                Label("Start Heating", systemImage: "flame")
            }
        }
        .displayName("Start Heating")
        .description("Starts a session on your Switch 2.")
    }
}

struct StopHeatingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.monklabs.rigsapp.stop") {
            ControlWidgetButton(action: StopSessionIntent()) {
                Label("Stop Heating", systemImage: "stop.fill")
            }
        }
        .displayName("Stop Heating")
        .description("Stops the session on your Switch 2.")
    }
}
