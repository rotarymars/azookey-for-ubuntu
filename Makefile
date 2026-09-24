# ibus-azookey: build, test and install.
#
#   make                 build llama.cpp, fetch the model, build the engine and
#                        stage the installation tree under build/stage
#   make test            unit tests
#   make e2e             end-to-end test against a private ibus-daemon
#   sudo make install    copy the staged tree into $(DESTDIR)/ (no building)
#   sudo make uninstall
#   make deb             build a .deb from the staged tree
#   make release         build a .deb that runs on any x86-64 CPU with AVX2

VERSION      := 0.1.2
PREFIX       ?= /usr
DESTDIR      ?=
# A model id from data/models.json to bundle (small/xsmall mean zenz-v3.2).
MODEL        ?= zenz-v3.2-small
MODEL_ID     := $(if $(filter small xsmall,$(MODEL)),zenz-v3.2-$(MODEL),$(MODEL))
CONFIG       ?= release
# 1: build llama.cpp for any x86-64-v3 CPU instead of this machine's CPU.
LLAMA_PORTABLE ?= 0
LLAMA_MODE   := $(if $(filter 1,$(LLAMA_PORTABLE)),portable,native)

# A swift on PATH wins; otherwise the newest toolchain unpacked by
# scripts/install-swift.sh.
SWIFT        ?= $(or $(shell command -v swift 2>/dev/null),$(lastword $(sort $(wildcard $(HOME)/.local/share/swift-toolchains/swift-*/usr/bin/swift))))

LIBDIR       := $(PREFIX)/lib/ibus-azookey
DATADIR      := $(PREFIX)/share/ibus-azookey
COMPONENTDIR := $(PREFIX)/share/ibus/component
DOCDIR       := $(PREFIX)/share/doc/ibus-azookey
# GNOME Settings finds an engine's preferences as ibus-setup-<engine>.desktop.
APPDIR       := $(PREFIX)/share/applications
STAGE        := build/stage

.PHONY: all llama model engine stage test e2e install uninstall deb release clean check-swift

all: stage

check-swift:
	@test -x "$(SWIFT)" || { echo "Swift 6.1+ not found; run scripts/install-swift.sh or set SWIFT=/path/to/swift" >&2; exit 1; }

# The marker file names the CPU target, so switching LLAMA_PORTABLE rebuilds.
llama: build/lib/.llama-$(LLAMA_MODE)

build/lib/.llama-$(LLAMA_MODE): scripts/build-llama.sh
	LLAMA_PORTABLE=$(LLAMA_PORTABLE) ./scripts/build-llama.sh

model:
	./scripts/fetch-model.sh $(MODEL_ID)

# The Swift runtime is linked statically so the installed engine does not
# depend on the toolchain. With C++ interop, libswiftCxx*.a only live in the
# dynamic runtime directory (swiftlang/swift#78003), hence the extra -L.
engine: check-swift llama
	$(eval SWIFT_RUNTIME_DIR := $(shell "$(SWIFT)" -print-target-info | python3 -c 'import json, sys; print(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"][0])'))
	"$(SWIFT)" build -c $(CONFIG) --product ibus-engine-azookey --static-swift-stdlib -Xlinker -L"$(SWIFT_RUNTIME_DIR)"

stage: engine model
	$(eval BIN := $(shell "$(SWIFT)" build -c $(CONFIG) --show-bin-path))
	rm -rf $(STAGE)
	install -d $(STAGE)$(LIBDIR)/lib $(STAGE)$(DATADIR)/models $(STAGE)$(DATADIR)/icons \
		$(STAGE)$(COMPONENTDIR) $(STAGE)$(DOCDIR)/licenses $(STAGE)$(APPDIR)
	install -m 755 $(BIN)/ibus-engine-azookey $(STAGE)$(LIBDIR)/
	install -m 755 tools/ibus-setup-azookey $(STAGE)$(LIBDIR)/
	strip --strip-unneeded $(STAGE)$(LIBDIR)/ibus-engine-azookey
	cp -r $(BIN)/*.resources $(STAGE)$(LIBDIR)/
	install -m 644 build/lib/*.so $(STAGE)$(LIBDIR)/lib/
	cp -r build/models/$(MODEL_ID) $(STAGE)$(DATADIR)/models/
	install -m 644 data/models.json $(STAGE)$(DATADIR)/
	install -m 644 data/icons/ibus-azookey.svg $(STAGE)$(DATADIR)/icons/
	sed -e 's|@LIBDIR@|$(LIBDIR)|g' -e 's|@DATADIR@|$(DATADIR)|g' -e 's|@DOCDIR@|$(DOCDIR)|g' \
		-e 's|@VERSION@|$(VERSION)|g' \
		data/azookey.xml.in > $(STAGE)$(COMPONENTDIR)/azookey.xml
	sed -e 's|@LIBDIR@|$(LIBDIR)|g' -e 's|@DATADIR@|$(DATADIR)|g' \
		data/ibus-setup-azookey.desktop.in > $(STAGE)$(APPDIR)/ibus-setup-azookey.desktop
	install -m 644 README.md README.ja.md LICENSE THIRD_PARTY_NOTICES.md $(STAGE)$(DOCDIR)/
	install -m 644 data/licenses/Apache-2.0.txt $(STAGE)$(DOCDIR)/licenses/
	chmod -R u+rwX,go=rX $(STAGE)
	@echo ">> staged into $(STAGE)$(PREFIX)"

test: check-swift llama
	LD_LIBRARY_PATH=$(CURDIR)/build/lib "$(SWIFT)" test

e2e: stage
	dbus-run-session --config-file=tests/e2e/session.conf -- ./tests/e2e/run.sh $(STAGE)$(PREFIX)

# Deliberately does not build: run `make` as your user first, then only
# the copy step needs root.
install:
	@test -f $(STAGE)$(LIBDIR)/ibus-engine-azookey || { echo "run 'make' first (as your user, not root)" >&2; exit 1; }
	@test "$(PREFIX)" = /usr || test -n "$(DESTDIR)" || echo "note: ibus only reads components from /usr/share/ibus/component unless IBUS_COMPONENT_PATH is set" >&2
	cd $(STAGE)$(PREFIX) && find . -type d -exec install -d -m 755 "$(DESTDIR)$(PREFIX)/{}" \;
	cd $(STAGE)$(PREFIX) && find . -type f -perm -u+x -exec install -m 755 "{}" "$(DESTDIR)$(PREFIX)/{}" \;
	cd $(STAGE)$(PREFIX) && find . -type f ! -perm -u+x -exec install -m 644 "{}" "$(DESTDIR)$(PREFIX)/{}" \;
	@echo ">> installed. Now run (as your user): ibus write-cache && ibus restart"

uninstall:
	rm -rf $(DESTDIR)$(LIBDIR) $(DESTDIR)$(DATADIR) $(DESTDIR)$(DOCDIR)
	rm -f $(DESTDIR)$(COMPONENTDIR)/azookey.xml $(DESTDIR)$(APPDIR)/ibus-setup-azookey.desktop

deb: stage
	rm -f build/ibus-azookey_*.deb
	./scripts/build-deb.sh $(VERSION) $(STAGE)

# The package to publish: same as deb, but llama.cpp is built for any x86-64
# CPU with AVX2 rather than for this machine (which may have newer instructions).
release:
	$(MAKE) LLAMA_PORTABLE=1 deb

clean:
	rm -rf .build build/stage build/*.deb
