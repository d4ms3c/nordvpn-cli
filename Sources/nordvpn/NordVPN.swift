import ArgumentParser
import Foundation
import NordVPNKit

@main
struct NordVPN: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nordvpn",
        abstract: "Control the NordVPN macOS app from the terminal.",
        discussion: """
        Connections go through the installed NordVPN.app, which stays in charge of your account, \
        protocol, kill switch and auto-connect settings. Server lists come from NordVPN's public API.

        Quick start:
          nordvpn                          show status (same as `nordvpn status`)
          nordvpn connect                  connect to the fastest server
          nordvpn connect italy            connect to a country (code, name or city)
          nordvpn disconnect               disconnect
          nordvpn countries                list where you can connect
          nordvpn servers pl --group p2p   least loaded P2P servers in Poland

        Limits of the app: only a country can be chosen (not a city, group or server), and \
        `disconnect` needs Accessibility access for your terminal in System Settings > \
        Privacy & Security > Accessibility.
        """,
        version: "0.2.0",
        subcommands: [Status.self, Connect.self, Disconnect.self, Countries.self, Cities.self,
                      Servers.self, IP.self, Open.self, Doctor.self],
        defaultSubcommand: Status.self
    )
}

// MARK: - status

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the VPN state, server and public IP.",
        discussion: """
        Examples:
          nordvpn status
          nordvpn status --json | jq -r .publicIP.ip
        """
    )

    @Flag(help: "Print machine-readable JSON.") var json = false

    struct Report: Encodable {
        let vpn: VPNSnapshot?
        let server: String?
        let lastTarget: String?
        let publicIP: IPInsights?
    }

    func run() async throws {
        let vpn = VPNService.current()
        let insights = try? await NordAPI().insights()
        let server = vpn?.state == .connected ? NordApp.lastServerName() : nil
        if json {
            return try printJSON(Report(vpn: vpn, server: server, lastTarget: NordApp.lastConnectionKey, publicIP: insights))
        }
        guard let vpn else {
            stderr(NordApp.url == nil ? "NordVPN.app is not installed." : "No NordVPN VPN profile found. Open the app and connect once.")
            throw ExitCode.failure
        }
        printRows([
            ("Status", vpn.state.styled),
            ("Server", server),
            ("Location", insights.map { [$0.city, $0.country].compactMap { $0 }.joined(separator: ", ") }),
            ("Public IP", insights.map { $0.protected ? Style.green($0.ip) : Style.red("\($0.ip) (not protected)") }),
            ("Profile", "\(vpn.name) \(Style.dim("(\(vpn.interface ?? "-"))"))"),
            ("Uptime", vpn.since.map(formatDuration(since:))),
            ("ISP", insights?.isp),
        ])
    }
}

// MARK: - connect

struct Connect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Connect to the fastest server, or to a country.",
        discussion: """
        LOCATION can be a country code (pl, us, uk), a country name (Italy, "united states") or a city \
        (Warsaw). The app only accepts a country, so a city connects to the fastest server of its country.

        Examples:
          nordvpn connect
          nordvpn connect italy
          nordvpn connect united states
        """
    )

    @Argument(help: "Country code, country name or city. Empty for quick connect.")
    var location: [String] = []

    @Flag(name: .long, help: "Return right after asking the app to connect.")
    var noWait = false

    @Option(help: "Seconds to wait for the connection.") var timeout: Double = 30

    mutating func validate() throws {
        guard timeout.isFinite, timeout > 0, timeout <= 3600 else {
            throw ValidationError("Timeout must be between 0 and 3600 seconds (exclusive of 0).")
        }
    }

    func run() async throws {
        let api = NordAPI()
        var country: Country?
        if !location.isEmpty {
            let resolved = try LocationResolver.resolve(location.joined(separator: " "), in: try await api.countries())
            country = resolved.country
            if case let .city(city, in: parent) = resolved {
                stderr(Style.yellow("The app cannot pick a city: connecting to the fastest server in \(parent.name), not specifically \(city.name)."))
            }
        }

        let log = AppLog()
        try await NordApp.connect(countryCode: country?.code)
        print("Connecting to \(Style.bold(country?.name ?? "the fastest server"))…")
        if noWait { return }

        let insights = try await waitForConnection(log: log, country: country)
        let server = log?.server ?? country?.name ?? "NordVPN"
        print("\(Style.green("Connected")) to \(Style.bold(server)) · \(insights.ip)")
    }

    private func waitForConnection(log: AppLog?, country: Country?) async throws -> IPInsights {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        var outcome = ConnectionOutcome.timedOut
        while clock.now < deadline {
            try Task.checkCancellation()
            log?.poll()
            let tunnelConnected = log.map { $0.state == .connected }
                ?? (VPNService.current()?.state == .connected)
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
                let stillConnected = log.map { $0.state == .connected }
                    ?? (VPNService.current()?.state == .connected)
                outcome = ConnectionEvidence.outcome(
                    tunnelConnected: stillConnected, protected: insights?.protected,
                    expectedCountry: country?.code, observedCountry: insights?.countryCode)
                if outcome == .verified, let insights {
                    guard clock.now <= deadline else { throw ConnectionFailure(outcome: .timedOut) }
                    return insights
                }
            } else {
                outcome = .timedOut
            }
            try await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(500))))
        }
        throw ConnectionFailure(outcome: outcome)
    }
}

struct ConnectionFailure: LocalizedError {
    let outcome: ConnectionOutcome

    var errorDescription: String? {
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

// MARK: - disconnect

struct Disconnect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Disconnect the VPN.",
        discussion: """
        The app has no deep link for disconnecting, so this presses "Disconnect" in its menu bar \
        or Dock menu. Your terminal needs Accessibility access: System Settings > Privacy & Security > \
        Accessibility.

        Examples:
          nordvpn disconnect
          nordvpn disconnect --timeout 30
        """
    )

    @Option(help: "Seconds to wait for the tunnel to close.") var timeout: Double = 15

    mutating func validate() throws {
        guard timeout.isFinite, timeout > 0, timeout <= 3600 else {
            throw ValidationError("Timeout must be between 0 and 3600 seconds (exclusive of 0).")
        }
    }

    func run() async throws {
        guard NordApp.url != nil else { throw NordAppError.notInstalled }
        guard let before = VPNService.current() else {
            throw NordAppError.noProfile
        }
        if before.state == .disconnected {
            print("Already disconnected.")
            return
        }
        try NordApp.disconnect()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(400))
            if VPNService.current()?.state == .disconnected {
                print(Style.red("Disconnected"))
                return
            }
        }
        stderr(Style.yellow("Asked the app to disconnect, but the tunnel is still up after \(Int(timeout))s."))
        throw ExitCode.failure
    }
}

// MARK: - countries / cities / servers

struct Countries: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the countries with NordVPN servers.",
        discussion: """
        Examples:
          nordvpn countries
          nordvpn countries united
          nordvpn countries --refresh --json
        """
    )

    @Argument(help: "Show only countries whose name or code contains this text.") var filter: String?
    @Flag(help: "Ignore the one-day cache.") var refresh = false
    @Flag(help: "Print machine-readable JSON.") var json = false

    func run() async throws {
        var countries = try await NordAPI().countries(refresh: refresh)
        if let filter = filter?.lowercased() {
            countries = countries.filter { $0.name.lowercased().contains(filter) || $0.code.lowercased() == filter }
        }
        if json { return try printJSON(countries) }
        let width = countries.map(\.name.count).max() ?? 0
        for country in countries {
            let cities = country.cities.count == 1 ? "1 city" : "\(country.cities.count) cities"
            print("\(Style.bold(country.code))  \(country.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(Style.dim("\(country.serverCount) servers, \(cities)"))")
        }
    }
}

struct Cities: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the cities of a country.",
        discussion: """
        Examples:
          nordvpn cities uk
          nordvpn cities united states
        """
    )

    @Argument(help: "Country code or name.") var country: [String]

    func run() async throws {
        let resolved = try LocationResolver.resolve(country.joined(separator: " "), in: try await NordAPI().countries()).country
        print(Style.bold(resolved.name))
        for city in resolved.cities.sorted(by: { $0.name < $1.name }) {
            print("  \(city.name) \(Style.dim("(\(city.serverCount) servers)"))")
        }
    }
}

enum ServerGroup: String, ExpressibleByArgument, CaseIterable {
    case standard, p2p, double, onion, obfuscated, dedicated

    var identifier: String {
        switch self {
        case .standard: "legacy_standard"
        case .p2p: "legacy_p2p"
        case .double: "legacy_double_vpn"
        case .onion: "legacy_onion_over_vpn"
        case .obfuscated: "legacy_obfuscated_servers"
        case .dedicated: "legacy_dedicated_ip"
        }
    }
}

struct Servers: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the least loaded servers, optionally in a country or group.",
        discussion: """
        Informational: the app picks the actual server, and cannot be told to use a specific one.

        Examples:
          nordvpn servers
          nordvpn servers germany --limit 5
          nordvpn servers us --group p2p
        """
    )

    @Argument(help: "Country code, name or city.") var location: [String] = []
    @Option(help: "Server group.") var group: ServerGroup?
    @Option(help: "Number of servers.") var limit = 10
    @Flag(help: "Print machine-readable JSON.") var json = false

    func run() async throws {
        let api = NordAPI()
        let country = location.isEmpty ? nil
            : try LocationResolver.resolve(location.joined(separator: " "), in: try await api.countries()).country
        let servers = try await api.recommendations(countryID: country?.id, group: group?.identifier, limit: limit)
        if json { return try printJSON(servers) }
        if servers.isEmpty { return print("No servers found.") }
        let width = servers.map(\.name.count).max() ?? 0
        for server in servers {
            let load = "\(server.load)%".padding(toLength: 4, withPad: " ", startingAt: 0)
            let styledLoad = server.load < 40 ? Style.green(load) : server.load < 70 ? Style.yellow(load) : Style.red(load)
            print("\(server.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(styledLoad)  \(Style.dim([server.cityName, server.hostname].compactMap { $0 }.joined(separator: " · ")))")
        }
    }
}

// MARK: - ip / open

struct IP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ip",
        abstract: "Show your public IP and whether NordVPN protects it.",
        discussion: """
        Examples:
          nordvpn ip
          nordvpn ip --json
        """
    )

    @Flag(help: "Print machine-readable JSON.") var json = false

    func run() async throws {
        let insights = try await NordAPI().insights()
        if json { return try printJSON(insights) }
        printRows([
            ("IP", insights.ip),
            ("Protected", insights.protected ? Style.green("yes") : Style.red("no")),
            ("Location", [insights.city, insights.country].compactMap { $0 }.joined(separator: ", ")),
            ("ISP", insights.isp),
        ])
    }
}

struct Open: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Bring the NordVPN app to the front.")

    func run() async throws {
        try await NordApp.launch()
    }
}
