# MCP server for AI agents

`nordvpn mcp` is a [Model Context Protocol](https://modelcontextprotocol.io) server built into the CLI. It lets Claude Code, Codex, Cursor, VS Code and other MCP clients check your NordVPN connection and, with your approval, connect or disconnect it.

It runs over stdio, inside the same binary: no Node.js or Python, no credentials, no open network port, and the same limits as the CLI.

[![Add to Cursor](https://cursor.com/deeplink/mcp-install-dark.svg)](https://cursor.com/en/install-mcp?name=nordvpn&config=eyJjb21tYW5kIjoibm9yZHZwbiIsImFyZ3MiOlsibWNwIl19)
[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install_server-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://insiders.vscode.dev/redirect?url=vscode%3Amcp%2Finstall%3F%257B%2522name%2522%253A%2522nordvpn%2522%252C%2522command%2522%253A%2522nordvpn%2522%252C%2522args%2522%253A%255B%2522mcp%2522%255D%257D)

The buttons need the `nordvpn` CLI [installed](../README.md#install) and on your `PATH`.

## Tools

| Tool | What it does | Changes the VPN |
|---|---|---|
| `nordvpn_get_status` | Tunnel state, server, public IP and whether NordVPN considers it protected | No |
| `nordvpn_list_countries` | Countries with server counts and cities, filtered and paginated | No |
| `nordvpn_list_servers` | Least loaded servers by country and group (informational) | No |
| `nordvpn_run_doctor` | App, profile, Accessibility, log and API checks | No |
| `nordvpn_connect` | Connect to the fastest server or a country, and verify it | **Yes** |
| `nordvpn_disconnect` | Disconnect through the app's menu | **Yes** |

The four reporting tools are annotated `readOnlyHint`. Connect and disconnect are annotated `destructiveHint`, so clients that honor annotations ask before running them. Connect and disconnect never run at the same time.

Things to ask your agent:

- "Am I on the VPN right now?"
- "Connect me to Germany, then check that my IP changed."
- "Which countries have servers in more than five cities?"
- "Why does disconnecting fail?" (the agent runs the doctor)

## Add it to your agent

Each command below assumes `nordvpn` is on your `PATH`. Apps started from the Dock may not see your shell's `PATH`: if the server does not start, replace `nordvpn` with the absolute path printed by `command -v nordvpn`.

### Claude Code

```sh
claude mcp add --scope user nordvpn -- nordvpn mcp
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
codex mcp add nordvpn -- nordvpn mcp
```

The three Codex surfaces share `~/.codex/config.toml`. Setting `default_tools_approval_mode = "writes"` makes Codex prompt only for tools not marked read-only, here connect and disconnect:

```toml
[mcp_servers.nordvpn]
command = "nordvpn"
args = ["mcp"]
default_tools_approval_mode = "writes"
```

### Cursor

Use the button above, or add to `~/.cursor/mcp.json` (all projects) or `.cursor/mcp.json` (one project):

```json
{
  "mcpServers": {
    "nordvpn": {
      "command": "nordvpn",
      "args": ["mcp"]
    }
  }
}
```

### VS Code (GitHub Copilot agent mode)

Use the button above, or run:

```sh
code --add-mcp '{"name":"nordvpn","command":"nordvpn","args":["mcp"]}'
```

In `.vscode/mcp.json`, VS Code uses `servers` as the top-level key, not `mcpServers`:

```json
{
  "servers": {
    "nordvpn": {
      "type": "stdio",
      "command": "nordvpn",
      "args": ["mcp"]
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

Claude Desktop starts from the Dock, so give it the absolute path, for example `/opt/homebrew/bin/nordvpn` or `/Users/you/.local/bin/nordvpn`.

## Read-only mode

`nordvpn mcp --read-only` offers only the four reporting tools, so no agent can connect or disconnect:

```sh
claude mcp add --scope user nordvpn -- nordvpn mcp --read-only
```

## Permissions and safety

- **Disconnect needs Accessibility for the host app.** macOS grants Accessibility to the application that runs the server: your terminal for Claude Code or the Codex CLI, otherwise Cursor, VS Code, Claude or Codex itself. Enable it in **System Settings → Privacy & Security → Accessibility** and restart the app. `nordvpn_run_doctor` reports whether it is granted.
- **Disconnecting exposes your real IP.** Keep confirmation on for connect and disconnect, or use `--read-only`, especially when an agent runs without approvals.
- **Public IPs reach the model.** `nordvpn_get_status` returns your public IP and ISP to the agent, and through it to its model provider. `nordvpn_run_doctor` omits them.
- **Waits stay under a minute.** Connect and disconnect accept at most 55 seconds of waiting, below the default 60-second tool timeout of clients such as Codex.

## Protocol support

The server implements the tools part of MCP: `initialize`, `ping`, `tools/list`, `tools/call` and request cancellation, over newline-delimited JSON-RPC on stdio. It negotiates protocol versions 2025-11-25, 2025-06-18, 2025-03-26 and 2024-11-05. Status and doctor results include `structuredContent` that matches their `outputSchema`.

To explore it interactively:

```sh
npx @modelcontextprotocol/inspector nordvpn mcp
```
