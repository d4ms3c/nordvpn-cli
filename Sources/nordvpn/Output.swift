import Foundation
import NordVPNKit

enum Style {
    static let enabled = isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func green(_ s: String) -> String { wrap(s, "32") }
    static func yellow(_ s: String) -> String { wrap(s, "33") }
    static func red(_ s: String) -> String { wrap(s, "31") }
    static func dim(_ s: String) -> String { wrap(s, "2") }
    static func bold(_ s: String) -> String { wrap(s, "1") }

    private static func wrap(_ s: String, _ code: String) -> String {
        enabled ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s
    }
}

extension VPNState {
    var styled: String {
        switch self {
        case .connected: Style.green("Connected")
        case .connecting: Style.yellow("Connecting")
        case .disconnecting: Style.yellow("Disconnecting")
        case .disconnected: Style.red("Disconnected")
        case .invalid: Style.red("Unavailable")
        }
    }
}

/// Aligned "Label: value" rows.
func printRows(_ rows: [(String, String?)]) {
    let visible = rows.compactMap { label, value in value.map { (label, $0) } }
    let width = visible.map(\.0.count).max() ?? 0
    for (label, value) in visible {
        print("\(Style.dim(label.padding(toLength: width, withPad: " ", startingAt: 0)))  \(value)")
    }
}

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

func formatDuration(since date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    let (h, m, s) = (seconds / 3600, seconds % 3600 / 60, seconds % 60)
    return h > 0 ? "\(h)h \(m)m" : m > 0 ? "\(m)m \(s)s" : "\(s)s"
}

func stderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
