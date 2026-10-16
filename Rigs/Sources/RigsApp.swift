import SwiftUI

@main
struct RigsApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .foregroundStyle(Theme.ink)
                .font(.geist(15))
        }
    }
}

enum Tab: String, CaseIterable {
    case session = "Session", presets = "Presets", lights = "Lights", history = "History"

    var icon: String {
        switch self {
        case .session: "flame.fill"
        case .presets: "slider.horizontal.3"
        case .lights: "lightbulb"
        case .history: "clock"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = DebugLaunch.tab ?? .session

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let rig = model.rig {
                ZStack(alignment: .bottom) {
                    // Each tab keeps its own navigation stack alive.
                    ForEach(Tab.allCases, id: \.self) { t in
                        NavigationStack { screen(t, rig) }
                            .opacity(tab == t ? 1 : 0)
                            .allowsHitTesting(tab == t)
                    }
                    TabBar(selection: $tab)
                }
                .environment(rig)
            } else {
                ConnectView()
            }
        }
    }

    @ViewBuilder private func screen(_ t: Tab, _ rig: Switch2Controller) -> some View {
        switch t {
        case .session: SessionView()
        case .presets: PresetsView()
        case .lights: LightsView()
        case .history: HistoryView()
        }
    }
}

struct TabBar: View {
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                let active = t == selection
                Button { selection = t } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(.system(size: 17)).frame(height: 22)
                        Text(t.rawValue).font(.geist(11))
                    }
                    .foregroundStyle(active ? Theme.ink : Theme.ink3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .overlay(alignment: .top) {
                        if active {
                            Theme.accent.frame(width: 32, height: 2).shadow(color: Theme.accent, radius: 4)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .background(Theme.background.opacity(0.94).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Hidden navigation bars still allow swipe-to-go-back.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
