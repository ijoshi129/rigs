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

/// The views live in Rigs/Shared/RigActivityViews.swift.
struct RigLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RigActivityAttributes.self) { context in
            ActivityLockScreen(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Theme.background)
                .activitySystemActionForegroundColor(Theme.accent)
        } dynamicIsland: { context in
            let s = context.state
            let a = context.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityTemperature(state: s, attributes: a, size: 40)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTrailing(state: s, size: 22)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityExpandedBottom(attributes: a, state: s)
                        .padding(.horizontal, 6)
                }
            } compactLeading: {
                Text(activityTemp(s.temperatureF, a) + "°")
                    .font(.geist(15, .medium)).monospacedDigit()
                    .foregroundStyle(s.phase == .lost ? Theme.ink3 : Theme.heat(Double(s.temperatureF)))
            } compactTrailing: {
                ActivityCompactTrailing(state: s)
            } minimal: {
                if s.phase == .lost {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash").foregroundStyle(Theme.ink3)
                } else {
                    Text(activityTemp(s.temperatureF, a))
                        .font(.geist(13, .medium)).monospacedDigit()
                        .foregroundStyle(Theme.heat(Double(s.temperatureF)))
                }
            }
            .keylineTint(Theme.accent)
        }
    }
}
