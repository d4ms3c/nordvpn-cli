import Foundation

/// One MCP tool: its entry in `tools/list` and the work behind `tools/call`.
public struct Tool: Sendable {
    /// Hints that let clients ask for approval only where it matters.
    struct Annotations: Sendable {
        let readOnly: Bool
        let destructive: Bool
        let idempotent: Bool

        static let readOnly = Annotations(readOnly: true, destructive: false, idempotent: true)

        static func changesNetwork(idempotent: Bool) -> Annotations {
            Annotations(readOnly: false, destructive: true, idempotent: idempotent)
        }

        /// Every tool reaches the NordVPN app or its API, outside this process.
        var json: JSONValue {
            ["readOnlyHint": .bool(readOnly), "destructiveHint": .bool(destructive),
             "idempotentHint": .bool(idempotent), "openWorldHint": true]
        }
    }

    let name: String
    let title: String
    let description: String
    let parameters: [any ToolParameter]
    let outputSchema: JSONValue?
    let annotations: Annotations
    let run: @Sendable (ToolArguments) async throws -> ToolResult

    var definition: JSONValue {
        let properties = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.schema) })
        var fields: [String: JSONValue] = [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": ["type": "object", "properties": .object(properties), "additionalProperties": false],
            "annotations": annotations.json,
        ]
        fields["outputSchema"] = outputSchema
        return .object(fields)
    }

    /// Errors become tool results with `isError`, which the model reads, instead of protocol errors.
    func call(_ arguments: [String: JSONValue]) async -> ToolResult {
        let unknown = arguments.keys.filter { key in !parameters.contains { $0.name == key } }.sorted()
        guard unknown.isEmpty else {
            let accepted = parameters.isEmpty ? "none" : parameters.map(\.name).joined(separator: ", ")
            return .failure("Unknown argument \(unknown.joined(separator: ", ")). \(name) accepts: \(accepted).")
        }
        do {
            return try await run(ToolArguments(values: arguments))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

public struct ToolResult: Sendable {
    let text: String
    let structuredContent: JSONValue?
    let isError: Bool

    static func text(_ text: String) -> ToolResult {
        ToolResult(text: text, structuredContent: nil, isError: false)
    }

    static func failure(_ message: String) -> ToolResult {
        ToolResult(text: message, structuredContent: nil, isError: true)
    }

    /// Structured output, repeated as text for clients that only show text.
    static func json(_ value: JSONValue) throws -> ToolResult {
        ToolResult(text: String(decoding: try value.encoded(pretty: true), as: UTF8.self), structuredContent: value, isError: false)
    }

    var json: JSONValue {
        var fields: [String: JSONValue] = ["content": [["type": "text", "text": .string(text)]]]
        fields["structuredContent"] = structuredContent
        if isError { fields["isError"] = true }
        return .object(fields)
    }
}
