import SwiftUI

/// The round button with a glowing cyan ring, after the rig's power button.
struct RingButton<Icon: View>: View {
    var size: CGFloat = 78
    var enabled = true
    @ViewBuilder var icon: Icon

    var body: some View {
        ZStack {
            Circle().fill(Theme.control)
            Circle()
                .strokeBorder(enabled ? Theme.accent : Theme.controlBorder, lineWidth: 2.5)
                .shadow(color: enabled ? Theme.accent.opacity(0.55) : .clear, radius: 11)
            icon.foregroundStyle(enabled ? Theme.accent : Theme.ink3)
        }
        .frame(width: size, height: size)
    }
}

struct PowerGlyph: View {
    var body: some View {
        Image(systemName: "power").font(.system(size: 28, weight: .medium))
    }
}

struct StopGlyph: View {
    var body: some View {
        Rectangle().frame(width: 16, height: 16)
    }
}

/// The +/− rocker, after the one on the rig.
struct Rocker: View {
    var plusLabel: String
    var minusLabel: String
    var canPlus: Bool
    var canMinus: Bool
    var onPlus: () -> Void
    var onMinus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            half("+", plusLabel, canPlus, onPlus)
            half("−", minusLabel, canMinus, onMinus)
        }
        .frame(width: 52, height: 96)
        .background(Capsule().fill(Theme.control))
        .overlay(Capsule().strokeBorder(Theme.controlBorder, lineWidth: 1.5))
    }

    private func half(_ glyph: String, _ label: String, _ enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.geist(26, .light))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}

/// Shrinks a little while pressed, like the web app's buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// A flat, square-cornered surface with a hairline border.
struct Surface<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, padding)
            .background(Theme.surface)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// One row inside a `Surface`: title, optional detail, trailing control.
struct Row<Trailing: View>: View {
    let title: String
    var detail: String?
    var last = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.geist(15))
                if let detail { Text(detail).font(.geist(12)).foregroundStyle(Theme.ink2) }
            }
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: 54)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { if !last { Theme.line.frame(height: 1) } }
    }
}

/// A square on/off switch.
struct SquareToggle: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle().fill(isOn ? Theme.accent : Theme.line)
                Rectangle().fill(.white).frame(width: 28, height: 28).padding(2)
            }
            .frame(width: 52, height: 32)
            .animation(.easeOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// A square −/value/+ stepper.
struct SquareStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    var step = 1
    let label: String
    var format: (Int) -> String = { "\($0)" }
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            button("−", enabled: value > range.lowerBound) { onChange(max(range.lowerBound, value - step)) }
                .accessibilityLabel("\(label): less")
            Text(format(value)).font(.geist(15, .medium)).monospacedDigit().frame(minWidth: 56)
            button("+", enabled: value < range.upperBound) { onChange(min(range.upperBound, value + step)) }
                .accessibilityLabel("\(label): more")
        }
        .padding(3)
        .frame(height: 36)
        .background(Theme.line)
    }

    private func button(_ glyph: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(.geist(18)).frame(width: 36, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Square segmented control, e.g. °F / °C.
struct SquareSegmented<T: Hashable>: View {
    let options: [T]
    let selection: T
    let label: (T) -> String
    let onSelect: (T) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                Button { onSelect(o) } label: {
                    Text(label(o))
                        .font(.geist(15, o == selection ? .medium : .regular))
                        .foregroundStyle(o == selection ? Theme.ink : Theme.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(o == selection ? Theme.surfaceStrong : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(height: 44)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A small square button on a graphite fill (Manage, Forget, Rename…).
struct SmallButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.geist(14, prominent ? .medium : .regular))
                .foregroundStyle(prominent ? Theme.onAccent : Theme.ink)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(prominent ? Theme.accent : Theme.surfaceStrong)
        }
        .buttonStyle(.pressable)
    }
}

/// Large title with an optional subtitle and back button, for the secondary screens.
struct ScreenHeader: View {
    let title: String
    var subtitle: String?
    var showsBack = false
    var trailing: AnyView?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsBack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(Theme.surface)
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .foregroundStyle(Theme.ink)
                .accessibilityLabel("Back")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.geist(34, .light)).tracking(-1)
                if let subtitle { Text(subtitle).font(.geist(14)).foregroundStyle(Theme.ink2) }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.bottom, 20)
    }
}
