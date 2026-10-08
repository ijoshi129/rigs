import Charts
import SwiftUI

/// Temperature over the current session. The line takes the color of the
/// live temperature; the dashed rule is the target.
struct HeatCurveView: View {
    let samples: [TemperatureSample]
    let target: Double?
    let maximum: Double

    private var current: Double { samples.last?.fahrenheit ?? 100 }

    var body: some View {
        Chart {
            ForEach(samples) { s in
                AreaMark(x: .value("Time", s.time), y: .value("°F", s.fahrenheit))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.heat(current).opacity(0.35), Theme.heat(current).opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                LineMark(x: .value("Time", s.time), y: .value("°F", s.fahrenheit))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(Theme.heat(current))
            }
            if let target {
                RuleMark(y: .value("Target", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.dim.opacity(0.7))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("\(Int(target))°")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
            }
        }
        .chartYScale(domain: 50...maximum)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [200, 400, 600].filter { Double($0) < maximum }) { v in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let i = v.as(Int.self) { Text("\(i)").font(.system(size: 10)).foregroundStyle(Theme.dim) }
                }
            }
        }
        .overlay {
            if samples.count < 2 {
                Text("Start a session to see the heat curve")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.dim)
            }
        }
        .frame(height: 120)
    }
}
