import Foundation

/// Launch arguments for screenshots in Debug builds: `-tab presets`,
/// `-open settings`, `-open help`, `-open diagnostics`, `-open activity`, `-open preset:2`. Release builds ignore them.
enum DebugLaunch {
    static var open: String? { value(after: "-open") }
    static var tab: Tab? { value(after: "-tab").flatMap { Tab(rawValue: $0.capitalized) } }
    static var presetToEdit: Int? {
        guard let o = open, o.hasPrefix("preset:") else { return nil }
        return Int(o.dropFirst(7))
    }

    /// `-intent start|stop|status|preset:N` runs that App Intent command after launch.
    static var intent: RigCommand? {
        switch value(after: "-intent") {
        case "start": .start(preset: nil)
        case "stop": .stop
        case "status": .status
        case let v? where v.hasPrefix("preset:"): Int(v.dropFirst(7)).map { .preset($0) }
        case let v? where v.hasPrefix("start:"): .start(preset: Int(v.dropFirst(6)))
        default: nil
        }
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
