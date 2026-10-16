import Foundation

extension MCPServer {
    /// Serves newline-delimited JSON-RPC on stdin and stdout until stdin closes, then lets the
    /// requests in flight finish. Lines are split on "\n" only: JSON strings may hold other line separators.
    public func serveStdio() async throws {
        let session = StdioSession(server: self)
        var line = Data()
        for try await byte in FileHandle.standardInput.bytes {
            if byte == UInt8(ascii: "\n") {
                await session.receive(line)
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(byte)
            }
        }
        if !line.isEmpty { await session.receive(line) }
        await session.finishRequests()
    }
}

/// Runs each request in its own task, so a connect that waits for the tunnel does not hold up a ping,
/// and writes every response as one line of stdout.
actor StdioSession {
    private let server: MCPServer
    private var inFlight: [JSONValue: Task<Void, Never>] = [:]

    init(server: MCPServer) {
        self.server = server
    }

    func receive(_ line: Data) async {
        guard line.contains(where: { !" \r\t".utf8.contains($0) }) else { return }
        let message: JSONValue
        do {
            message = try JSONDecoder().decode(JSONValue.self, from: line)
        } catch {
            return write(MCPServer.error(id: nil, RPCError(.parseError, "The message is not valid JSON.")))
        }
        if message["method"] == "notifications/cancelled" {
            if let id = message["params"]?["requestId"] { inFlight.removeValue(forKey: id)?.cancel() }
            return
        }
        guard let id = message["id"], message["method"] != nil else {
            if let response = await server.respond(to: message) { write(response) }
            return
        }
        inFlight[id] = Task { [server] in
            let response = await server.respond(to: message)
            self.complete(id, with: response)
        }
    }

    func finishRequests() async {
        for task in inFlight.values { await task.value }
    }

    /// A cancelled request was already removed, and gets no response.
    private func complete(_ id: JSONValue, with response: JSONValue?) {
        guard inFlight.removeValue(forKey: id) != nil, let response else { return }
        write(response)
    }

    private func write(_ message: JSONValue) {
        do {
            try FileHandle.standardOutput.write(contentsOf: message.encoded() + Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("nordvpn mcp: could not write a response: \(error)\n".utf8))
        }
    }
}
