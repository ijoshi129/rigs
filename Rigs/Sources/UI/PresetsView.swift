import RigKit
import SwiftUI

struct PresetsView: View {
    @Environment(Switch2Controller.self) private var rig
    @AppStorage(Prefs.units) private var units: Units = .f

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Presets", subtitle: "The five buttons on the Switch 2")
                VStack(spacing: 0) {
                    ForEach(rig.userPresets) { p in
                        let active = p.index == rig.activeIndex
                        NavigationLink(value: p.index) {
                            HStack(spacing: 14) {
                                Text(p.fahrenheit.map { "\(formatTemp($0, units))°" } ?? "—")
                                    .font(.geist(30, .light)).monospacedDigit()
                                    .frame(width: 80, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(p.profile?.name ?? "Profile").font(.geist(16, .medium))
                                        if active {
                                            Text("Active").font(.geist(11, .medium))
                                                .padding(.horizontal, 8).padding(.vertical, 2)
                                                .background(Theme.accent).foregroundStyle(Theme.onAccent)
                                        }
                                    }
                                    Text(p.holdSeconds.map { "\($0) s hold" } ?? "—").font(.geist(13)).foregroundStyle(Theme.ink2)
                                }
                                Spacer()
                                ProfileGlyph(profile: p.profile).foregroundStyle(Theme.ink.opacity(0.7))
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Theme.ink3)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(active ? Theme.surfaceStrong.opacity(0.6) : .clear)
                            .overlay(alignment: .bottom) { if p.index < 5 { Theme.line.frame(height: 1) } }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.surface)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))

                Text("Changes are written to the rig when you save, so the buttons on the device match the app.")
                    .font(.geist(12)).foregroundStyle(Theme.ink3).padding(.top, 18).padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Int.self) { PresetEditView(index: $0) }
    }
}

/// A small line drawing of a heating profile's shape.
struct ProfileGlyph: View {
    let profile: Switch2.HeatingProfile?
    var width: CGFloat = 26

    var body: some View {
        Canvas { ctx, size in
            guard let profile else { return }
            let sx = size.width / 26, sy = size.height / 12
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            var p = Path()
            switch profile {
            case .steady: p.move(to: pt(1, 6)); p.addLine(to: pt(25, 6))
            case .ascent: p.move(to: pt(1, 10)); p.addCurve(to: pt(25, 2), control1: pt(10, 10), control2: pt(14, 2))
            case .descent: p.move(to: pt(1, 2)); p.addCurve(to: pt(25, 10), control1: pt(10, 2), control2: pt(14, 10))
            case .valley: p.move(to: pt(1, 2)); p.addCurve(to: pt(13, 10), control1: pt(7, 2), control2: pt(9, 10)); p.addCurve(to: pt(25, 2), control1: pt(17, 10), control2: pt(19, 2))
            case .hill: p.move(to: pt(1, 10)); p.addCurve(to: pt(13, 2), control1: pt(7, 10), control2: pt(9, 2)); p.addCurve(to: pt(25, 10), control1: pt(17, 2), control2: pt(19, 10))
            case .custom: p.move(to: pt(1, 8)); p.addLine(to: pt(7, 3)); p.addLine(to: pt(13, 7)); p.addLine(to: pt(19, 2)); p.addLine(to: pt(25, 6))
            }
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: width * 12 / 26)
        .accessibilityHidden(true)
    }
}

struct PresetEditView: View {
    let index: Int
    @Environment(Switch2Controller.self) private var rig
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.units) private var units: Units = .f
    @State private var fahrenheit = 500
    @State private var hold = 30
    @State private var profile: Switch2.HeatingProfile = .descent
    @State private var saving = false
    @State private var loaded = false

    private var preset: Switch2.Preset { rig.state.presets[index] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Preset \(index)", subtitle: "Switch 2 · button \(index)", showsBack: true, trailing: AnyView(
                    SmallButton(title: saving ? "Saving…" : "Save", prominent: true) { Task { await save() } }.disabled(saving || !rig.isReady)
                ))

                HStack {
                    stepButton("minus", "Lower by 5 degrees") { fahrenheit = max(250, fahrenheit - 5) }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatTemp(fahrenheit, units)).font(.geist(96, .extraLight)).tracking(-4).monospacedDigit()
                            .contentTransition(.numericText(value: Double(fahrenheit)))
                        Text("°\(units.rawValue)").font(.geist(26, .light)).foregroundStyle(Theme.ink2)
                    }
                    Spacer()
                    stepButton("plus", "Raise by 5 degrees") { fahrenheit = min(650, fahrenheit + 5) }
                }
                .padding(.top, 12)
                .animation(.snappy, value: fahrenheit)

                Text(units == .f ? "Temperature · \(formatTemp(fahrenheit, .c)) °C" : "Temperature · \(fahrenheit) °F")
                    .font(.geist(13)).foregroundStyle(Theme.ink2).frame(maxWidth: .infinity).padding(.top, 14)
                Slider(value: Binding(get: { Double(fahrenheit) }, set: { fahrenheit = Int($0.rounded()) }), in: 250...650, step: 1)
                    .padding(.top, 4)
                    .sensoryFeedback(.selection, trigger: fahrenheit / 25)

                Surface {
                    Row(title: "Hold time", detail: "10 to 90 seconds", last: true) {
                        SquareStepper(value: hold, range: 10...90, step: 5, label: "Hold time", format: { "\($0) s" }) { hold = $0 }
                    }
                }
                .padding(.top, 20)

                SectionLabel("Heating profile")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Switch2.HeatingProfile.allCases, id: \.self) { p in
                        let active = p == profile
                        Button { profile = p } label: {
                            VStack(spacing: 8) {
                                ProfileGlyph(profile: p, width: 34)
                                Text(p.name).font(.geist(13, active ? .medium : .regular))
                            }
                            .frame(maxWidth: .infinity).frame(height: 66)
                            .background(active ? Theme.surfaceStrong : Theme.surface)
                            .overlay(Rectangle().strokeBorder(active ? Theme.accent : Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .sensoryFeedback(.selection, trigger: profile)
                Text(profile.summary).font(.geist(13)).foregroundStyle(Theme.ink2).padding(.top, 10).padding(.horizontal, 4)
                if profile == .custom {
                    Text("Custom curve: \(preset.curvePoints.count) points on the rig. Editing the points comes next.")
                        .font(.geist(13)).foregroundStyle(Theme.ink2).padding(.top, 8).padding(.horizontal, 4)
                }
                if let e = rig.lastError { Text(e).font(.geist(13)).foregroundStyle(Theme.error).padding(.top, 14) }
                Text("Saving writes to the rig, about three seconds. Its button \(index) changes with it.")
                    .font(.geist(12)).foregroundStyle(Theme.ink3).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            fahrenheit = preset.fahrenheit ?? 500
            hold = preset.holdSeconds ?? 30
            profile = preset.profile ?? .descent
        }
    }

    private func stepButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20, weight: .light))
                .frame(width: 44, height: 44)
                .background(Theme.surface)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    private func save() async {
        saving = true
        var p = preset
        p.fahrenheit = fahrenheit
        p.celsius = Temperature.fahrenheitToCelsius(fahrenheit)
        p.holdSeconds = hold
        p.profile = profile
        await rig.savePreset(p)
        saving = false
        if rig.lastError == nil { dismiss() }
    }
}
