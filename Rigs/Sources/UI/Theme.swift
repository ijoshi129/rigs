import SwiftUI

/// Smoked-glass palette with a single ember ramp that carries the heat.
enum Theme {
    static let background = Color(red: 0.106, green: 0.125, blue: 0.161)   // #1B2029
    static let surface = Color(red: 0.141, green: 0.165, blue: 0.208)      // #242A35
    static let raised = Color(red: 0.173, green: 0.200, blue: 0.251)       // #2C3340
    static let hairline = Color.white.opacity(0.08)
    static let text = Color(red: 0.933, green: 0.941, blue: 0.953)         // #EEF0F3
    static let dim = Color(red: 0.604, green: 0.639, blue: 0.698)          // #9AA3B2
    static let ember = Color(red: 0.910, green: 0.463, blue: 0.169)        // #E8762B

    /// Color for a temperature. Cold is slate; the ramp runs rust → ember →
    /// amber → white-hot across the dabbing range.
    static func heat(_ fahrenheit: Double) -> Color {
        let stops: [(Double, (Double, Double, Double))] = [
            (100, (0.29, 0.33, 0.41)),   // slate
            (300, (0.48, 0.18, 0.07)),   // rust
            (450, (0.91, 0.46, 0.17)),   // ember
            (580, (1.00, 0.77, 0.42)),   // amber
            (700, (1.00, 0.95, 0.84)),   // white-hot
        ]
        let f = min(max(fahrenheit, stops.first!.0), stops.last!.0)
        for i in 1..<stops.count where f <= stops[i].0 {
            let (f0, c0) = stops[i - 1], (f1, c1) = stops[i]
            let t = (f - f0) / (f1 - f0)
            return Color(red: c0.0 + (c1.0 - c0.0) * t, green: c0.1 + (c1.1 - c0.1) * t, blue: c0.2 + (c1.2 - c0.2) * t)
        }
        return Color(red: stops.last!.1.0, green: stops.last!.1.1, blue: stops.last!.1.2)
    }

    static let heroNumber = Font.system(size: 76, weight: .heavy, design: .rounded)
    static let heroUnit = Font.system(size: 26, weight: .semibold, design: .rounded)
    static let title = Font.system(size: 22, weight: .bold)
    static let body = Font.system(size: 16, weight: .regular)
    static let caption = Font.system(size: 13, weight: .medium)
}

struct DeckBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.hairline))
    }
}

extension View {
    func deck() -> some View { modifier(DeckBackground()) }
}

/// Battery glyph with percent; charging shown by the bolt.
struct BatteryBadge: View {
    let percent: Int?
    let charging: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: charging ? "battery.100percent.bolt" : symbol)
            if let percent { Text("\(percent)%").monospacedDigit() }
        }
        .font(Theme.caption)
        .foregroundStyle(Theme.dim)
    }

    private var symbol: String {
        switch percent ?? 0 {
        case 0..<15: "battery.0percent"
        case 15..<40: "battery.25percent"
        case 40..<65: "battery.50percent"
        case 65..<90: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// Live temperature as the hero: the number carries the heat color.
struct HeroTemperature: View {
    let fahrenheit: Double?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(fahrenheit.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(Theme.heroNumber)
                    .monospacedDigit()
                    .foregroundStyle(fahrenheit.map(Theme.heat) ?? Theme.dim)
                    .contentTransition(.numericText())
                Text("°F")
                    .font(Theme.heroUnit)
                    .foregroundStyle(Theme.dim)
            }
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.dim)
        }
        .animation(.easeOut(duration: 0.25), value: fahrenheit)
    }
}

/// The one big control per rig. Says what it will do.
struct SessionButton: View {
    let heating: Bool
    let idleTitle: String
    let secondsRemaining: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: heating ? "stop.fill" : "flame.fill")
                Text(heating ? "Stop" : idleTitle)
                if heating, let s = secondsRemaining {
                    Spacer()
                    Text("\(s) s").monospacedDigit().foregroundStyle(Theme.text.opacity(0.8))
                }
            }
            .font(.system(size: 18, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(heating ? Theme.text : Theme.background)
        .background(heating ? Theme.raised : Theme.ember, in: Capsule())
        .overlay(Capsule().stroke(heating ? Theme.ember.opacity(0.6) : .clear, lineWidth: 1.5))
        .accessibilityLabel(heating ? "Stop session" : idleTitle)
    }
}

/// A preset or profile chip. Active state is the ember fill.
struct PresetChip: View {
    let title: String
    let detail: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                Text(detail).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .frame(minWidth: 74, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .foregroundStyle(active ? Theme.background : Theme.text)
            .background(active ? Theme.ember : Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
