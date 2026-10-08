import RigKit
import SwiftUI

struct PeakProDeckView: View {
    @Bindable var rig: PeakProController
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 16) {
                HeroTemperature(fahrenheit: rig.temperatureF, label: stateLabel)
                Spacer(minLength: 0)
            }

            HeatCurveView(samples: rig.history, target: rig.targetF, maximum: 650)

            HStack(spacing: 10) {
                SessionButton(
                    heating: rig.isHeating,
                    idleTitle: rig.targetF.map { "Heat to \(Int($0))°" } ?? "Heat",
                    secondsRemaining: rig.state.secondsRemaining.map { Int($0.rounded()) },
                    action: { rig.isHeating ? rig.stopSession() : rig.startSession() }
                )
                .disabled(!rig.state.authenticated || !rig.connected)

                if rig.isHeating {
                    Button { rig.boost() } label: {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(16)
                            .foregroundStyle(Theme.ember)
                            .background(Theme.raised, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Boost")
                }
            }

            profiles

            if let err = rig.lastError {
                Text(err).font(Theme.caption).foregroundStyle(.red)
            }
        }
        .deck()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(rig.displayName).font(Theme.title).foregroundStyle(Theme.text)
            if !rig.connected {
                Text("Disconnected").font(Theme.caption).foregroundStyle(Theme.dim)
            } else if let c = rig.state.chamberType, c != .none {
                Text(c.name).font(Theme.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            BatteryBadge(percent: rig.state.batteryPercent, charging: rig.state.isCharging)
            Menu {
                Button("Disconnect", role: .destructive) { Task { await model.disconnect(.peakPro) } }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(Theme.dim)
            }
        }
    }

    private var stateLabel: String {
        guard rig.state.authenticated else { return "Pairing" }
        return rig.state.operatingState.name
    }

    private var profiles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(rig.profiles) { p in
                    PresetChip(
                        title: p.fahrenheit.map { "\(Int($0.rounded()))°" } ?? "—",
                        detail: [p.name.isEmpty ? nil : p.name, p.seconds.map { "\(Int($0)) s" }].compactMap { $0 }.joined(separator: " · "),
                        active: p.slot == rig.state.activeProfile,
                        action: { rig.selectProfile(p.slot) }
                    )
                }
            }
        }
        .disabled(rig.isHeating)
    }
}
