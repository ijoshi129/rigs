import RigKit
import SwiftUI

struct Switch2DeckView: View {
    @Bindable var rig: Switch2Controller
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 16) {
                HeroTemperature(fahrenheit: rig.temperatureF, label: stateLabel)
                Spacer(minLength: 0)
            }

            HeatCurveView(samples: rig.history, target: rig.targetF, maximum: 700)

            SessionButton(
                heating: rig.isHeating,
                idleTitle: rig.targetF.map { "Heat to \(Int($0))°" } ?? "Heat",
                secondsRemaining: rig.status?.sessionSecondsRemaining,
                action: { rig.isHeating ? rig.stopSession() : rig.startSession() }
            )
            .disabled(rig.status == nil || !rig.connected)

            presets

            if let err = rig.lastError {
                Text(err).font(Theme.caption).foregroundStyle(.red)
            }
        }
        .deck()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(rig.state.name ?? rig.name).font(Theme.title).foregroundStyle(Theme.text)
            if !rig.connected {
                Text("Disconnected").font(Theme.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            BatteryBadge(percent: rig.status?.batteryPercent, charging: rig.status?.charging ?? false)
            Menu {
                Button("Disconnect", role: .destructive) { Task { await model.disconnect(.switch2) } }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(Theme.dim)
            }
        }
    }

    private var stateLabel: String {
        guard let s = rig.status else { return "Waiting for the rig" }
        if s.sessionActive {
            if let t = rig.targetF, Double(s.temperatureFahrenheit) < t - 5 { return "Heating" }
            return "Holding · \(rig.activePreset?.profile?.name ?? "")"
        }
        if !rig.state.initialDumpComplete { return "Syncing" }
        return "Idle"
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(rig.userPresets) { p in
                    PresetChip(
                        title: p.fahrenheit.map { "\($0)°" } ?? "—",
                        detail: [p.profile?.name, p.holdSeconds.map { "\($0) s" }].compactMap { $0 }.joined(separator: " · "),
                        active: p.index == (rig.status?.activePreset ?? rig.state.activePreset),
                        action: { rig.selectPreset(p.index) }
                    )
                }
            }
        }
        .disabled(rig.isHeating)
    }
}
