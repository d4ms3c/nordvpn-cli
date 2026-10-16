import ArgumentParser
import Foundation
import NordVPNMCP

struct MCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve the Model Context Protocol on stdin and stdout, for AI agents.",
        discussion: """
        Your MCP client starts this command; you do not run it yourself. The agent can then check the VPN \
        and, if your client asks for approval, connect or disconnect only after you allow it.

        Examples:
          claude mcp add --scope user nordvpn -- nordvpn mcp
          codex mcp add nordvpn -- nordvpn mcp --read-only

        Setup for Cursor, VS Code and other clients: https://github.com/d4ms3c/nordvpn-cli/blob/main/docs/mcp.md
        """
    )

    @Flag(help: "Offer only the reporting tools, so no agent can connect or disconnect.") var readOnly = false

    func run() async throws {
        if isatty(STDIN_FILENO) != 0 {
            stderr("nordvpn mcp expects an MCP client on stdin. Add it to Claude Code, Codex or Cursor; press Ctrl-D to quit.")
        }
        let server = MCPServer(
            name: "nordvpn", title: "NordVPN", version: NordVPN.configuration.version,
            instructions: NordVPNTools.instructions,
            tools: NordVPNTools(control: LiveNordVPN()).tools(readOnly: readOnly))
        try await server.serveStdio()
    }
}
