import Foundation

/// What `nordvpn status --json` reports.
public struct StatusReport: Encodable, Sendable {
    public let vpn: VPNSnapshot?
    public let server: String?
    public let lastTarget: String?
    public let publicIP: IPInsights?

    /// The public IP is left out when NordVPN's API cannot be reached.
    public static func current() async -> StatusReport {
        let vpn = VPNService.current()
        let insights = try? await NordAPI().insights()
        let server = vpn?.state == .connected ? NordApp.lastServerName() : nil
        return StatusReport(vpn: vpn, server: server, lastTarget: NordApp.lastConnectionKey, publicIP: insights)
    }
}

public struct ConnectionFailure: LocalizedError {
    public let outcome: ConnectionOutcome

    public var errorDescription: String? {
        switch outcome {
        case .tunnelUnverified:
            "The tunnel connected, but public IP verification failed. Check `nordvpn ip` or `nordvpn doctor`."
        case .wrongCountry:
            "The VPN is connected, but the public IP does not match the requested country. Check the app."
        case .unprotected:
            "The tunnel connected, but NordVPN reports the public IP as unprotected. Check the app."
        case .timedOut:
            "Connection was not confirmed before the timeout. Check the NordVPN app."
        case .verified:
            "Connection verification failed unexpectedly."
        }
    }
}

public struct VerifiedConnection: Sendable {
    /// Nil when the app's log is unreadable.
    public let server: String?
    public let publicIP: IPInsights
}

/// One connection request, from the deep link to a verified tunnel.
public struct ConnectionRequest {
    private let log: AppLog?
    private let countryCode: String?

    /// Asks the app to connect. The app's log is opened first, so `verify` sees every line written for this request.
    public static func submit(countryCode: String?) async throws -> ConnectionRequest {
        let log = AppLog()
        try await NordApp.connect(countryCode: countryCode)
        return ConnectionRequest(log: log, countryCode: countryCode)
    }

    /// Waits until the tunnel is up and NordVPN reports the public IP as protected, in the requested
    /// country if there is one. `timeout` covers both checks.
    public func verify(within timeout: TimeInterval) async throws -> VerifiedConnection {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        var outcome = ConnectionOutcome.timedOut
        while clock.now < deadline {
            try Task.checkCancellation()
            log?.poll()
            if tunnelConnected {
                let remaining = clock.now.duration(to: deadline).components
                let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
                guard seconds > 0 else { break }
                let insights: IPInsights?
                do {
                    insights = try await NordAPI().insights(timeout: min(10, seconds))
                } catch {
                    try Task.checkCancellation()
                    insights = nil
                }
                log?.poll()
                outcome = ConnectionEvidence.outcome(
                    tunnelConnected: tunnelConnected, protected: insights?.protected,
                    expectedCountry: countryCode, observedCountry: insights?.countryCode)
                if outcome == .verified, let insights {
                    guard clock.now <= deadline else { throw ConnectionFailure(outcome: .timedOut) }
                    return VerifiedConnection(server: log?.server, publicIP: insights)
                }
            } else {
                outcome = .timedOut
            }
            try await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(500))))
        }
        throw ConnectionFailure(outcome: outcome)
    }

    /// The app's log tells when a server switch inside a connected tunnel finishes; the system state cannot.
    private var tunnelConnected: Bool {
        log.map { $0.state == .connected } ?? (VPNService.current()?.state == .connected)
    }
}

public enum DisconnectOutcome: Sendable {
    case alreadyDisconnected, disconnected
}

extension NordApp {
    /// Presses the app's "Disconnect" control, then waits up to `timeout` for the tunnel to close.
    public static func disconnect(waitingUpTo timeout: TimeInterval) async throws -> DisconnectOutcome {
        guard url != nil else { throw NordAppError.notInstalled }
        guard let before = VPNService.current() else { throw NordAppError.noProfile }
        if before.state == .disconnected { return .alreadyDisconnected }
        try disconnect()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(400))
            if VPNService.current()?.state == .disconnected { return .disconnected }
        }
        throw NordAppError.stillConnected(after: timeout)
    }
}
