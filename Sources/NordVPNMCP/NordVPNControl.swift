import Foundation
import NordVPNKit

/// What the tools need from the NordVPN app and API. Tests substitute a fake, so they never touch the VPN.
public protocol NordVPNControl: Sendable {
    func status() async -> StatusReport
    func countries() async throws -> [Country]
    func servers(countryID: Int?, group: ServerGroup?, limit: Int) async throws -> [Server]
    func diagnostics(offline: Bool) async -> [DiagnosticCheck]
    /// Submits a connection request and, given a timeout, waits until it is verified; without one it returns nil.
    func connect(countryCode: String?, verifyingWithin timeout: TimeInterval?) async throws -> VerifiedConnection?
    func disconnect(waitingUpTo timeout: TimeInterval) async throws -> DisconnectOutcome
}

/// The installed NordVPN app and NordVPN's public API.
public struct LiveNordVPN: NordVPNControl {
    public init() {}

    public func status() async -> StatusReport {
        await StatusReport.current()
    }

    public func countries() async throws -> [Country] {
        try await NordAPI().countries()
    }

    public func servers(countryID: Int?, group: ServerGroup?, limit: Int) async throws -> [Server] {
        try await NordAPI().recommendations(countryID: countryID, group: group?.identifier, limit: limit)
    }

    public func diagnostics(offline: Bool) async -> [DiagnosticCheck] {
        await Diagnostics.run(offline: offline)
    }

    public func connect(countryCode: String?, verifyingWithin timeout: TimeInterval?) async throws -> VerifiedConnection? {
        let request = try await ConnectionRequest.submit(countryCode: countryCode)
        guard let timeout else { return nil }
        return try await request.verify(within: timeout)
    }

    public func disconnect(waitingUpTo timeout: TimeInterval) async throws -> DisconnectOutcome {
        try await NordApp.disconnect(waitingUpTo: timeout)
    }
}

/// Runs operations one at a time, each after the previous one has finished.
actor SerialQueue {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = await task.result }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
