## What's new

- `nordvpn doctor` checks app installation, VPN profiles, Accessibility, readable logs and API access. Use `--offline --json` for a local diagnostic report without IP addresses or local paths.
- Connection confirmation uses one wait budget and distinguishes a connected tunnel from failed IP verification or an unexpected country.
- Missing profiles no longer appear as an already disconnected VPN.
- Invalid connect/disconnect timeouts fail before interacting with the app.
- Disconnect reports missing Accessibility access without triggering a system permission dialog.
- Release automation builds Apple Silicon and Intel archives with shell completions, checksums and a Homebrew formula.
- `nordvpn mcp` serves the Model Context Protocol, so Claude Code, Codex, Cursor, VS Code and other agents can check the VPN and, with your approval, connect or disconnect. It is part of the binary: no Node.js or other runtime. `--read-only` offers only the reporting tools. See [docs/mcp.md](https://github.com/d4ms3c/nordvpn-cli/blob/main/docs/mcp.md).

## Compatibility and limitations

Requires macOS 13+ and the installed NordVPN app, signed in and connected at least once. The underlying integration was originally checked against NordVPN 10.10. Disconnect currently recognizes English menu labels only and needs Accessibility permission. Connection targets are countries, not individual cities or servers. API verification is not a comprehensive DNS/IPv6 leak test.

Binaries are not Developer ID signed or notarized. Build from source if your environment requires a different distribution trust policy.
