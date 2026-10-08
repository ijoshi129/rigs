import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let s = model.switch2 { Switch2DeckView(rig: s) }
                    if let p = model.peakPro { PeakProDeckView(rig: p) }
                    if !model.hasAnyRig {
                        ConnectView(inline: true).deck()
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Rigs")
            .toolbar {
                if model.hasAnyRig, model.switch2 == nil || model.peakPro == nil, !model.isMock {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add a rig")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                ConnectView()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Theme.surface)
                    .environment(model)
            }
            .task {
                await model.bluetooth?.reconnectRemembered()
            }
        }
    }
}
