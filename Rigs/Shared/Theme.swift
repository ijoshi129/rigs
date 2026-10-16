import SwiftUI

/// Dr. Dabber palette: near-black, graphite surfaces, and the rig's LED cyan
/// as the only accent. Geist at light weights; corners are square.
enum Theme {
    static let background = Color(hex: 0x050608)
    static let surface = Color(hex: 0x101115)
    static let surfaceStrong = Color(hex: 0x26282E)
    static let line = Color(hex: 0x1D1F24)
    static let control = Color(hex: 0x15171B)
    static let controlBorder = Color(hex: 0x34373E)
    static let sheet = Color(hex: 0x121317)

    static let ink = Color.white
    static let ink2 = Color(hex: 0x8B8E97)
    static let ink3 = Color(hex: 0x5A5D65)

    static let accent = Color(hex: 0x00E1ED)
    static let onAccent = Color(hex: 0x04161A)
    static let error = Color(hex: 0xFF7A6B)

    /// Color for a temperature: slate when cold, then rust → ember → amber → white-hot.
    static func heat(_ fahrenheit: Double) -> Color {
        let stops: [(Double, (Double, Double, Double))] = [
            (100, (74, 84, 105)),
            (300, (122, 46, 18)),
            (450, (232, 118, 43)),
            (580, (255, 197, 107)),
            (700, (255, 243, 214)),
        ]
        let f = min(max(fahrenheit, stops.first!.0), stops.last!.0)
        for i in 1..<stops.count where f <= stops[i].0 {
            let (f0, c0) = stops[i - 1], (f1, c1) = stops[i]
            let t = (f - f0) / (f1 - f0)
            func mix(_ a: Double, _ b: Double) -> Double { (a + (b - a) * t) / 255 }
            return Color(red: mix(c0.0, c1.0), green: mix(c0.1, c1.1), blue: mix(c0.2, c1.2))
        }
        let last = stops.last!.1
        return Color(red: last.0 / 255, green: last.1 / 255, blue: last.2 / 255)
    }

    /// The Switch 2's LED modes as color pairs, for the swatches on the Lights screen.
    static let lightModeColors: [UInt8: (UInt32, UInt32)] = [
        0: (0x3A3F4A, 0x1D2430), 1: (0xD9D4C7, 0x8A8577), 2: (0x8A3FFC, 0x4A1D8A), 3: (0x2F6BFF, 0x1D2F8A),
        4: (0x22C7E6, 0x0F4D5A), 5: (0x3CCF6A, 0x0F4D3A), 6: (0xF4D13D, 0x8A6B0F), 7: (0xFF8A2B, 0x8A3A0F),
        8: (0xE8383D, 0x6A0F1D), 9: (0xFF5FB0, 0x8A1D5A), 10: (0xFF8A2B, 0x8B2FD6), 11: (0x5B2CC9, 0xC04BFF),
        12: (0x0FA38A, 0x6A3BE0), 13: (0xFF2D95, 0x22C7E6), 14: (0x2F6BFF, 0x9AD5FF), 15: (0xE8383D, 0xFF9BB3),
        16: (0xFF8A2B, 0x3CCF6A), 17: (0xB7FF3D, 0x3CCF6A), 24: (0x2F6BFF, 0xF4D13D), 25: (0xF4D13D, 0xFF8A2B),
        26: (0x8A3FFC, 0x3CCF6A), 27: (0xFF2D95, 0x22C7E6), 28: (0x5B2CC9, 0xFF5FB0), 29: (0xFF8A2B, 0xF4D13D),
        30: (0xE8383D, 0x3A0F0F), 31: (0xD9D4C7, 0x3A3F4A), 32: (0x3CCF6A, 0x5B2CC9), 33: (0xFF8A2B, 0x1D0F0A),
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Type

enum GeistWeight {
    case extraLight, light, regular, medium

    var name: String {
        switch self {
        case .extraLight: "Geist-ExtraLight"
        case .light: "Geist-Light"
        case .regular: "Geist-Regular"
        case .medium: "Geist-Medium"
        }
    }
}

extension Font {
    static func geist(_ size: CGFloat, _ weight: GeistWeight = .regular) -> Font {
        .custom(weight.name, fixedSize: size)
    }
}

/// Small all-caps section label.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.geist(12))
            .tracking(1.2)
            .foregroundStyle(Theme.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 28)
            .padding(.bottom, 10)
    }
}
