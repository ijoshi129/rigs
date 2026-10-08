import Foundation

/// A minimal view of one connected BLE peripheral.
///
/// The app supplies a CoreBluetooth implementation; tests and the simulator
/// supply in-memory ones. Characteristics are addressed by their 128-bit UUID.
public protocol BLETransport: Sendable {
    /// Enables notifications on a characteristic and returns the stream of
    /// values the peripheral sends. The stream ends when the link drops.
    func subscribe(to characteristic: UUID) async throws -> AsyncStream<Data>

    /// Writes a value. `withResponse: false` maps to "write without response".
    func write(_ data: Data, to characteristic: UUID, withResponse: Bool) async throws

    /// Reads a characteristic value once.
    func read(from characteristic: UUID) async throws -> Data

    /// Tears the link down. Subscribed streams finish.
    func disconnect() async
}

public enum RigKitError: Error, Sendable, Equatable {
    case notConnected
    case invalidValue(String)
    case timeout
    case authenticationFailed(status: UInt8)
    case commandFailed(status: UInt8)
    case malformedPacket
    case unsupported(String)
}

/// Runs `body` and throws `RigKitError.timeout` if it has not finished in time.
func withTimeout<T: Sendable>(
    _ duration: Duration,
    _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw RigKitError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - Byte helpers

extension Data {
    var byteArray: [UInt8] { [UInt8](self) }

    func be16(_ i: Int) -> Int {
        guard i + 1 < count else { return 0 }
        return Int(self[startIndex + i]) << 8 | Int(self[startIndex + i + 1])
    }

    func be32(_ i: Int) -> Int {
        guard i + 3 < count else { return 0 }
        return be16(i) << 16 | be16(i + 2)
    }

    func byte(_ i: Int) -> UInt8 {
        guard i < count else { return 0 }
        return self[startIndex + i]
    }

    var leUInt16: UInt16? {
        guard count >= 2 else { return nil }
        return UInt16(byte(0)) | UInt16(byte(1)) << 8
    }

    var leUInt32: UInt32? {
        guard count >= 4 else { return nil }
        return UInt32(byte(0)) | UInt32(byte(1)) << 8 | UInt32(byte(2)) << 16 | UInt32(byte(3)) << 24
    }

    var leInt32: Int32? { leUInt32.map { Int32(bitPattern: $0) } }

    var leFloat32: Float? { leUInt32.map { Float(bitPattern: $0) } }

    static func le(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    static func le(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)])
    }
    static func le(_ v: Int32) -> Data { le(UInt32(bitPattern: v)) }
    static func le(_ v: Float) -> Data { le(v.bitPattern) }

    /// UTF-8 text with trailing NULs and whitespace removed.
    var cleanString: String {
        let trimmed = self.prefix { $0 != 0 }
        return String(decoding: trimmed, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

public enum Temperature {
    /// The exact integer conversion the Dr. Dabber app uses.
    public static func fahrenheitToCelsius(_ f: Int) -> Int { Int((Double(f - 32) * 5.0 / 9.0).rounded()) }
    public static func celsiusToFahrenheit(_ c: Int) -> Int { Int((Double(c) * 9.0 / 5.0 + 32.0).rounded()) }

    public static func fahrenheit(fromCelsius c: Double) -> Double { c * 9.0 / 5.0 + 32.0 }
    public static func celsius(fromFahrenheit f: Double) -> Double { (f - 32.0) * 5.0 / 9.0 }
}
