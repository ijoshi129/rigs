import Foundation
import RigKit
import UIKit

/// A rolling record of everything that happens on the Bluetooth link: state
/// changes, scans, connects, drops, and every packet each way, raw and decoded.
/// Kept in memory and mirrored to a file so it survives the app being killed.
/// Safe to call from any thread.
final class Diagnostics: @unchecked Sendable {
    static let shared = Diagnostics()

    enum Kind: String, Sendable {
        case app = "APP", ble = "BLE", tx = "TX", rx = "RX", error = "ERR"
        var isPacket: Bool { self == .tx || self == .rx }
    }

    struct Entry: Identifiable, Sendable {
        let id: Int
        let time: Date
        let kind: Kind
        let text: String
        /// Identical lines in a row collapse into one, counted here.
        var repeats = 1
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var nextID = 0
    private let limit = 10_000
    private let fileURL: URL
    private let io = DispatchQueue(label: "rigs.diagnostics")
    /// Text from earlier launches, read once at startup.
    private(set) var previousRuns = ""

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appending(path: "diagnostics.log")
        if let old = try? String(contentsOf: fileURL, encoding: .utf8) {
            // Keep the last ~400 KB of earlier runs.
            previousRuns = String(old.suffix(400_000))
            try? previousRuns.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    func record(_ kind: Kind, _ text: String) {
        let now = Date.now
        let line: String? = lock.withLock {
            if var last = entries.last, last.kind == kind, last.text == text {
                last.repeats += 1
                entries[entries.count - 1] = last
                return nil
            }
            entries.append(Entry(id: nextID, time: now, kind: kind, text: text))
            nextID += 1
            if entries.count > limit { entries.removeFirst(entries.count - limit) }
            return Self.format(time: now, kind: kind, text: text)
        }
        guard let line else { return }
        io.async { [fileURL] in
            guard let data = (line + "\n").data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: fileURL) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    func snapshot() -> [Entry] { lock.withLock { entries } }

    func clear() {
        lock.withLock { entries.removeAll() }
        previousRuns = ""
        io.async { [fileURL] in try? FileManager.default.removeItem(at: fileURL) }
    }

    /// The whole log as a text file for the share sheet, with a header.
    @MainActor func export(rig: Switch2Controller?) -> URL {
        var out = header(rig: rig)
        if !previousRuns.isEmpty {
            out += "\n== Earlier runs ==\n" + previousRuns
        }
        out += "\n== This run ==\n"
        for e in snapshot() {
            out += Self.format(time: e.time, kind: e.kind, text: e.text)
            if e.repeats > 1 { out += "  ×\(e.repeats)" }
            out += "\n"
        }
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
        let url = FileManager.default.temporaryDirectory.appending(path: "Rigs diagnostics \(stamp).txt")
        try? out.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor private func header(rig: Switch2Controller?) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        var lines = [
            "Rigs \(version) (\(build))",
            "\(Self.deviceModel) · iOS \(UIDevice.current.systemVersion)",
            "Exported \(Date.now.formatted(date: .abbreviated, time: .standard))",
        ]
        if let rig {
            let s = rig.state
            lines.append("Rig: \(rig.name) · \(rig.connected ? "connected" : "disconnected")")
            lines.append("Firmware: \(s.firmwareVersion ?? "?") / \(s.secondaryVersion ?? "?") · packets \(s.packetsReceived)")
            if let st = s.status {
                lines.append("Last status: \(Self.describe(.status(st)))")
            }
        } else {
            lines.append("Rig: none attached")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Formatting

    private static func format(time: Date, kind: Kind, text: String) -> String {
        "\(timeFormatter.string(from: time)) \(kind.rawValue.padding(toLength: 3, withPad: " ", startingAt: 0)) \(text)"
    }

    nonisolated(unsafe) static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Short names for the characteristics we talk to.
    static func name(_ uuid: UUID) -> String {
        let known: [UUID: String] = [
            Switch2.UUIDs.controlWrite: "FEC1", Switch2.UUIDs.controlNotify: "FEC2",
            Switch2.UUIDs.fallbackWrite: "fallback-write", Switch2.UUIDs.fallbackNotify: "fallback-notify",
            Switch2.UUIDs.goWrite: "go-write", Switch2.UUIDs.goNotify: "go-notify",
            Switch2.UUIDs.modelNumber: "model", Switch2.UUIDs.serialNumber: "serial",
            Switch2.UUIDs.hardwareRevision: "hw-rev", Switch2.UUIDs.softwareRevision: "sw-rev",
            Switch2.UUIDs.manufacturer: "manufacturer", Switch2.UUIDs.batteryLevel: "battery",
        ]
        return known[uuid] ?? shortUUID(uuid)
    }

    /// `0000FEE7-0000-1000-8000-00805F9B34FB` → `FEE7`.
    static func shortUUID(_ uuid: UUID) -> String {
        let s = uuid.uuidString
        return s.hasSuffix("-0000-1000-8000-00805F9B34FB") && s.hasPrefix("0000") ? String(s.dropFirst(4).prefix(4)) : s
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    /// A one-line reading of a packet from the rig.
    static func describe(_ m: Switch2.Message) -> String {
        switch m {
        case let .status(s):
            var parts = ["status", "preset \(s.activePreset)", "\(s.temperatureFahrenheit)°F"]
            parts.append(s.sessionActive ? "heating, \(s.sessionSecondsRemaining)s left" : "idle")
            if s.sessionExtend > 0 { parts.append("+\(s.sessionExtend * 10)s") }
            parts.append("battery \(s.batteryPercent)%\(s.charging ? " charging" : "")")
            parts.append("light \(s.lightMode) @\(s.brightness)%")
            return parts.joined(separator: " · ")
        case let .clock(y, mo, d, h, mi): return String(format: "clock %04d-%02d-%02d %02d:%02d", y, mo, d, h, mi)
        case let .presetTemperature(p, f, c): return "preset \(p) temp \(f)°F / \(c)°C"
        case let .presetProfile(p, prof): return "preset \(p) profile \(prof?.name ?? "unknown")"
        case let .presetHoldTime(p, s): return "preset \(p) hold \(s)s"
        case let .activePreset(p): return "active preset \(p)"
        case let .customCurve(p, start, pts):
            return "preset \(p) curve from #\(start + 1): " + pts.map { "\($0.seconds)s→\($0.fahrenheit)°F" }.joined(separator: ", ")
        case let .nameChunk(final, d): return "name chunk \"\(d.cleanString)\"\(final ? " (last)" : "")"
        case let .firmwareVersion(v): return "firmware \(v)"
        case let .secondaryVersion(v): return "secondary firmware \(v)"
        case let .hardware(h): return "hardware \(h)"
        case let .maintenance(clean, reset): return "maintenance cleaning=\(clean) reset=\(reset)"
        case let .analytics(a): return "analytics cycles=\(a.totalHeatingCycles.map(String.init) ?? "-") fav=\(a.favoriteTempF.map { "\($0)°F" } ?? "-")"
        case let .unknown(op, _): return "unknown opcode \(op)"
        }
    }
}

private extension Data {
    var cleanString: String {
        String(decoding: prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Wraps any `BLETransport` and records every call and packet in `Diagnostics`.
final class LoggingTransport: BLETransport, @unchecked Sendable {
    private let inner: any BLETransport
    private let log = Diagnostics.shared

    init(_ inner: any BLETransport) { self.inner = inner }

    func subscribe(to characteristic: UUID) async throws -> AsyncStream<Data> {
        let name = Diagnostics.name(characteristic)
        log.record(.ble, "subscribe \(name)")
        let upstream: AsyncStream<Data>
        do {
            upstream = try await inner.subscribe(to: characteristic)
        } catch {
            log.record(.error, "subscribe \(name) failed: \(error)")
            throw error
        }
        let (stream, cont) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        let log = log
        let pump = Task {
            for await packet in upstream {
                let decoded = Switch2.Message.parse(packet).map(Diagnostics.describe) ?? "unparsed"
                log.record(.rx, "\(name) \(Diagnostics.hex(packet))  ← \(decoded)")
                cont.yield(packet)
            }
            log.record(.ble, "\(name) stream ended")
            cont.finish()
        }
        cont.onTermination = { _ in pump.cancel() }
        return stream
    }

    func write(_ data: Data, to characteristic: UUID, withResponse: Bool) async throws {
        let name = Diagnostics.name(characteristic)
        log.record(.tx, "\(name) \(Diagnostics.hex(data))\(withResponse ? " (with response)" : "")")
        do {
            try await inner.write(data, to: characteristic, withResponse: withResponse)
        } catch {
            log.record(.error, "write \(name) failed: \(error)")
            throw error
        }
    }

    func read(from characteristic: UUID) async throws -> Data {
        let name = Diagnostics.name(characteristic)
        do {
            let value = try await inner.read(from: characteristic)
            log.record(.rx, "read \(name) \(Diagnostics.hex(value))")
            return value
        } catch {
            log.record(.error, "read \(name) failed: \(error)")
            throw error
        }
    }

    func disconnect() async {
        log.record(.ble, "disconnect requested")
        await inner.disconnect()
    }
}
