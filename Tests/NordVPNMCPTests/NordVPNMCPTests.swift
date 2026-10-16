import Foundation
import Testing
@testable import NordVPNKit
@testable import NordVPNMCP

// MARK: - Fake app and API

actor CallLog {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

/// Stands in for the NordVPN app and API, recording each call, so no test changes the VPN.
struct FakeNordVPN: NordVPNControl {
    let log = CallLog()
    var accessibilityDenied = false
    var connectDuration: Duration = .zero

    func status() async -> StatusReport {
        await log.record("status")
        return StatusReport(
            vpn: VPNSnapshot(serviceID: "service", name: "NordLynx", state: .connected, interface: "utun4",
                             tunnelAddress: "10.5.0.2", since: Date(timeIntervalSince1970: 0), onDemand: true),
            server: "Italy #456", lastTarget: "country:it:-:-:-", publicIP: italianIP)
    }

    func countries() async throws -> [Country] {
        [
            Country(id: 81, name: "Germany", code: "DE", serverCount: 300,
                    cities: [.init(id: 1, name: "Frankfurt", serverCount: 200), .init(id: 2, name: "Berlin", serverCount: 100)]),
            Country(id: 106, name: "Italy", code: "IT", serverCount: 120,
                    cities: [.init(id: 3, name: "Milan", serverCount: 100), .init(id: 4, name: "Rome", serverCount: 20)]),
            Country(id: 228, name: "United States", code: "US", serverCount: 2000,
                    cities: [.init(id: 5, name: "New York", serverCount: 300)]),
        ]
    }

    func servers(countryID: Int?, group: ServerGroup?, limit: Int) async throws -> [Server] {
        await log.record("servers \(countryID.map(String.init) ?? "-") \(group?.rawValue ?? "-") \(limit)")
        let servers = (1...limit).map { number in
            """
            {"name": "Italy #\(number)", "hostname": "it\(number).nordvpn.com", "station": "203.0.113.\(number)", "load": \(number * 10),
             "locations": [{"country": {"name": "Italy", "code": "IT", "city": {"name": "Milan"}}}],
             "groups": [{"identifier": "legacy_p2p"}]}
            """
        }
        return try JSONDecoder().decode([Server].self, from: Data("[\(servers.joined(separator: ","))]".utf8))
    }

    func diagnostics(offline: Bool) async -> [DiagnosticCheck] {
        await log.record("doctor offline=\(offline)")
        return [DiagnosticCheck(name: "app", passed: true, message: "NordVPN installed."),
                DiagnosticCheck(name: "accessibility", passed: false, message: "Required only for disconnect.")]
    }

    func connect(countryCode: String?, verifyingWithin timeout: TimeInterval?) async throws -> VerifiedConnection? {
        await log.record("connect \(countryCode ?? "-") \(timeout.map { String(Int($0)) } ?? "no-wait")")
        try await Task.sleep(for: connectDuration)
        await log.record("connected")
        return timeout == nil ? nil : VerifiedConnection(server: "Italy #456", publicIP: italianIP)
    }

    func disconnect(waitingUpTo timeout: TimeInterval) async throws -> DisconnectOutcome {
        if accessibilityDenied { throw NordAppError.accessibilityDenied }
        await log.record("disconnect")
        return .disconnected
    }

    private var italianIP: IPInsights {
        IPInsights(ip: "203.0.113.7", country: "Italy", countryCode: "IT", city: "Milan", isp: "Example", protected: true)
    }
}

// MARK: - Helpers

private func makeServer(_ fake: FakeNordVPN = FakeNordVPN(), readOnly: Bool = false) -> MCPServer {
    MCPServer(name: "nordvpn", title: "NordVPN", version: "0.0.0", instructions: "Test.",
              tools: NordVPNTools(control: fake).tools(readOnly: readOnly))
}

private func request(_ server: MCPServer, _ method: String, _ params: JSONValue = [:]) async -> JSONValue? {
    await server.respond(to: ["jsonrpc": "2.0", "id": 1, "method": .string(method), "params": params])
}

private func callTool(_ server: MCPServer, _ name: String, _ arguments: JSONValue = [:]) async throws -> JSONValue {
    let response = await request(server, "tools/call", ["name": .string(name), "arguments": arguments])
    return try #require(response?["result"])
}

private func text(of result: JSONValue) -> String {
    guard case let .array(blocks)? = result["content"] else { return "" }
    return blocks.compactMap { $0["text"]?.string }.joined(separator: "\n")
}

private func toolNames(_ server: MCPServer) async -> [String] {
    guard case let .array(tools)? = await request(server, "tools/list")?["result"]?["tools"] else { return [] }
    return tools.compactMap { $0["name"]?.string }
}

// MARK: - Protocol

@Test func negotiatesTheProtocolVersion() async {
    let server = makeServer()
    let supported = await request(server, "initialize", ["protocolVersion": "2025-03-26"])?["result"]
    #expect(supported?["protocolVersion"] == "2025-03-26")
    #expect(supported?["capabilities"]?["tools"] == ["listChanged": false])
    #expect(supported?["serverInfo"]?["name"] == "nordvpn")

    let unknown = await request(server, "initialize", ["protocolVersion": "1999-01-01"])?["result"]
    #expect(unknown?["protocolVersion"] == .string(MCPServer.protocolVersions[0]))
}

@Test func answersPingAndRejectsUnknownMethods() async {
    let server = makeServer()
    #expect(await request(server, "ping")?["result"] == [:])
    #expect(await request(server, "resources/list")?["error"]?["code"] == -32601)
    #expect(await request(server, "tools/call", ["name": "nordvpn_nope"])?["error"]?["code"] == -32602)
    #expect(await server.respond(to: ["jsonrpc": "1.0", "id": 1, "method": "ping"])?["error"]?["code"] == -32600)
}

@Test func sendsNothingForNotificationsOrClientResponses() async {
    let server = makeServer()
    #expect(await server.respond(to: ["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil)
    #expect(await server.respond(to: ["jsonrpc": "2.0", "id": 9, "result": [:]]) == nil)
}

@Test func annotatesReadOnlyAndNetworkChangingTools() async throws {
    let response = await request(makeServer(), "tools/list")
    guard case let .array(tools)? = response?["result"]?["tools"] else { Issue.record("no tools"); return }
    let byName = Dictionary(uniqueKeysWithValues: tools.compactMap { tool in tool["name"]?.string.map { ($0, tool) } })
    #expect(byName.keys.sorted() == ["nordvpn_connect", "nordvpn_disconnect", "nordvpn_get_status",
                                     "nordvpn_list_countries", "nordvpn_list_servers", "nordvpn_run_doctor"])
    for (name, tool) in byName {
        let readOnly = !["nordvpn_connect", "nordvpn_disconnect"].contains(name)
        #expect(tool["annotations"]?["readOnlyHint"] == .bool(readOnly), "\(name)")
        #expect(tool["annotations"]?["destructiveHint"] == .bool(!readOnly), "\(name)")
        #expect(tool["inputSchema"]?["additionalProperties"] == false, "\(name)")
    }
}

@Test func readOnlyModeLeavesOutConnectAndDisconnect() async {
    #expect(await toolNames(makeServer(readOnly: true)) == ["nordvpn_get_status", "nordvpn_list_countries",
                                                           "nordvpn_list_servers", "nordvpn_run_doctor"])
}

@Test func encodesWholeNumbersWithoutAFraction() throws {
    #expect(String(decoding: try JSONValue.array([10, 2.5]).encoded(), as: UTF8.self) == "[10,2.5]")
}

// MARK: - Reporting tools

@Test func statusRepeatsItsStructuredContentAsText() async throws {
    let result = try await callTool(makeServer(), "nordvpn_get_status")
    #expect(result["isError"] == nil)
    #expect(result["structuredContent"]?["vpn"]?["state"] == "connected")
    #expect(result["structuredContent"]?["vpn"]?["since"] == "1970-01-01T00:00:00Z")
    #expect(result["structuredContent"]?["publicIP"]?["country_code"] == "IT")
    #expect(try JSONDecoder().decode(JSONValue.self, from: Data(text(of: result).utf8)) == result["structuredContent"])
}

@Test func doctorReturnsFailedChecksAsData() async throws {
    let fake = FakeNordVPN()
    let result = try await callTool(makeServer(fake), "nordvpn_run_doctor", ["offline": true])
    #expect(result["isError"] == nil)
    #expect(result["structuredContent"]?["all_passed"] == false)
    #expect(await fake.log.entries == ["doctor offline=true"])
}

@Test func countriesPaginateAndFilter() async throws {
    let server = makeServer()
    let page = try await callTool(server, "nordvpn_list_countries", ["limit": 2, "response_format": "json"])
    #expect(page["structuredContent"]?["total"] == 3)
    #expect(page["structuredContent"]?["count"] == 2)
    #expect(page["structuredContent"]?["next_offset"] == 2)

    let last = try await callTool(server, "nordvpn_list_countries", ["offset": 2, "response_format": "json"])
    #expect(last["structuredContent"]?["has_more"] == false)
    #expect(last["structuredContent"]?["next_offset"] == nil)

    let germany = try await callTool(server, "nordvpn_list_countries", ["filter": "germany"])
    #expect(text(of: germany).contains("- **DE** Germany: 300 servers; cities: Berlin, Frankfurt"))
    #expect(text(of: try await callTool(server, "nordvpn_list_countries", ["filter": "narnia"]))
        .contains("No country matches \"narnia\""))
    #expect(text(of: try await callTool(server, "nordvpn_list_countries", ["offset": 9]))
        .contains("Offset 9 is past the last of 3 countries."))
}

@Test func serversResolveTheLocationAndComeBackCompact() async throws {
    let fake = FakeNordVPN()
    let result = try await callTool(makeServer(fake), "nordvpn_list_servers",
                                    ["location": "rome", "group": "p2p", "limit": 3, "response_format": "json"])
    #expect(result["structuredContent"]?["count"] == 3)
    guard case let .array(servers)? = result["structuredContent"]?["servers"], case let .object(first)? = servers.first else {
        Issue.record("no servers")
        return
    }
    #expect(first.keys.sorted() == ["city", "country", "country_code", "groups", "hostname", "load", "name"])
    #expect(await fake.log.entries == ["servers 106 p2p 3"])
}

// MARK: - Tools that change the network

@Test func connectResolvesACityToItsCountryAndWarns() async throws {
    let fake = FakeNordVPN()
    let result = try await callTool(makeServer(fake), "nordvpn_connect", ["location": "rome", "timeout_seconds": 20])
    #expect(result["isError"] == nil)
    #expect(text(of: result).contains("Connected to Italy #456. Public IP 203.0.113.7 (Milan, Italy), protected by NordVPN."))
    #expect(text(of: result).contains("Warning: The app cannot pick a city"))
    #expect(await fake.log.entries == ["connect IT 20", "connected"])
}

@Test func connectWithoutWaitingSaysItIsNotConfirmed() async throws {
    let fake = FakeNordVPN()
    let result = try await callTool(makeServer(fake), "nordvpn_connect", ["wait": false])
    #expect(text(of: result).contains("not confirmed yet"))
    #expect(await fake.log.entries == ["connect - no-wait", "connected"])
}

@Test func unknownLocationIsAToolErrorThatNamesTheCountryList() async throws {
    let fake = FakeNordVPN()
    let result = try await callTool(makeServer(fake), "nordvpn_connect", ["location": "atlantis"])
    #expect(result["isError"] == true)
    #expect(text(of: result).hasPrefix("No country or city matches \"atlantis\""))
    #expect(text(of: result).contains("nordvpn_list_countries"))
    #expect(await fake.log.entries.isEmpty)
}

@Test(arguments: [
    ["timeout_seconds": 0], ["timeout_seconds": 56], ["timeout_seconds": 2.5], ["timeout_seconds": "30"],
    ["location": ""], ["location": "   "], ["wait": "yes"], ["country": "it"],
] as [JSONValue])
func invalidArgumentsNeverReachTheApp(arguments: JSONValue) async throws {
    let fake = FakeNordVPN()
    let result = try await callTool(makeServer(fake), "nordvpn_connect", arguments)
    #expect(result["isError"] == true)
    #expect(await fake.log.entries.isEmpty)
}

@Test func disconnectBlockedByAccessibilityNamesTheHostApplication() async throws {
    let result = try await callTool(makeServer(FakeNordVPN(accessibilityDenied: true)), "nordvpn_disconnect")
    #expect(result["isError"] == true)
    #expect(text(of: result).contains("application that runs this MCP server"))
}

@Test func connectAndDisconnectNeverOverlap() async throws {
    let fake = FakeNordVPN(connectDuration: .milliseconds(200))
    let server = makeServer(fake)
    async let connect = callTool(server, "nordvpn_connect", ["location": "italy"])
    try await Task.sleep(for: .milliseconds(50))
    async let disconnect = callTool(server, "nordvpn_disconnect")
    _ = try await (connect, disconnect)
    #expect(await fake.log.entries == ["connect IT 30", "connected", "disconnect"])
}
