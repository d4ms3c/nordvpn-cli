PREFIX ?= $(HOME)/.local

.PHONY: build test install uninstall xcode

build:
	swift build -c release

# Older Command Line Tools lack the swift-testing macros: run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`.
test:
	swift test

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
