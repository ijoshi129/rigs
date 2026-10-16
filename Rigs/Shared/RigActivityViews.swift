import AppIntents
import SwiftUI

/// The Live Activity's views, shared so the app's Debug gallery can render
/// every phase without a running session. The widget wraps them.

typealias ActivityState = RigActivityAttributes.ContentState

extension ActivityState {
    /// 0…1 from where heating started to the target.
    var heatProgress: Double {
        let start = Double(startF ?? 72), target = Double(targetF)
        guard target > start + 1 else { return 1 }
        return min(1, max(0, (Double(temperatureF) - start) / (target - start)))
    }

    var isLive: Bool { phase == .heating || phase == .holding }
}

func activityTemp(_ f: Int, _ a: RigActivityAttributes) -> String {
    formatTemp(f, a.unitsCelsius ? .c : .f)
}

/// Lock Screen and banner.
struct ActivityLockScreen: View {
    let attributes: RigActivityAttributes
    let state: ActivityState

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ActivityTemperature(state: state, attributes: attributes, size: 56)
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    ActivityStatusLine(state: state, attributes: attributes)
                    Spacer(minLength: 4)
                    ActivityTrailing(state: state, size: 17)
                }
                ActivityBar(state: state)
                HStack {
                    Text("\(attributes.rigName) · \(attributes.profile)")
                        .font(.geist(12)).foregroundStyle(Theme.ink2).lineLimit(1)
                    Spacer(minLength: 4)
                    if state.isLive { ActivityStopButton() }
                }
            }
        }
        .padding(18)
        .foregroundStyle(Theme.ink)
    }
}

/// The number, colored by heat; grey while the link is down.
struct ActivityTemperature: View {
    let state: ActivityState
    let attributes: RigActivityAttributes
    let size: CGFloat

    private var color: Color {
        if state.phase == .lost { return Theme.ink3 }
        return state.temperatureF > 150 ? Theme.heat(Double(state.temperatureF)) : Theme.ink
    }

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Text(activityTemp(state.temperatureF, attributes))
                .font(.geist(size, .extraLight)).monospacedDigit()
                .tracking(-size * 0.04)
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(state.temperatureF)))
            Text(attributes.unitsCelsius ? "°C" : "°F").font(.geist(size * 0.3, .light)).padding(.top, size * 0.08)
        }
    }
}

struct ActivityStatusLine: View {
    let state: ActivityState
    let attributes: RigActivityAttributes

    var body: some View {
        let text = switch state.phase {
        case .heating: "Heating to \(activityTemp(state.targetF, attributes))°"
        case .holding: "Holding"
        case .done: "Done"
        case .lost: "Reconnecting…"
        }
        Text(text).font(.geist(15)).foregroundStyle(state.phase == .lost ? Theme.ink2 : Theme.ink)
    }
}

/// Countdown while holding; otherwise an icon for the phase.
struct ActivityTrailing: View {
    let state: ActivityState
    let size: CGFloat

    var body: some View {
        if state.phase == .holding, let end = state.holdEnds, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true, showsHours: false)
                .font(.geist(size, .medium)).monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.accent)
        } else {
            Image(systemName: icon)
                .font(.system(size: size * 0.9))
                .foregroundStyle(state.phase == .lost ? Theme.ink3 : Theme.accent)
        }
    }

    private var icon: String {
        switch state.phase {
        case .heating, .holding: "flame"
        case .done: "checkmark"
        case .lost: "antenna.radiowaves.left.and.right.slash"
        }
    }
}

/// Fills while heating, drains over the hold, full when done.
struct ActivityBar: View {
    let state: ActivityState

    var body: some View {
        switch state.phase {
        case .holding:
            if let end = state.holdEnds, end > .now {
                ProgressView(timerInterval: end.addingTimeInterval(-Double(max(state.holdSeconds, 1)))...end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            } else {
                line(1)
            }
        case .heating: line(state.heatProgress)
        case .done: line(1)
        case .lost: line(0)
        }
    }

    private func line(_ fraction: Double) -> some View {
        Rectangle().fill(Theme.line).frame(height: 2)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Rectangle().fill(Theme.accent).frame(width: g.size.width * fraction)
                        .shadow(color: Theme.accent.opacity(0.6), radius: 3)
                }
            }
            .frame(height: 2)
    }
}

/// Small ring for the compact Dynamic Island while heating.
struct ActivityRing: View {
    let fraction: Double
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 2.5)
            Circle().trim(from: 0, to: fraction).stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

/// Compact trailing: countdown when holding, ring while heating.
struct ActivityCompactTrailing: View {
    let state: ActivityState

    var body: some View {
        switch state.phase {
        case .heating: ActivityRing(fraction: state.heatProgress)
        case .holding, .done, .lost: ActivityTrailing(state: state, size: 15).frame(maxWidth: 44)
        }
    }
}

/// Stops the session from the Lock Screen or Dynamic Island.
struct ActivityStopButton: View {
    var body: some View {
        Button(intent: StopSessionIntent()) {
            HStack(spacing: 6) {
                Rectangle().frame(width: 8, height: 8)
                Text("Stop").font(.geist(13, .medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .overlay(Rectangle().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop heating")
    }
}

/// Expanded Dynamic Island, bottom region.
struct ActivityExpandedBottom: View {
    let attributes: RigActivityAttributes
    let state: ActivityState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ActivityStatusLine(state: state, attributes: attributes)
                Spacer(minLength: 4)
                if state.isLive { ActivityStopButton() }
            }
            ActivityBar(state: state)
        }
    }
}
