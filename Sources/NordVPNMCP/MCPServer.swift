import Foundation

struct RPCError: Error {
    enum Code: Int {
        case parseError = -32700
        case invalidRequest = -32600
        case methodNotFound = -32601
        case invalidParams = -32602
    }

    let code: Code
    let message: String

    init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }
}

/// A Model Context Protocol server that offers tools and nothing else. It answers one decoded
/// JSON-RPC message at a time; `serveStdio()` adds the transport, concurrency and cancellation.
public struct MCPServer: Sendable {
    /// Newest first: a client asking for a version not listed here gets the newest.
    static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    let name: String
    let title: String
    let version: String
    let instructions: String
    let tools: [Tool]

    public init(name: String, title: String, version: String, instructions: String, tools: [Tool]) {
        self.name = name
        self.title = title
        self.version = version
        self.instructions = instructions
        self.tools = tools
    }

    /// The response to `message`; nil for notifications and for responses from the client.
    public func respond(to message: JSONValue) async -> JSONValue? {
        guard message["jsonrpc"] == "2.0" else {
            return Self.error(id: message["id"], RPCError(.invalidRequest, "Expected a JSON-RPC 2.0 message."))
        }
        let id = message["id"]
        guard let method = message["method"]?.string else {
            let isClientResponse = id != nil && (message["result"] != nil || message["error"] != nil)
            return isClientResponse ? nil : Self.error(id: id, RPCError(.invalidRequest, "Missing method."))
        }
        guard let id else { return nil }
        do throws(RPCError) {
            let value = try await result(of: method, params: message["params"])
            return ["jsonrpc": "2.0", "id": id, "result": value]
        } catch {
            return Self.error(id: id, error)
        }
    }

    static func error(id: JSONValue?, _ error: RPCError) -> JSONValue {
        ["jsonrpc": "2.0", "id": id ?? .null, "error": ["code": .number(Double(error.code.rawValue)), "message": .string(error.message)]]
    }

    private func result(of method: String, params: JSONValue?) async throws(RPCError) -> JSONValue {
        switch method {
        case "initialize": initializeResult(requestedVersion: params?["protocolVersion"]?.string)
        case "ping": [:]
        case "tools/list": ["tools": .array(tools.map(\.definition))]
        case "tools/call": try await callTool(params)
        default: throw RPCError(.methodNotFound, "Method not found: \(method).")
        }
    }

    private func initializeResult(requestedVersion: String?) -> JSONValue {
        let protocolVersion = requestedVersion.flatMap { Self.protocolVersions.contains($0) ? $0 : nil }
            ?? Self.protocolVersions[0]
        return [
            "protocolVersion": .string(protocolVersion),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": .string(name), "title": .string(title), "version": .string(version)],
            "instructions": .string(instructions),
        ]
    }

    private func callTool(_ params: JSONValue?) async throws(RPCError) -> JSONValue {
        guard let name = params?["name"]?.string else { throw RPCError(.invalidParams, "tools/call needs a tool name.") }
        guard let tool = tools.first(where: { $0.name == name }) else {
            throw RPCError(.invalidParams, "Unknown tool: \(name).")
        }
        switch params?["arguments"] {
        case nil, .null?: return await tool.call([:]).json
        case let .object(arguments)?: return await tool.call(arguments).json
        default: throw RPCError(.invalidParams, "Tool arguments must be an object.")
        }
    }
}
