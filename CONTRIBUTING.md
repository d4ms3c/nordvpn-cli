# Contributing

Start with an issue describing the user workflow or reproducible failure. Small fixes, documentation examples and compatibility reports are welcome.

Run `make build`, `make test` (requires a licensed Xcode installation) and `make smoke`. Smoke tests do not connect or disconnect the VPN. For changes to app integration, report a manual test with macOS version, architecture, NordVPN version and app language. Never run live connection tests on someone else's session without authorization.

Keep logs, public IP addresses, account data and local paths out of fixtures and issue reports. Add regression tests for changed behavior. Never claim a supported app version or language without testing it.

See [release instructions](docs/releasing.md) for packaging and Homebrew distribution.
