import RigKit
import SwiftUI

struct LightsView: View {
    @Environment(Switch2Controller.self) private var rig
    @State private var brightness: Double = 100
    @State private var writeTask: Task<Void, Never>?
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let st = rig.status
        let mode = st?.lightMode ?? 1
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Lights", subtitle: "Changes apply to the rig instantly")

                Surface {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Brightness").font(.geist(15))
                            Spacer()
                            Text("\(Int(brightness))%").font(.geist(15)).foregroundStyle(Theme.ink2).monospacedDigit()
                        }
                        Slider(value: $brightness, in: 0...100, step: 1)
                            .disabled(st == nil)
                            .onChange(of: brightness) { _, v in
                                // Write after 300 ms of quiet so dragging doesn't flood the rig.
                                writeTask?.cancel()
                                writeTask = Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    guard !Task.isCancelled, Int(v) != rig.status?.brightness else { return }
                                    rig.setBrightness(Int(v))
                                }
                            }
                        Text("All the way down is stealth: only the power button stays lit.").font(.geist(12)).foregroundStyle(Theme.ink2)
                    }
                    .padding(.vertical, 14)
                }

                SectionLabel("Light mode · \(Switch2.LightMode.named(mode).name)")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(Switch2.LightMode.all) { m in
                        let (a, b) = Theme.lightModeColors[m.code] ?? (0x888888, 0x444444)
                        let active = m.code == mode
                        Button { rig.setLightMode(m.code) } label: {
                            Rectangle()
                                .fill(m.code <= 9 ? AnyShapeStyle(Color(hex: a)) : AnyShapeStyle(LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(Rectangle().strokeBorder(active ? Theme.ink : .clear, lineWidth: 2).padding(-4))
                        }
                        .buttonStyle(.pressable)
                        .disabled(st == nil)
                        .accessibilityLabel(m.name)
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 4)
                .sensoryFeedback(.selection, trigger: mode)
                Text("These are the rig's own LED modes, in the rig's own colors.").font(.geist(12)).foregroundStyle(Theme.ink3).padding(.top, 10).padding(.horizontal, 4)

                Surface {
                    Row(title: "Haptic feedback") {
                        SquareToggle(isOn: Binding(get: { st?.hapticFeedback ?? false }, set: { rig.setHaptics($0) }), label: "Haptic feedback")
                    }
                    Row(title: "Auto shut-off", detail: (st?.autoShutOffMinutes ?? 0) > 0 ? "\(st!.autoShutOffRemainingMinutes) min left" : "Never") {
                        SquareStepper(value: st?.autoShutOffMinutes ?? 0, range: 0...60, step: 5, label: "Auto shut-off", format: { $0 == 0 ? "Off" : "\($0) min" }) { rig.setAutoShutOff($0) }
                    }
                    Row(title: "Cleaning assist", detail: "Warms the insert for 30 s to loosen it") {
                        SmallButton(title: rig.state.cleaningActive ? "Stop" : "Start") { rig.cleaningAssist(!rig.state.cleaningActive) }.disabled(st == nil)
                    }
                    Row(title: "Name", detail: [rig.name, rig.state.firmwareVersion].compactMap { $0 }.joined(separator: " · "), last: true) {
                        SmallButton(title: "Rename") { newName = rig.state.name ?? ""; renaming = true }
                    }
                }
                .padding(.top, 20)
                if let e = rig.lastError { Text(e).font(.geist(13)).foregroundStyle(Theme.error).padding(.top, 14) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if let b = st?.brightness { brightness = Double(b) } }
        .alert("Name this rig", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { if !newName.isEmpty { rig.rename(newName) } }
        } message: {
            Text("Up to 29 letters, numbers, and symbols.")
        }
    }
}
