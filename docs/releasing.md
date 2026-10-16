# Maintainer release checklist

1. Update the CLI version, smoke-test expectation and release notes together.
2. Run `make test` and `make smoke`.
3. Check connect, country switching and disconnect manually on an opted-in test machine. Record macOS version, architecture, NordVPN version/distribution and app language. CI does not test a live VPN.
4. Push a matching stable tag, e.g. `v0.2.0`. The Release workflow tests both architectures and creates a **draft** with archives, SHA256SUMS and a formula. `workflow_dispatch` on a branch tests packaging without creating a release.
5. Review the draft artifacts, verify the embedded version matches the tag, and check installation on both architectures. Publish the draft after those checks.
6. Copy the generated `nordvpn-cli.rb` into `Formula/` in the `d4ms3c/homebrew-tap` repository (create that repository if it does not exist). Test with `brew install d4ms3c/tap/nordvpn-cli` and `brew test d4ms3c/tap/nordvpn-cli` before promoting this install command in the README. The formula URLs require a published release.

The initial pipeline provides unsigned binaries, not Developer ID signing or notarization. Do not document older macOS versions as tested merely because the deployment target is macOS 13.
