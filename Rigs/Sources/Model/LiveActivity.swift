import ActivityKit
import Foundation
import os
import RigKit
import SwiftUI

/// Starts a Live Activity when a session starts, keeps it current from the
/// rig's status packets, and ends it when heating stops.
@MainActor
final class LiveActivityController {
    private let log = Logger(subsystem: "org.monklabs.rigs", category: "LiveActivity")
    private var activity: Activity<RigActivityAttributes>?
    private var lastSent: RigActivityAttributes.ContentState?
    private var lastSentAt = Date.distantPast
    private var startF: Int?
    private var giveUp: Task<Void, Never>?
    /// How long a dropped link may stay "Reconnecting…" before the activity ends.
    private let lostGrace: Duration = .seconds(180)

    func update(_ state: Switch2.State, rigName: String) {
        guard let status = state.status else { return }
        let preset = state.activePresetSettings
        let target = preset?.fahrenheit ?? status.temperatureFahrenheit
        let hold = (preset?.holdSeconds ?? 30) + status.sessionExtend * 10

        giveUp?.cancel()
        giveUp = nil

        if !status.sessionActive {
            if activity != nil { end() }
            return
        }

        let f = status.temperatureFahrenheit
        if activity == nil { startF = f }
        let holding = f >= target - 5
        let content = RigActivityAttributes.ContentState(
            phase: holding ? .holding : .heating,
            temperatureF: f,
            targetF: target,
            holdEnds: holding && status.sessionSecondsRemaining > 0 ? Date.now.addingTimeInterval(Double(status.sessionSecondsRemaining)) : nil,
            holdSeconds: hold,
            startF: startF
        )

        if activity == nil {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                log.notice("Live Activities are turned off for Rigs")
                return
            }
            let units = UserDefaults.standard.string(forKey: Prefs.units) == Units.c.rawValue
            let attributes = RigActivityAttributes(rigName: rigName, profile: preset?.profile?.name ?? "Session", unitsCelsius: units)
            do {
                activity = try Activity.request(attributes: attributes, content: .init(state: content, staleDate: nil))
            } catch {
                log.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
            }
            lastSent = content
            lastSentAt = .now
            return
        }

        // The countdown ticks on its own; only send when something visible changes,
        // and the temperature at most once a second.
        guard let last = lastSent else { return }
        let phaseChanged = last.phase != content.phase || last.holdSeconds != content.holdSeconds
        let drift = abs((last.holdEnds?.timeIntervalSince1970 ?? 0) - (content.holdEnds?.timeIntervalSince1970 ?? 0)) > 2
        let tempChanged = last.temperatureF != content.temperatureF && Date.now.timeIntervalSince(lastSentAt) >= 1
        guard phaseChanged || drift || tempChanged else { return }
        lastSent = content
        lastSentAt = .now
        guard let id = activity?.id else { return }
        Task { await Self.push(id: id, content) }
    }

    /// The link dropped: show "Reconnecting…" and end the activity if the rig
    /// doesn't come back. The next status after a reconnect resumes it.
    func linkLost() {
        guard let id = activity?.id, var content = lastSent, content.phase != .lost else { return }
        content.phase = .lost
        content.holdEnds = nil
        lastSent = content
        lastSentAt = .now
        Task { await Self.push(id: id, content) }
        giveUp?.cancel()
        giveUp = Task { [weak self, lostGrace] in
            try? await Task.sleep(for: lostGrace)
            guard !Task.isCancelled else { return }
            self?.endLost()
        }
    }

    private func endLost() {
        guard let a = activity, let final = lastSent else { return }
        activity = nil
        lastSent = nil
        let id = a.id
        Task { await Self.finish(id: id, final) }
    }

    func end() {
        giveUp?.cancel()
        giveUp = nil
        guard let a = activity, var final = lastSent else { return }
        activity = nil
        lastSent = nil
        final.phase = .done
        final.holdEnds = nil
        let id = a.id
        Task { await Self.finish(id: id, final) }
    }

    // Activity isn't Sendable, so look it up by id off the main actor.
    private nonisolated static func find(_ id: String) -> Activity<RigActivityAttributes>? {
        Activity<RigActivityAttributes>.activities.first { $0.id == id }
    }

    private nonisolated static func push(id: String, _ content: RigActivityAttributes.ContentState) async {
        await find(id)?.update(.init(state: content, staleDate: nil))
    }

    private nonisolated static func finish(id: String, _ content: RigActivityAttributes.ContentState) async {
        await find(id)?.end(.init(state: content, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(8)))
    }
}
