import Foundation
import SystemConfiguration

/// Connection state of a system VPN service, as reported by SystemConfiguration.
public enum VPNState: String, Codable, Sendable {
    case invalid, disconnected, connecting, connected, disconnecting

    init(_ status: SCNetworkConnectionStatus) {
        switch status {
        case .disconnected: self = .disconnected
        case .connecting: self = .connecting
        case .connected: self = .connected
        case .disconnecting: self = .disconnecting
        default: self = .invalid
        }
    }
}

public struct VPNSnapshot: Codable, Sendable {
    public let serviceID: String
    public let name: String
    public let state: VPNState
    public let interface: String?
    public let tunnelAddress: String?
    public let since: Date?
    public let onDemand: Bool
}

/// A VPN profile that the NordVPN app registered with the system (one per protocol: NordLynx, OpenVPN, NordWhisper).
public struct VPNService: Sendable {
    public static let providerBundleID = "com.nordvpn.NordVPN"

    public let id: String
    public let name: String

    /// All VPN services created by the NordVPN app.
    public static func all() -> [VPNService] {
        guard let prefs = SCPreferencesCreate(nil, "nordvpn-cli" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else { return [] }
        return services.compactMap { service in
            guard let outer = SCNetworkServiceGetInterface(service),
                  let inner = SCNetworkInterfaceGetInterface(outer),
                  let subtype = SCNetworkInterfaceGetInterfaceType(inner) as String?,
                  subtype == providerBundleID,
                  let id = SCNetworkServiceGetServiceID(service) as String? else { return nil }
            return VPNService(id: id, name: (SCNetworkServiceGetName(service) as String?) ?? "NordVPN")
        }
    }

    /// State of the NordVPN profile that matters right now: connected beats transitioning beats idle.
    /// Profiles are per protocol, so a protocol switch can move the tunnel to another one.
    public static func current() -> VPNSnapshot? {
        let rank: [VPNState: Int] = [.connected: 0, .connecting: 1, .disconnecting: 1, .disconnected: 2, .invalid: 3]
        return all().map { $0.snapshot() }.min { rank[$0.state]! < rank[$1.state]! }
    }

    public func snapshot() -> VPNSnapshot {
        guard let connection = SCNetworkConnectionCreateWithServiceID(nil, id as CFString, nil, nil) else {
            return VPNSnapshot(serviceID: id, name: name, state: .invalid,
                               interface: nil, tunnelAddress: nil, since: nil, onDemand: false)
        }
        let state = VPNState(SCNetworkConnectionGetStatus(connection))
        let extended = SCNetworkConnectionCopyExtendedStatus(connection) as? [String: Any] ?? [:]
        let ipv4 = extended["IPv4"] as? [String: Any]
        let options = (extended["StartMessage"] as? [String: Any])?["SessionOptions"] as? [String: Any]
        return VPNSnapshot(
            serviceID: id,
            name: name,
            state: state,
            interface: ipv4?["InterfaceName"] as? String,
            tunnelAddress: (ipv4?["Addresses"] as? [String])?.first,
            since: state == .connected ? extended["LastStatusChangeTime"] as? Date : nil,
            onDemand: (options?["is-on-demand"] as? Bool) ?? false
        )
    }
}
