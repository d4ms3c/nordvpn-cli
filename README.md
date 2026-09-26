# nordvpn-cli

A command-line interface for the NordVPN app on macOS. NordVPN ships an official CLI only for Linux; this tool fills the gap on the Mac.

It does not replace the app, it drives it: your account, protocol, kill switch and auto-connect settings stay in NordVPN.app.

> **Unofficial.** This project is not affiliated with, endorsed by or supported by NordVPN or Nord Security. "NordVPN" is a trademark of its respective owner.

## Requirements

- macOS 13 or later
- [NordVPN for macOS](https://nordvpn.com/download/mac/), signed in and connected at least once
- Swift 6 (Xcode 16 or the Command Line Tools) to build

## Install

```sh
git clone https://github.com/d4ms3c/nordvpn-cli.git
cd nordvpn-cli
make install                  # release build into ~/.local/bin/nordvpn
make install PREFIX=/usr/local
```

Shell completion (zsh):

```sh
nordvpn --generate-completion-script zsh > ~/.zfunc/_nordvpn
```

## Usage

```sh
nordvpn                         # same as `nordvpn status`
nordvpn status [--json]         # state, server, public IP, uptime
nordvpn connect                 # fastest server
nordvpn connect italy           # also: it, uk, "united states", warsaw
nordvpn disconnect
nordvpn countries [filter]      # countries with server and city counts
nordvpn cities uk
nordvpn servers pl --group p2p  # least loaded servers (informational)
nordvpn ip [--json]             # public IP and whether it is protected
nordvpn open                    # bring the app to the front
nordvpn help <command>          # details and examples
```

### Accessibility permission

The app has no deep link for disconnecting, so `nordvpn disconnect` presses the app's own "Disconnect" menu item through the macOS Accessibility API. Allow your terminal app in **System Settings → Privacy & Security → Accessibility**. The other commands need no permission.

## How it works

| Task | Mechanism |
|---|---|
| Connect | The app's `nordvpn://connect[?country=xx]` deep link |
| Disconnect | Accessibility API: the app's "Disconnect" item in its menu bar extra or Dock menu |
| Tunnel state | SystemConfiguration (`SCNetworkConnection`) on the VPN profiles the app registers |
| Connect completion, server name | The app's local log in `~/Library/Group Containers/W5W395V82Y.group.com.nordvpn/Library/Caches/Logs` |
| Countries, cities, servers, IP | NordVPN's public API at `api.nordvpn.com`; the country list is cached for a day |

## Limitations

- **Country only.** The deep link accepts nothing but a country. A city connects to the fastest server of its country (with a warning). Server groups (P2P, Double VPN, Onion, Obfuscated) and specific servers cannot be selected; `servers` is informational.
- **No plain `scutil --nc stop`.** Stopping the system VPN profile directly is undone within seconds by its on-demand rule, which is why `disconnect` goes through the app.
- **Undocumented interfaces.** The deep link parameters and the log lines this tool reads are not public APIs. They were verified against NordVPN for macOS 10.10 and may change with app updates.

## Privacy

The CLI talks only to the NordVPN app on your Mac and to NordVPN's public API. It sends no credentials or telemetry anywhere, and it reads the app's log only to detect connection state and server name.

## Development

```sh
make build    # swift build -c release
make test     # needs Xcode: the Command Line Tools lack the swift-testing macro plugin
make xcode    # open the package in Xcode
```

- `Sources/NordVPNKit`: library (VPN profile state, app bridge, log reader, API client, location resolver)
- `Sources/nordvpn`: commands, built on swift-argument-parser

## License

[MIT](LICENSE)
