import Foundation

/// Follows the NordVPN app's log from the moment it is created. The system VPN status is no use for
/// telling when a server switch finishes: NordLynx swaps servers inside a tunnel that stays "connected".
public final class AppLog {
    public enum State: String, Sendable {
        case initiating, connecting, connected, disconnecting, disconnected
    }

    public private(set) var state: State?
    public private(set) var server: String?

    private let handle: FileHandle
    private var pending = ""

    /// Nil when the log cannot be read; callers then fall back to the public IP check.
    public init?() {
        guard let url = NordApp.latestAppLog(), let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        self.handle = handle
        _ = try? handle.seekToEnd()
    }

    deinit { try? handle.close() }

    /// Reads what the app wrote since the last call and updates `state` and `server`.
    public func poll() {
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        pending += String(decoding: data, as: UTF8.self)
        var lines = pending.components(separatedBy: "\n")
        pending = lines.removeLast()
        for line in lines { Self.parse(line, into: &state, server: &server) }
    }

    static func parse(_ line: String, into state: inout State?, server: inout String?) {
        if let value = line.value(after: "> App state changed to "), let parsed = State(rawValue: value) {
            state = parsed
        } else if let value = line.value(after: "> Connecting to the ") {
            server = value
        }
    }
}

private extension String {
    func value(after marker: String) -> String? {
        range(of: marker).map { String(self[$0.upperBound...]).trimmingCharacters(in: .whitespaces) }
    }
}
