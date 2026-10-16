import Foundation

/// Launch arguments for screenshots in Debug builds: `-tab presets`,
/// `-open settings`, `-open help`, `-open diagnostics`, `-open preset:2`. Release builds ignore them.
enum DebugLaunch {
    static var open: String? { value(after: "-open") }
    static var tab: Tab? { value(after: "-tab").flatMap { Tab(rawValue: $0.capitalized) } }
    static var presetToEdit: Int? {
        guard let o = open, o.hasPrefix("preset:") else { return nil }
        return Int(o.dropFirst(7))
    }

    private static func value(after flag: String) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
        #else
        return nil
        #endif
    }
}
