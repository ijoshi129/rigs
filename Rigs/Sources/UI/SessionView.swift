import RigKit
import SwiftUI

/// The main screen: the rig half off the right edge, a thin temperature,
/// the presets as a ladder, the glowing power button, and the +/− rocker.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(Switch2Controller.self) private var rig
    @AppStorage(Prefs.units) private var units: Units = .f
    @AppStorage(Prefs.heatColorsNumber) private var heatColors = true
    @State private var editing: Int? = DebugLaunch.presetToEdit
    @State private var showSettings = DebugLaunch.open == "settings"

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 700
            VStack(alignment: .leading, spacing: 0) {
                header
                readout(compact: compact).padding(.top, geo.size.height * 0.05)
                ladder(compact: compact).padding(.top, geo.size.height * 0.04)
                Spacer(minLength: 16)
                controls
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 58 + 18)
        }
        .background { backdrop }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $editing) { PresetEditView(index: $0) }
        .navigationDestination(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: Pieces

    private var backdrop: some View {
        ZStack(alignment: .topTrailing) {
            RadialGradient(colors: [Theme.accent.opacity(0.2), .clear], center: .center, startRadius: 0, endRadius: 190)
                .frame(width: 380, height: 420)
                .blur(radius: 10)
                .offset(x: 120, y: 110)
            Image("Switch2")
                .resizable()
                .scaledToFit()
                .frame(height: 860)
                .offset(x: 150, y: 10)
                .opacity(rig.connected ? 0.5 : 0.25)
                .animation(.easeOut(duration: 0.4), value: rig.connected)
            LinearGradient(stops: [.init(color: Theme.background, location: 0.25), .init(color: Theme.background.opacity(0.6), location: 0.58), .init(color: Theme.background.opacity(0.1), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: Theme.background, location: 0.7)], startPoint: .top, endPoint: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(rig.name).font(.geist(15, .medium)).lineLimit(1)
            Spacer()
            if let s = rig.status {
                Text("\(s.batteryPercent)%\(s.charging ? " ⚡" : "")").font(.geist(15)).foregroundStyle(Theme.ink2).monospacedDigit()
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 17)).foregroundStyle(Theme.ink2).frame(width: 36, height: 36)
            }
            .accessibilityLabel("Settings")
        }
        .frame(height: 40)
    }

    private func readout(compact: Bool) -> some View {
        let f = rig.temperatureF
        let color: Color = heatColors && (f ?? 0) > 150 ? Theme.heat(Double(f ?? 0)) : Theme.ink
        let size: CGFloat = compact ? 100 : 130
        return VStack(alignment: .leading, spacing: compact ? 14 : 20) {
            HStack(alignment: .top, spacing: 4) {
                Text(formatTemp(f, units))
                    .font(.geist(size, .extraLight))
                    .tracking(-size * 0.05)
                    .monospacedDigit()
                    .foregroundStyle(color)
                    // Geist's line box is ~1.3× the size; trim it to the digits.
                    .padding(.top, -size * 0.27)
                    .padding(.bottom, -size * 0.26)
                Text("°\(units.rawValue)").font(.geist(size * 0.26, .light)).padding(.top, -size * 0.04)
            }
            statusLine
            if let e = rig.lastError { Text(e).font(.geist(14)).foregroundStyle(Theme.error) }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusLine: some View {
        let s = rig.status
        let target = rig.activePreset?.fahrenheit
        let line: String
        var detail: String?
        if !rig.connected {
            line = model.isReconnecting ? "Reconnecting…" : "Disconnected"
        } else if s == nil {
            line = "Waiting for the rig"
        } else if rig.isHeating {
            if let t = target, let f = rig.temperatureF, f < t - 5 { line = "Heating to \(formatTemp(t, units))°" } else { line = "Holding" }
            if let r = s?.sessionSecondsRemaining, r > 0 { detail = "\(r) s left" }
        } else {
            line = rig.state.initialDumpComplete ? "Ready" : "Syncing"
        }
        return Text("\(line)\(Text(detail.map { " · \($0)" } ?? "").foregroundStyle(Theme.ink2))").font(.geist(17))
    }

    /// The presets, hottest at the top. Tap to select; hold to edit.
    private func ladder(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rig.presetsByTemperature.reversed(), id: \.self) { i in
                let p = rig.state.presets[i]
                let active = i == rig.activeIndex
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(active ? Theme.accent : Color(hex: 0x3A3D44))
                        .frame(width: active ? 34 : 14, height: active ? 2 : 1)
                        .shadow(color: active ? Theme.accent : .clear, radius: 4)
                    Text(formatTemp(p.fahrenheit, units))
                        .font(.geist(active ? 26 : 20, .light))
                        .monospacedDigit()
                        .foregroundStyle(active ? Theme.ink : Theme.ink3)
                    if active {
                        Text([p.profile?.name, p.holdSeconds.map { "\($0) s" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.geist(14)).foregroundStyle(Theme.ink2)
                    }
                }
                .frame(height: compact ? 36 : 44)
                .padding(.trailing, 16)
                .contentShape(Rectangle())
                .onTapGesture { if rig.isReady, !rig.isHeating, !active { rig.selectPreset(i) } }
                .onLongPressGesture(minimumDuration: 0.45) { if !rig.isHeating { editing = i } }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint("Hold to edit")
            }
        }
        .animation(.snappy(duration: 0.2), value: rig.activeIndex)
        .sensoryFeedback(.selection, trigger: rig.activeIndex)
    }

    private var controls: some View {
        let order = rig.presetsByTemperature
        let pos = order.firstIndex(of: rig.activeIndex) ?? 0
        return HStack {
            if rig.connected {
                Button { rig.isHeating ? rig.stopSession() : rig.startSession() } label: {
                    HStack(spacing: 16) {
                        RingButton(enabled: rig.isReady) { if rig.isHeating { StopGlyph() } else { PowerGlyph() } }
                        Text(rig.isHeating ? "Stop" : "Heat to \(formatTemp(rig.activePreset?.fahrenheit, units))°").font(.geist(18))
                    }
                }
                .buttonStyle(.pressable)
                .disabled(!rig.isReady)
                .sensoryFeedback(.impact(weight: .heavy), trigger: rig.isHeating)
            } else {
                HStack(spacing: 16) {
                    RingButton(enabled: false) { PowerGlyph() }
                    Text(model.isReconnecting ? "Reconnecting…" : "Disconnected").font(.geist(18)).foregroundStyle(Theme.ink2)
                }
            }
            Spacer()
            HStack(spacing: 14) {
                if rig.isHeating {
                    Text("Hold\ntime").font(.geist(14)).foregroundStyle(Theme.ink2).multilineTextAlignment(.trailing)
                }
                Rocker(
                    plusLabel: rig.isHeating ? "Add 10 seconds" : "Hotter preset",
                    minusLabel: rig.isHeating ? "Remove 10 seconds" : "Cooler preset",
                    canPlus: rig.isReady && (rig.isHeating ? rig.extend < 9 : pos < order.count - 1),
                    canMinus: rig.isReady && (rig.isHeating ? rig.extend > 0 : pos > 0),
                    onPlus: { rig.isHeating ? rig.extend(to: rig.extend + 1) : rig.selectPreset(order[pos + 1]) },
                    onMinus: { rig.isHeating ? rig.extend(to: rig.extend - 1) : rig.selectPreset(order[pos - 1]) }
                )
                .sensoryFeedback(.increase, trigger: rig.extend)
            }
        }
    }
}
