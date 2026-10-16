PREFIX ?= $(HOME)/.local

.PHONY: build test install uninstall xcode

build:
	swift build -c release

# swift-testing needs the Xcode toolchain; the Command Line Tools lack its macro plugin.
test:
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

install: build
	install -d $(PREFIX)/bin
	install .build/release/nordvpn $(PREFIX)/bin/nordvpn

uninstall:
	rm -f $(PREFIX)/bin/nordvpn

xcode:
	open -a Xcode Package.swift

.PHONY: smoke package
smoke: build
	python3 scripts/smoke-test.py .build/release/nordvpn

package:
	bash scripts/package-release.sh

.PHONY: mcp mcp-test
mcp:
	npm --prefix mcp ci --ignore-scripts
	npm --prefix mcp run build
	@echo "MCP server: node $(CURDIR)/mcp/dist/index.js (see mcp/README.md)"

mcp-test:
	npm --prefix mcp ci --ignore-scripts
	npm --prefix mcp test
