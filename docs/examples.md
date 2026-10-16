# Automation examples

These examples assume `nordvpn` is on your PATH. They use the existing app and do not create an independent VPN tunnel.

## Check the reported public IP

Requires `jq`. A successful `ip` command alone does not mean the IP is protected:

```sh
set -o pipefail
nordvpn ip --json | jq -e '.protected == true' >/dev/null
```

This is a point-in-time check, not a guarantee about later traffic or a leak test. Keep the app's own kill switch configured as needed.

## Raycast script command

Save as `nordvpn-italy.sh`, make executable, and add its directory to Raycast Script Commands. Adjust the binary path if installed elsewhere.

```bash
#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Connect NordVPN to Italy
# @raycast.mode fullOutput
# @raycast.packageName NordVPN
exec "$HOME/.local/bin/nordvpn" connect italy
```

## SwiftBar status

Save as `nordvpn.1m.sh` in your SwiftBar plugin folder and make it executable. This checks the public IP once a minute, so it contacts NordVPN's API. Requires `jq` on the plugin's PATH; adjust the executable path for your installation.

```bash
#!/bin/bash
set -o pipefail
if "$HOME/.local/bin/nordvpn" ip --json | jq -e '.protected == true' >/dev/null; then
  echo 'VPN: protected'
else
  echo 'VPN: unprotected or unknown'
fi
```

## Share diagnostics

```sh
nordvpn doctor --offline --json > nordvpn-diagnostics.json
```

A report is still written when a check fails and the command exits with status 1. The offline report excludes API reachability. Review it before attaching it to an issue.
