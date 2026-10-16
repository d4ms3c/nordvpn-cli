import AppKit
import Foundation

public enum NordAppError: LocalizedError {
    case notInstalled
    case notRunning
    case noProfile
    case accessibilityDenied
    case disconnectItemNotFound
    case stillConnected(after: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            "NordVPN.app is not installed."
        case .noProfile:
            "No NordVPN VPN profile found. Open the app and connect once."
        case .notRunning:
            "NordVPN.app is not running. Start it with `nordvpn open`."
        case .accessibilityDenied:
            """
            The app has no deep link for disconnecting, so the CLI clicks "Disconnect" in its menu \
            and needs Accessibility access for your terminal: System Settings > Privacy & Security > \
            Accessibility, then enable your terminal app and run the command again.
            """
        case .disconnectItemNotFound:
            "Could not find a \"Disconnect\" control in the NordVPN menus. Is the VPN connected?"
        case let .stillConnected(seconds):
            "Asked the app to disconnect, but the tunnel is still up after \(Int(seconds))s."
        }
    }
}

/// Drives the installed NordVPN app. Connecting goes through its `nordvpn://connect` deep link;
/// disconnecting has no deep link, and stopping the system profile directly is undone by the
/// profile's on-demand rule, so the CLI uses the app's own "Disconnect" menu item.
public enum NordApp {
    public static let bundleID = "com.nordvpn.NordVPN"

    public static var url: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    public static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// `nordvpn://connect` quick-connects; `?country=pl` picks a country. The app ignores any other parameter.
    public static func connectURL(countryCode: String?) -> URL {
        var components = URLComponents()
        components.scheme = "nordvpn"
        components.host = "connect"
        if let countryCode {
            components.queryItems = [URLQueryItem(name: "country", value: countryCode.lowercased())]
        }
        return components.url!
    }

    public static func connect(countryCode: String?) async throws {
        try await open(connectURL(countryCode: countryCode))
    }

    public static func launch() async throws {
        guard let url else { throw NordAppError.notInstalled }
        let configuration = NSWorkspace.OpenConfiguration()
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Target of the last connection the app made, e.g. `country:pl:-:-:-` or `quick:-:-:-:-`.
    public static var lastConnectionKey: String? {
        CFPreferencesCopyAppValue("lastConnectionPrimaryKey" as CFString, bundleID as CFString) as? String
    }

    /// Server the app last connected to (e.g. "Poland #274"), read from the app's own log.
    public static func lastServerName() -> String? {
        guard let log = latestAppLog(), let handle = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 512_000 ? size - 512_000 : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        var state: AppLog.State?, server: String?
        for line in text.split(separator: "\n") { AppLog.parse(String(line), into: &state, server: &server) }
        return server
    }

    static func latestAppLog() -> URL? {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/W5W395V82Y.group.com.nordvpn/Library/Caches/Logs")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("NordVPN ") && $0.pathExtension == "log" }
            .max { modified($0) < modified($1) }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func open(_ url: URL) async throws {
        guard NordApp.url != nil else { throw NordAppError.notInstalled }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try await NSWorkspace.shared.open(url, configuration: configuration)
    }
}
