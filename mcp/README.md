# nordvpn MCP server

A local [Model Context Protocol](https://modelcontextprotocol.io) server that lets AI coding agents (Claude Code, Codex, Cursor, VS Code and others) check your NordVPN connection and, with your approval, connect or disconnect it.

It runs the [`nordvpn` CLI](../README.md) as a subprocess over stdio: no credentials, no open network port, and the same limits as the CLI. Requests to NordVPN's public API come from the CLI, not from the server.

## Tools

| Tool | What it does | Changes the VPN |
|---|---|---|
| `nordvpn_get_status` | Tunnel state, server, public IP and whether NordVPN considers it protected | No |
| `nordvpn_list_countries` | Countries with server counts and cities, filtered and paginated | No |
| `nordvpn_list_servers` | Least loaded servers by country and group (informational) | No |
| `nordvpn_run_doctor` | App, profile, Accessibility, log and API checks | No |
| `nordvpn_connect` | Connect to the fastest server or a country, and verify it | **Yes** |
| `nordvpn_disconnect` | Disconnect through the app's menu | **Yes** |

The four reporting tools are annotated `readOnlyHint`; connect and disconnect are annotated `destructiveHint`, so clients that honor annotations ask before running them. Connect and disconnect never run at the same time.

## Install

Requires the `nordvpn` CLI 0.2.0 or later and Node.js 22 or later. From the repository root:

```sh
make install   # the CLI, if not installed yet
make mcp       # installs dependencies and builds mcp/dist/index.js
```

The server command is `node /ABSOLUTE/PATH/nordvpn-cli/mcp/dist/index.js`. The commands below use `$PWD`, so run them from the repository root.

## Add it to your agent

### Claude Code

```sh
claude mcp add --scope user nordvpn -- node "$PWD/mcp/dist/index.js"
```

To skip the prompt for the reporting tools, add them to `permissions.allow` in `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "mcp__nordvpn__nordvpn_get_status",
      "mcp__nordvpn__nordvpn_list_countries",
      "mcp__nordvpn__nordvpn_list_servers",
      "mcp__nordvpn__nordvpn_run_doctor"
    ]
  }
}
```

### Codex (CLI, IDE extension and desktop app)

```sh
codex mcp add nordvpn -- node "$PWD/mcp/dist/index.js"
```

The three Codex surfaces share `~/.codex/config.toml`. Setting `default_tools_approval_mode = "writes"` makes Codex prompt only for tools not marked read-only, here connect and disconnect:

```toml
[mcp_servers.nordvpn]
command = "node"
args = ["/ABSOLUTE/PATH/nordvpn-cli/mcp/dist/index.js"]
default_tools_approval_mode = "writes"
```

### Cursor

Add to `~/.cursor/mcp.json` (all projects) or `.cursor/mcp.json` (one project):

```json
{
  "mcpServers": {
    "nordvpn": {
      "command": "node",
      "args": ["/ABSOLUTE/PATH/nordvpn-cli/mcp/dist/index.js"]
    }
  }
}
```

### VS Code (GitHub Copilot agent mode)

```sh
code --add-mcp "{\"name\":\"nordvpn\",\"command\":\"node\",\"args\":[\"$PWD/mcp/dist/index.js\"]}"
```

Or add it to `.vscode/mcp.json`. VS Code uses `servers` as the top-level key, not `mcpServers`:

```json
{
  "servers": {
    "nordvpn": {
      "type": "stdio",
      "command": "node",
      "args": ["/ABSOLUTE/PATH/nordvpn-cli/mcp/dist/index.js"]
    }
  }
}
```

### Other clients

These clients use the same `mcpServers` block as Cursor, in their own file:

| Client | Configuration file |
|---|---|
| Devin Desktop (Windsurf) | `~/.config/devin/mcp_config.json` |
| Antigravity CLI | `~/.gemini/config/mcp_config.json`, or `.agents/mcp_config.json` in a project |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` |

Apps started from the Dock may not find `node` on their `PATH`. If the server fails to start, replace `node` with the absolute path printed by `command -v node`.

## Configuration

| Variable | Effect |
|---|---|
| `NORDVPN_BIN` | Absolute path of the `nordvpn` CLI. Otherwise the server searches `PATH`, `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`. |
| `NORDVPN_MCP_READ_ONLY=1` | Registers only the four reporting tools, so no agent can connect or disconnect. |

Pass them in your client's configuration, for example `claude mcp add --scope user -e NORDVPN_MCP_READ_ONLY=1 nordvpn -- node "$PWD/mcp/dist/index.js"`.

## Permissions and safety

- **Disconnect needs Accessibility for the host app.** macOS grants Accessibility to the application that runs the server: your terminal for Claude Code or the Codex CLI, otherwise Cursor, VS Code, Claude or Codex itself. Enable it in **System Settings → Privacy & Security → Accessibility** and restart the app. `nordvpn_run_doctor` reports whether it is granted.
- **Disconnecting exposes your real IP.** Keep confirmation on for connect and disconnect, or use `NORDVPN_MCP_READ_ONLY=1`, especially when an agent runs without approvals.
- **Public IPs reach the model.** `nordvpn_get_status` returns your public IP and ISP to the agent, and through it to its model provider. `nordvpn_run_doctor` omits them.
- **Waits stay under a minute.** Connect and disconnect accept at most 55 seconds of waiting, below the default 60-second tool timeout of clients such as Codex.

## Development

```sh
npm ci --ignore-scripts
npm test                                         # builds, then drives the server against a fake CLI
npx @modelcontextprotocol/inspector node dist/index.js   # interactive exploration
```

The tests start the built server over stdio and replace the CLI with `test/fixtures/nordvpn`, so they never change your VPN.
