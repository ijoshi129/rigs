#if DEBUG
import SwiftUI

/// Every Live Activity phase, for screenshots: `-open activity` (heating,
/// holding) and `-open activity2` (reconnecting, done).
/// The system draws the real containers; these frames only approximate them.
struct ActivityGallery: View {
    private let a = RigActivityAttributes(rigName: "Zuko", profile: "Descent", unitsCelsius: false)

    private var samples: [(String, ActivityState)] {
        let all: [(String, ActivityState)] = [
            ("Heating", .init(phase: .heating, temperatureF: 318, targetF: 500, holdEnds: nil, holdSeconds: 30, startF: 71)),
            ("Holding", .init(phase: .holding, temperatureF: 498, targetF: 500, holdEnds: .now.addingTimeInterval(18), holdSeconds: 30, startF: 71)),
            ("Reconnecting", .init(phase: .lost, temperatureF: 498, targetF: 500, holdEnds: nil, holdSeconds: 30, startF: 71)),
            ("Done", .init(phase: .done, temperatureF: 487, targetF: 500, holdEnds: nil, holdSeconds: 30, startF: 71)),
        ]
        return DebugLaunch.open == "activity2" ? Array(all.suffix(2)) : Array(all.prefix(2))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(samples, id: \.0) { name, s in
                    Text(name.uppercased()).font(.geist(11)).tracking(1.2).foregroundStyle(Theme.ink3)
                    HStack(spacing: 10) {
                        pill { compactLeading(s) } trailing: { ActivityCompactTrailing(state: s) }
                    }
                    ActivityLockScreen(attributes: a, state: s)
                        .background(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    island(s)
                }
            }
            .padding(16)
        }
        .background(Color(hex: 0x2A2D33))
    }

    private func compactLeading(_ s: ActivityState) -> some View {
        Text(activityTemp(s.temperatureF, a) + "°")
            .font(.geist(15, .medium)).monospacedDigit()
            .foregroundStyle(s.phase == .lost ? Theme.ink3 : Theme.heat(Double(s.temperatureF)))
    }

    private func pill<L: View, T: View>(@ViewBuilder _ leading: () -> L, @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            leading()
            Spacer(minLength: 90)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(width: 250, height: 37)
        .background(Capsule().fill(.black))
        .frame(maxWidth: .infinity)
    }

    private func island(_ s: ActivityState) -> some View {
        VStack(spacing: 10) {
            HStack {
                ActivityTemperature(state: s, attributes: a, size: 40)
                Spacer()
                ActivityTrailing(state: s, size: 22)
            }
            ActivityExpandedBottom(attributes: a, state: s)
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
        .foregroundStyle(Theme.ink)
        .background(RoundedRectangle(cornerRadius: 44).fill(.black))
    }
}
#endif
