import SwiftUI

/// Before any rig is connected: the device, one line, one button.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @State private var showHelp = DebugLaunch.open == "help"
    @State private var breathe = false

    private var line: String {
        if let e = model.error { return e }
        if model.isSearching { return "Looking for your rig…" }
        return "Turn it on, then press the button."
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // The rig, large, with the LED glow behind it.
                ZStack {
                    RadialGradient(colors: [Theme.accent.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 200)
                        .frame(width: 420, height: 300)
                        .blur(radius: 10)
                        .scaleEffect(breathe ? 1.15 : 0.9)
                        .opacity(breathe ? 1 : 0.7)
                        .offset(y: -40)
                    Image("Switch2")
                        .resizable()
                        .scaledToFit()
                        .frame(height: min(640, geo.size.height * 0.78))
                }
                .padding(.top, geo.size.height * 0.08)
                .frame(maxWidth: .infinity)

                LinearGradient(colors: [.clear, Theme.background], startPoint: .init(x: 0.5, y: 0.5), endPoint: .init(x: 0.5, y: 0.72))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Rigs").font(.geist(15, .medium))
                        Spacer()
                        Button("Help") { showHelp = true }
                            .font(.geist(15))
                            .foregroundStyle(Theme.ink2)
                    }
                    .frame(height: 40)

                    Spacer()

                    Text("Switch 2").font(.geist(40, .light)).tracking(-0.8)
                    Text(line)
                        .font(.geist(16))
                        .foregroundStyle(model.error != nil ? Theme.error : Theme.ink2)
                        .padding(.top, 10)
                        .frame(maxWidth: 320, alignment: .leading)
                        .animation(.default, value: line)

                    Button { model.connect() } label: {
                        HStack(spacing: 16) {
                            RingButton(enabled: !model.isSearching) { PowerGlyph() }
                            Text(model.isSearching ? "Searching…" : "Connect").font(.geist(18))
                        }
                    }
                    .buttonStyle(.pressable)
                    .disabled(model.isSearching)
                    .padding(.top, 32)
                    .sensoryFeedback(.impact(weight: .medium), trigger: model.isSearching) { _, new in new }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }
        }
        .background(Theme.background)
        .onChange(of: model.isSearching, initial: true) { _, searching in
            withAnimation(searching ? .easeInOut(duration: 1.6).repeatForever() : .easeOut(duration: 0.4)) { breathe = searching }
        }
        .sheet(isPresented: $showHelp) { HelpSheet() }
    }
}

struct HelpSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var listing = false

    private let steps = [
        ("Turn pairing on", "Hold + and − together for 3 seconds. The rig flashes and buzzes."),
        ("Close the Dr. Dabber app", "On every phone and tablet nearby. Only one app can connect at a time."),
        ("Allow Bluetooth", "Check that Rigs has Bluetooth permission in Settings."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(listing ? "Nearby devices" : "Having trouble?").font(.geist(24, .light)).tracking(-0.5)
            if listing { nearbyList } else { stepList }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.sheet)
        .presentationDetents(listing ? [.large] : [.fraction(0.68)])
        .presentationCornerRadius(0)
        .presentationBackground(Theme.sheet)
        .onDisappear { if listing { model.bluetooth?.stopSearch() } }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: 14) {
                    Text("\(i + 1)").font(.geist(15)).foregroundStyle(Theme.accent).frame(width: 20, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.0).font(.geist(16, .medium))
                        Text(s.1).font(.geist(14)).foregroundStyle(Theme.ink2)
                    }
                }
            }
            if model.bluetooth != nil {
                Button {
                    listing = true
                    model.bluetooth?.search(everything: true)
                } label: {
                    Text("Show every nearby device").font(.geist(16))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Theme.surface)
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .padding(.top, 8)
            }
            Button("Done") { dismiss() }
                .font(.geist(16)).foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 20)
    }

    private var nearbyList: some View {
        let devices = model.bluetooth?.nearby ?? []
        return ScrollView {
            VStack(spacing: 0) {
                if devices.isEmpty {
                    Text("Listening…").font(.geist(14)).foregroundStyle(Theme.ink2).padding(.vertical, 20)
                }
                ForEach(devices) { d in
                    Button {
                        model.bluetooth?.connect(to: d.id)
                        dismiss()
                    } label: {
                        HStack {
                            Text(d.name).font(.geist(16))
                            if d.looksLikeSwitch2 { Text("Switch 2").font(.geist(12)).foregroundStyle(Theme.accent) }
                            Spacer()
                            Text("\(d.rssi) dBm").font(.geist(12)).foregroundStyle(Theme.ink3).monospacedDigit()
                        }
                        .frame(height: 50)
                        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 16)
    }
}
