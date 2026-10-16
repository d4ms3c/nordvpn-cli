import Foundation
import NordVPNKit

/// The NordVPN tools. The reporting tools are read-only; connect and disconnect change the Mac's network,
/// so they carry destructive annotations, run one at a time and are left out in read-only mode.
public struct NordVPNTools: Sendable {
    public static let instructions = """
    Controls the NordVPN app on this Mac. Call nordvpn_get_status to answer questions about the VPN. \
    nordvpn_connect and nordvpn_disconnect change the network for every app on the Mac: call them only when \
    the user asks to connect or disconnect. Only a country can be targeted, not a city or a specific server.
    """

    /// Codex and other clients stop waiting for a tool after 60 seconds by default.
    static let maxWaitSeconds = 55
    static let characterLimit = 25_000
    static let nextSteps = "Next: call nordvpn_get_status to see the current state, or nordvpn_run_doctor to diagnose the setup."
    static let locationHint = "nordvpn_list_countries lists valid locations."
    static let accessibilityHint = """
    macOS checks the application that runs this MCP server (your terminal, Cursor, Claude, Codex…): enable that \
    app in System Settings > Privacy & Security > Accessibility, then restart it.
    """

    let control: any NordVPNControl
    private let changes = SerialQueue()

    public init(control: any NordVPNControl) {
        self.control = control
    }

    public func tools(readOnly: Bool) -> [Tool] {
        let reporting = [statusTool, countriesTool, serversTool, doctorTool]
        return readOnly ? reporting : reporting + [connectTool, disconnectTool]
    }

    /// The app connects by country only, so a city resolves to its country.
    func resolve(_ location: String) async throws -> ResolvedLocation {
        let countries = try await control.countries()
        do {
            return try LocationResolver.resolve(location, in: countries)
        } catch let error as LocationError {
            throw ToolFailure("\(error.localizedDescription) \(Self.locationHint)")
        }
    }
}

struct ToolFailure: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

// MARK: - Reporting tools

extension NordVPNTools {
    static let filter = TextParameter(
        name: "filter", description: "Keep countries whose name contains this text or whose code equals it", maxLength: 60)
    static let countryLimit = IntegerParameter(
        name: "limit", description: "Maximum number of countries to return", range: 1...200, fallback: 50)
    static let offset = IntegerParameter(
        name: "offset", description: "Number of countries to skip, for pagination", range: 0...10_000, fallback: 0)
    static let serverLocation = TextParameter(
        name: "location", description: "Country code (it, us, uk), country name (Italy, United States) or city (Warsaw)",
        maxLength: 60)
    static let group = ChoiceParameter(
        name: "group", description: "Server group", choices: ServerGroup.allCases.map(\.rawValue), fallback: nil)
    static let serverLimit = IntegerParameter(name: "limit", description: "Number of servers", range: 1...50, fallback: 10)
    static let responseFormat = ChoiceParameter(
        name: "response_format", description: "'markdown' for readable text, 'json' for structured data",
        choices: ["markdown", "json"], fallback: "markdown")
    static let offline = BooleanParameter(
        name: "offline", description: "Skip the check that contacts NordVPN's API", fallback: false)

    var statusTool: Tool {
        Tool(
            name: "nordvpn_get_status", title: "Get VPN status",
            description: """
            Report the NordVPN tunnel state, the connected server, and the public IP with whether NordVPN considers it protected.

            Use it before and after nordvpn_connect or nordvpn_disconnect, and to answer "am I on the VPN?". \
            A successful call does not mean the VPN is connected: check vpn.state and publicIP.protected.
            """,
            parameters: [], outputSchema: OutputSchemas.status, annotations: .readOnly
        ) { _ in
            try .json(JSONValue(encoding: await control.status()))
        }
    }

    var countriesTool: Tool {
        Tool(
            name: "nordvpn_list_countries", title: "List VPN countries",
            description: """
            List the countries with NordVPN servers, with server counts and city names.

            Use it to find a valid location for nordvpn_connect or nordvpn_list_servers.
            Examples:
              - "Which cities can I use in Germany?" -> filter="germany"
              - "Countries starting with United" -> filter="united"
            """,
            parameters: [Self.filter, Self.countryLimit, Self.offset, Self.responseFormat],
            outputSchema: nil, annotations: .readOnly, run: listCountries)
    }

    var serversTool: Tool {
        Tool(
            name: "nordvpn_list_servers", title: "List least loaded servers",
            description: """
            Show NordVPN's recommended (least loaded) servers, optionally in one country and server group.

            Informational only: the app picks the actual server, and nordvpn_connect cannot target a specific server or group.
            Examples:
              - "Least loaded P2P servers in the US" -> location="us", group="p2p"
              - "How busy are servers in Italy?" -> location="italy"
            """,
            parameters: [Self.serverLocation, Self.group, Self.serverLimit, Self.responseFormat],
            outputSchema: nil, annotations: .readOnly, run: listServers)
    }

    var doctorTool: Tool {
        Tool(
            name: "nordvpn_run_doctor", title: "Diagnose NordVPN setup",
            description: """
            Check the NordVPN app installation, VPN profiles, Accessibility permission, app logs and API access, \
            without changing the connection.

            Use it when another nordvpn tool fails. The "accessibility" check concerns the application that runs \
            this MCP server (your terminal, Cursor, Claude, Codex…) and matters only for nordvpn_disconnect.
            The report contains no IP addresses, server names, account data or local paths.
            """,
            parameters: [Self.offline], outputSchema: OutputSchemas.doctor, annotations: .readOnly
        ) { arguments in
            let checks = await control.diagnostics(offline: try Self.offline.value(in: arguments))
            return try .json(JSONValue(encoding: DoctorReport(allPassed: checks.allSatisfy(\.passed), checks: checks)))
        }
    }

    @Sendable func listCountries(_ arguments: ToolArguments) async throws -> ToolResult {
        let filter = try Self.filter.value(in: arguments)
        let limit = try Self.countryLimit.value(in: arguments)
        let offset = try Self.offset.value(in: arguments)
        let asJSON = try Self.responseFormat.value(in: arguments) == "json"
        let countries = try await control.countries().filter { filter.map($0.matches) ?? true }
        guard !countries.isEmpty else {
            return .text(filter.map { "No country matches \"\($0)\". Call again without a filter to see every country." }
                ?? "NordVPN returned no countries.")
        }
        guard offset < countries.count else {
            return .text("Offset \(offset) is past the last of \(countries.count) countries.")
        }
        let page = try CountryPage.fitting(Array(countries.dropFirst(offset).prefix(limit)), of: countries.count,
                                           offset: offset, asJSON: asJSON)
        return asJSON ? try .json(JSONValue(encoding: page)) : .text(try page.rendered(asJSON: false))
    }

    @Sendable func listServers(_ arguments: ToolArguments) async throws -> ToolResult {
        let location = try Self.serverLocation.value(in: arguments)
        let group = try Self.group.value(in: arguments).flatMap(ServerGroup.init(rawValue:))
        let limit = try Self.serverLimit.value(in: arguments)
        let asJSON = try Self.responseFormat.value(in: arguments) == "json"
        var country: Country?
        if let location { country = try await resolve(location).country }
        let servers = try await control.servers(countryID: country?.id, group: group, limit: limit).map(CompactServer.init)
        guard !servers.isEmpty else { return .text("No servers found. Try another group or location.") }
        if asJSON { return try .json(JSONValue(encoding: ServerList(count: servers.count, servers: servers))) }
        let lines = servers.map { server in
            "- **\(server.name)**: load \(server.load)%, \([server.city, server.hostname].compactMap { $0 }.joined(separator: " · "))"
        }
        return .text((["# Least loaded NordVPN servers", ""] + lines).joined(separator: "\n"))
    }
}

// MARK: - Tools that change the network

extension NordVPNTools {
    static let connectLocation = TextParameter(
        name: "location", description: "Country code, country name or city; omit for the fastest server", maxLength: 60)
    static let connectTimeout = waitSeconds(fallback: 30)
    static let wait = BooleanParameter(
        name: "wait", description: "false returns right after the request is sent, without confirming the connection",
        fallback: true)
    static let disconnectTimeout = waitSeconds(fallback: 15)

    static func waitSeconds(fallback: Int) -> IntegerParameter {
        IntegerParameter(name: "timeout_seconds", description: "Seconds to wait for confirmation (1-\(maxWaitSeconds))",
                         range: 1...maxWaitSeconds, fallback: fallback)
    }

    var connectTool: Tool {
        Tool(
            name: "nordvpn_connect", title: "Connect the VPN",
            description: """
            Ask the NordVPN app to connect, to the fastest server or to a country, and wait until the tunnel and public IP are verified.

            Changes the Mac's network: an existing VPN connection is replaced. Only a country can be targeted; \
            a city connects to the fastest server of its country.
            Use nordvpn_list_countries to find valid locations.
            Examples:
              - "Connect me to the VPN" -> no arguments
              - "Put me in Italy" -> location="italy"
            """,
            parameters: [Self.connectLocation, Self.connectTimeout, Self.wait],
            outputSchema: nil, annotations: .changesNetwork(idempotent: false)
        ) { arguments in
            let location = try Self.connectLocation.value(in: arguments)
            let timeout = try Self.connectTimeout.value(in: arguments)
            let wait = try Self.wait.value(in: arguments)
            return try await changes.run { try await connect(to: location, timeout: timeout, wait: wait) }
        }
    }

    var disconnectTool: Tool {
        Tool(
            name: "nordvpn_disconnect", title: "Disconnect the VPN",
            description: """
            Disconnect the NordVPN tunnel and wait until it closes. Traffic is no longer protected afterwards.

            The app has no disconnect deep link, so this presses "Disconnect" in its menu through the macOS \
            Accessibility API: the application running this MCP server needs Accessibility access. \
            Already disconnected is reported as success.
            """,
            parameters: [Self.disconnectTimeout], outputSchema: nil, annotations: .changesNetwork(idempotent: true)
        ) { arguments in
            let timeout = try Self.disconnectTimeout.value(in: arguments)
            return try await changes.run { await disconnect(timeout: timeout) }
        }
    }

    func connect(to location: String?, timeout: Int, wait: Bool) async throws -> ToolResult {
        var resolved: ResolvedLocation?
        if let location { resolved = try await resolve(location) }
        let country = resolved?.country
        let connection: VerifiedConnection?
        do {
            connection = try await control.connect(countryCode: country?.code, verifyingWithin: wait ? TimeInterval(timeout) : nil)
        } catch {
            let pending = error is ConnectionFailure ? " The request was sent and may still complete." : ""
            return .failure("\(error.localizedDescription)\(pending)\n\n\(Self.nextSteps)")
        }
        var lines: [String]
        if let connection {
            let ip = connection.publicIP
            let place = [ip.city, ip.country].compactMap { $0 }.joined(separator: ", ")
            lines = ["Connected to \(connection.server ?? country?.name ?? "NordVPN"). Public IP \(ip.ip)"
                + (place.isEmpty ? "" : " (\(place))") + ", protected by NordVPN."]
        } else {
            lines = ["Asked the app to connect to \(country?.name ?? "the fastest server"). "
                + "The connection is not confirmed yet: call nordvpn_get_status to check."]
        }
        if let warning = resolved?.cityWarning { lines.append("Warning: \(warning)") }
        return .text(lines.joined(separator: "\n"))
    }

    func disconnect(timeout: Int) async -> ToolResult {
        do {
            switch try await control.disconnect(waitingUpTo: TimeInterval(timeout)) {
            case .alreadyDisconnected: return .text("Already disconnected.")
            case .disconnected: return .text("Disconnected. Traffic is no longer protected by the VPN.")
            }
        } catch NordAppError.accessibilityDenied {
            let message = NordAppError.accessibilityDenied.localizedDescription
            return .failure("\(message)\n\n\(Self.accessibilityHint) \(Self.nextSteps)")
        } catch {
            return .failure("\(error.localizedDescription)\n\n\(Self.nextSteps)")
        }
    }
}
