import SwiftUI

enum Units: String, CaseIterable {
    case f = "F", c = "C"
}

/// User settings kept on this phone.
enum Prefs {
    static let units = "units"
    static let heatColorsNumber = "heatColorsNumber"
}

/// Formats a Fahrenheit value in the chosen units, rounded.
func formatTemp(_ f: Int?, _ units: Units) -> String {
    guard let f else { return "—" }
    return units == .f ? "\(f)" : "\(Int((Double(f - 32) * 5 / 9).rounded()))"
}
