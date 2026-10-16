import Foundation

/// A tool argument. Each one produces both its JSON Schema and the check applied to `tools/call`,
/// so what clients are told and what the server accepts cannot drift apart.
protocol ToolParameter: Sendable {
    var name: String { get }
    var schema: JSONValue { get }
}

struct ToolArguments: Sendable {
    let values: [String: JSONValue]

    /// A missing argument and an explicit null both mean "use the default".
    subscript(name: String) -> JSONValue? {
        values[name] == .null ? nil : values[name]
    }
}

struct InvalidArgument: LocalizedError {
    let name: String
    let requirement: String

    var errorDescription: String? { "Invalid \(name): \(requirement)." }
}

/// Free text, trimmed. Nil when absent.
struct TextParameter: ToolParameter {
    let name: String
    let description: String
    let maxLength: Int

    var schema: JSONValue {
        ["type": "string", "minLength": 1, "maxLength": .number(Double(maxLength)), "description": .string(description)]
    }

    func value(in arguments: ToolArguments) throws -> String? {
        guard let value = arguments[name] else { return nil }
        let text = value.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard (1...maxLength).contains(text.count) else {
            throw InvalidArgument(name: name, requirement: "must be text of 1 to \(maxLength) characters")
        }
        return text
    }
}

/// One of a fixed set of strings, or `fallback` when absent.
struct ChoiceParameter: ToolParameter {
    let name: String
    let description: String
    let choices: [String]
    let fallback: String?

    var schema: JSONValue {
        var fields: [String: JSONValue] = [
            "type": "string", "enum": .array(choices.map(JSONValue.string)), "description": .string(description),
        ]
        fields["default"] = fallback.map(JSONValue.string)
        return .object(fields)
    }

    func value(in arguments: ToolArguments) throws -> String? {
        guard let value = arguments[name] else { return fallback }
        guard let choice = value.string, choices.contains(choice) else {
            throw InvalidArgument(name: name, requirement: "must be one of \(choices.joined(separator: ", "))")
        }
        return choice
    }
}

struct IntegerParameter: ToolParameter {
    let name: String
    let description: String
    let range: ClosedRange<Int>
    let fallback: Int

    var schema: JSONValue {
        ["type": "integer", "minimum": .number(Double(range.lowerBound)), "maximum": .number(Double(range.upperBound)),
         "default": .number(Double(fallback)), "description": .string(description)]
    }

    func value(in arguments: ToolArguments) throws -> Int {
        guard let value = arguments[name] else { return fallback }
        guard case let .number(number) = value, number.rounded() == number,
              Double(range.lowerBound) <= number, number <= Double(range.upperBound) else {
            throw InvalidArgument(name: name, requirement: "must be a whole number from \(range.lowerBound) to \(range.upperBound)")
        }
        return Int(number)
    }
}

struct BooleanParameter: ToolParameter {
    let name: String
    let description: String
    let fallback: Bool

    var schema: JSONValue {
        ["type": "boolean", "default": .bool(fallback), "description": .string(description)]
    }

    func value(in arguments: ToolArguments) throws -> Bool {
        guard let value = arguments[name] else { return fallback }
        guard case let .bool(flag) = value else { throw InvalidArgument(name: name, requirement: "must be true or false") }
        return flag
    }
}
