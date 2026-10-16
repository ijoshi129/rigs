import Foundation

/// An in-memory `BLETransport`. A simulator installs `onWrite`/`onRead`
/// handlers and pushes notifications with `emit`.
public final class MockTransport: BLETransport, @unchecked Sendable {
    private let lock = NSLock()
    private var streams: [UUID: AsyncStream<Data>.Continuation] = [:]
    private var open = true

    public var onWrite: (@Sendable (UUID, Data) async throws -> Void)?
    public var onRead: (@Sendable (UUID) async throws -> Data)?
    public var onDisconnect: (@Sendable () async -> Void)?

    public init() {}

    public func subscribe(to characteristic: UUID) async throws -> AsyncStream<Data> {
        let (stream, cont) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        lock.withLock {
            streams[characteristic]?.finish()
            streams[characteristic] = cont
        }
        return stream
    }

    public func write(_ data: Data, to characteristic: UUID, withResponse: Bool) async throws {
        guard lock.withLock({ open }) else { throw RigKitError.notConnected }
        try await onWrite?(characteristic, data)
    }

    public func read(from characteristic: UUID) async throws -> Data {
        guard lock.withLock({ open }) else { throw RigKitError.notConnected }
        guard let onRead else { throw RigKitError.unsupported("read \(characteristic)") }
        return try await onRead(characteristic)
    }

    public func disconnect() async {
        let conts = lock.withLock {
            open = false
            let c = Array(streams.values)
            streams.removeAll()
            return c
        }
        conts.forEach { $0.finish() }
        await onDisconnect?()
    }

    /// Drops the link as if the rig went out of range: streams end and
    /// writes fail, without the `onDisconnect` hook a requested disconnect runs.
    public func dropLink() {
        let conts = lock.withLock {
            open = false
            let c = Array(streams.values)
            streams.removeAll()
            return c
        }
        conts.forEach { $0.finish() }
    }

    /// Brings a dropped link back, for reconnect tests.
    public func reopen() {
        lock.withLock { open = true }
    }

    /// Pushes a notification to whoever subscribed to `characteristic`.
    public func emit(_ data: Data, on characteristic: UUID) {
        lock.withLock { streams[characteristic] }?.yield(data)
    }

    public var isOpen: Bool { lock.withLock { open } }
}
