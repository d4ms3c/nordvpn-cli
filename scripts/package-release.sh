#!/bin/bash
set -euo pipefail

arch="$(uname -m)"
case "$arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
if [[ "${GITHUB_REF_TYPE:-}" == tag ]]; then
  version="$("$binary_dir/nordvpn" --version)"
  if [[ "v$version" != "$GITHUB_REF_NAME" ]]; then
    echo "Tag $GITHUB_REF_NAME does not match CLI version $version" >&2
    exit 1
  fi
fi
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/completions" dist
install "$binary_dir/nordvpn" "$stage/nordvpn"
cp LICENSE README.md "$stage/"
for shell in bash zsh fish; do
  "$stage/nordvpn" --generate-completion-script "$shell" > "$stage/completions/nordvpn.$shell"
done
tar -czf "dist/nordvpn-macos-$arch.tar.gz" -C "$stage" nordvpn LICENSE README.md completions
