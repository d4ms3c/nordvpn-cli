# AGENTS.md

Instructions for AI coding agents working on this repository. Humans: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Project

`nordvpn` is an unofficial Swift CLI that drives the installed NordVPN macOS app: deep link to connect, Accessibility API to disconnect, SystemConfiguration for tunnel state, the app's log for server names, NordVPN's public API for countries and the public IP. `nordvpn mcp` serves the same features to AI agents over the Model Context Protocol.

## Layout

| Path | Contents |
|---|---|
| `Sources/NordVPNKit` | Library: VPN profiles, app bridge, log reader, API client, location resolver, connection verification. Never prints. |
| `Sources/NordVPNMCP` | MCP over stdio: `MCPServer` (JSON-RPC), `StdioSession` (transport), `Tool` and `ToolParameter`, the NordVPN tools behind the `NordVPNControl` protocol. Never prints to stdout. |
| `Sources/nordvpn` | Commands on swift-argument-parser. The only target that writes to stdout. |
| `Tests/` | swift-testing. `NordVPNMCPTests` drives the server against `FakeNordVPN`. |
| `scripts/smoke-test.py` | CLI and MCP contracts against the built binary. |
| `docs/` | MCP guide, automation examples, release notes and checklist, README images. |

## Commands

```sh
make build   # release build
make test    # unit tests; no VPN changes
make smoke   # contracts of the built binary, including an MCP session; no VPN changes
```

Before handing off, all three must pass. If the Command Line Tools lack swift-testing, run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`. With the Swift 6.4 Command Line Tools, test compilation sometimes fails with `plugin for module 'TestingMacros' not found`: that is the toolchain, not the code, so run `make test` again.

## Rules

- **Never change the real VPN.** Do not run `nordvpn connect`, `nordvpn disconnect` or the MCP connect and disconnect tools unless the user asks for it in the current session. Tests use `FakeNordVPN`; reading commands (`status`, `countries`, `servers`, `doctor`) are fine.
- **Keep stdout clean for MCP.** On `nordvpn mcp`, stdout carries only JSON-RPC lines. Diagnostics go to stderr.
- **No new dependencies** without the maintainer's agreement. The binary depends only on swift-argument-parser, and the MCP protocol code is part of this repository on purpose.
- **Keep CLI and MCP on shared code.** Logic that both need (connection verification, disconnect, status, location resolution) lives in `NordVPNKit`, not in a command.
- **MCP tool contract.** Tool names, parameters, annotations and output shapes are a public interface. Change them together with `docs/mcp.md`, the tests and the smoke test. Network-changing tools stay `destructiveHint: true`, serialized and hidden by `--read-only`. Waits stay at or below 55 seconds.
- **Versions.** The version in `Sources/nordvpn/NordVPN.swift`, `VERSION` in `scripts/smoke-test.py` and `docs/release-notes.md` change together; see `docs/releasing.md`.
- **Privacy.** No real IP addresses, logs, account data or local paths in code, fixtures, docs or issues. Use 203.0.113.0/24 for example addresses.
- **Claims.** Do not document an app version, language or client as supported unless it was tested; say what was checked.
- **Swift 6 language mode** with strict concurrency: shared types are `Sendable`.
