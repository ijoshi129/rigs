import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Switch2Controller.self) private var rig
    @AppStorage(Prefs.units) private var units: Units = .f
    @AppStorage(Prefs.heatColorsNumber) private var heatColors = true
    @State private var confirmForget = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Settings", showsBack: true)

                SectionLabel("Display")
                Surface {
                    Row(title: "Heat colors the number", detail: "White when cold, amber when hot") {
                        SquareToggle(isOn: $heatColors, label: "Heat colors the number")
                    }
                    Row(title: "Units", last: true) {
                        SquareSegmented(options: Units.allCases, selection: units, label: { "°\($0.rawValue)" }) { units = $0 }
                            .frame(width: 120)
                    }
                }

                SectionLabel("Rig")
                Surface {
                    HStack(spacing: 16) {
                        Image("Switch2").resizable().scaledToFit().frame(height: 96)
                            .saturation(rig.connected ? 1 : 0).opacity(rig.connected ? 1 : 0.6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rig.name).font(.geist(20, .light))
                            Text(rig.connected ? "Connected" : model.isReconnecting ? "Reconnecting…" : "Disconnected")
                                .font(.geist(13)).foregroundStyle(rig.connected ? Theme.accent : Theme.ink2)
                        }
                        Spacer()
                        SmallButton(title: "Forget") { confirmForget = true }
                    }
                    .padding(.vertical, 16)
                }
                Text(model.isMock
                     ? "The rig is simulated right now."
                     : "Rigs remembers the rig and reconnects on its own whenever it's on and nearby.")
                    .font(.geist(12)).foregroundStyle(Theme.ink3).padding(.top, 12).padding(.horizontal, 4)

                Text("Rigs \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · Nothing leaves your phone. No account, no cloud.")
                    .font(.geist(12)).foregroundStyle(Theme.ink3).padding(.top, 24).padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Forget this rig?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) { Task { await model.forget() } }
        } message: {
            Text("Rigs stops reconnecting to it. You can connect again from the start screen.")
        }
    }
}
