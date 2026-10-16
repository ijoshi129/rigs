import Foundation
import Observation

/// One logged heat cycle.
struct SessionEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let start: Date
    var end: Date?
    var targetF: Int?
    var profile: String?
    var holdSeconds: Int?
    var peakF: Int
    var extended = false
}

/// The session history, kept on this phone only.
@MainActor @Observable
final class SessionLog {
    private(set) var entries: [SessionEntry] = []
    private var open: SessionEntry?
    private var wasHeating = false
    private let key = "rigs.history"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([SessionEntry].self, from: data) {
            entries = saved
        }
    }

    /// Feed every status update. Opens an entry when heating starts and
    /// closes it when heating stops.
    func track(heating: Bool, fahrenheit: Int?, details: () -> (targetF: Int?, profile: String?, hold: Int?, extended: Bool)) {
        let was = wasHeating
        wasHeating = heating
        if heating, !was {
            let d = details()
            open = SessionEntry(id: UUID(), start: .now, targetF: d.targetF, profile: d.profile, holdSeconds: d.hold, peakF: fahrenheit ?? 0)
            return
        }
        if heating, var entry = open {
            if let f = fahrenheit, f > entry.peakF { entry.peakF = f }
            if details().extended { entry.extended = true }
            open = entry
            return
        }
        if !heating, was, var entry = open {
            entry.end = .now
            open = nil
            // A two-second abort is noise; keep sessions that got warm or ran a while.
            if entry.peakF >= 200 || entry.end!.timeIntervalSince(entry.start) > 10 {
                entries = Array(([entry] + entries).prefix(500))
                save()
            }
        }
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}
