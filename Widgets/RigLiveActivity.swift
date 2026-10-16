import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RigsWidgets: WidgetBundle {
    var body: some Widget {
        RigLiveActivity()
        StartHeatingControl()
        StopHeatingControl()
    }
}

struct RigLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RigActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Theme.background)
                .activitySystemActionForegroundColor(Theme.accent)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Temperature(state: s, attributes: context.attributes, size: 40)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: s, size: 22)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            StatusLine(state: s, attributes: context.attributes)
                            Spacer(minLength: 4)
                            if s.phase != .done { StopButton() }
                        }
                        HoldBar(state: s)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Text(format(s.temperatureF, context.attributes) + "°")
                    .font(.geist(15, .medium)).monospacedDigit()
                    .foregroundStyle(Theme.heat(Double(s.temperatureF)))
            } compactTrailing: {
                Countdown(state: s, size: 15).frame(maxWidth: 44)
            } minimal: {
                Text(format(s.temperatureF, context.attributes))
                    .font(.geist(13, .medium)).monospacedDigit()
                    .foregroundStyle(Theme.heat(Double(s.temperatureF)))
            }
            .keylineTint(Theme.accent)
        }
    }
}

private func format(_ f: Int, _ a: RigActivityAttributes) -> String {
    formatTemp(f, a.unitsCelsius ? .c : .f)
}

private struct LockScreenView: View {
    let context: ActivityViewContext<RigActivityAttributes>

    var body: some View {
        let s = context.state
        HStack(alignment: .center, spacing: 18) {
            Temperature(state: s, attributes: context.attributes, size: 56)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    StatusLine(state: s, attributes: context.attributes)
                    Spacer(minLength: 4)
                    Countdown(state: s, size: 17)
                }
                HoldBar(state: s)
                HStack {
                    Text("\(context.attributes.rigName) · \(context.attributes.profile)")
                        .font(.geist(12)).foregroundStyle(Theme.ink2)
                    Spacer(minLength: 4)
                    if s.phase != .done { StopButton() }
                }
            }
        }
        .padding(18)
        .foregroundStyle(Theme.ink)
    }
}

private struct Temperature: View {
    let state: RigActivityAttributes.ContentState
    let attributes: RigActivityAttributes
    let size: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Text(format(state.temperatureF, attributes))
                .font(.geist(size, .extraLight)).monospacedDigit()
                .tracking(-size * 0.04)
                .foregroundStyle(state.temperatureF > 150 ? Theme.heat(Double(state.temperatureF)) : Theme.ink)
            Text(attributes.unitsCelsius ? "°C" : "°F").font(.geist(size * 0.3, .light)).padding(.top, size * 0.08)
        }
    }
}

private struct StatusLine: View {
    let state: RigActivityAttributes.ContentState
    let attributes: RigActivityAttributes

    var body: some View {
        let text = switch state.phase {
        case .heating: "Heating to \(format(state.targetF, attributes))°"
        case .holding: "Holding"
        case .done: "Done"
        }
        Text(text).font(.geist(15))
    }
}

/// Stops the session from the Lock Screen or Dynamic Island.
private struct StopButton: View {
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

/// Seconds left in the hold, ticking on its own.
private struct Countdown: View {
    let state: RigActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        if state.phase == .holding, let end = state.holdEnds, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true, showsHours: false)
                .font(.geist(size, .medium)).monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.accent)
        } else {
            Image(systemName: state.phase == .done ? "checkmark" : "flame")
                .font(.system(size: size * 0.9))
                .foregroundStyle(Theme.accent)
        }
    }
}

/// A thin cyan line that drains over the hold.
private struct HoldBar: View {
    let state: RigActivityAttributes.ContentState

    var body: some View {
        if state.phase == .holding, let end = state.holdEnds, end > .now {
            ProgressView(timerInterval: end.addingTimeInterval(-Double(max(state.holdSeconds, 1)))...end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(Theme.accent)
        } else {
            Rectangle().fill(state.phase == .done ? Theme.accent : Theme.line).frame(height: 2)
        }
    }
}
