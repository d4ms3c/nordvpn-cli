#!/usr/bin/env python3
"""Generate a versioned Homebrew formula from the actual release archives."""

import hashlib
import re
import sys
from pathlib import Path


def main():
    version = sys.argv[1]
    if not re.fullmatch(r"v\d+\.\d+\.\d+", version):
        raise SystemExit("Expected a stable version tag, e.g. v0.2.0")
    archives = Path("dist")
    checksums = {
        arch: hashlib.sha256(
            (archives / f"nordvpn-macos-{arch}.tar.gz").read_bytes()
        ).hexdigest()
        for arch in ("arm64", "x86_64")
    }
    base = f"https://github.com/d4ms3c/nordvpn-cli/releases/download/{version}"
    formula = f'''class NordvpnCli < Formula
  desc "Control the existing NordVPN macOS app from the terminal"
  homepage "https://github.com/d4ms3c/nordvpn-cli"
  version "{version[1:]}"
  license "MIT"
  depends_on macos: :ventura

  on_arm do
    url "{base}/nordvpn-macos-arm64.tar.gz"
    sha256 "{checksums["arm64"]}"
  end

  on_intel do
    url "{base}/nordvpn-macos-x86_64.tar.gz"
    sha256 "{checksums["x86_64"]}"
  end

  def install
    bin.install "nordvpn"
    bash_completion.install "completions/nordvpn.bash" => "nordvpn"
    zsh_completion.install "completions/nordvpn.zsh" => "_nordvpn"
    fish_completion.install "completions/nordvpn.fish" => "nordvpn.fish"
  end

  test do
    assert_equal version.to_s, shell_output("#{{bin}}/nordvpn --version").strip
    assert_match "Check installation", shell_output("#{{bin}}/nordvpn doctor --help")
  end
end
'''
    (archives / "nordvpn-cli.rb").write_text(formula)


if __name__ == "__main__":
    main()
