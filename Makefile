# ibus-azookey: build, test and install.
#
#   make                 build llama.cpp, fetch the model, build the engine and
#                        stage the installation tree under build/stage
#   make test            unit tests
#   make e2e             end-to-end test against a private ibus-daemon
#   sudo make install    copy the staged tree into $(DESTDIR)/ (no building)
#   sudo make uninstall
#   make deb             build a .deb from the staged tree

VERSION      := 0.1.0
PREFIX       ?= /usr
DESTDIR      ?=
MODEL        ?= small
CONFIG       ?= release

# A swift on PATH wins; otherwise the newest toolchain unpacked by
# scripts/install-swift.sh.
SWIFT        ?= $(or $(shell command -v swift 2>/dev/null),$(lastword $(sort $(wildcard $(HOME)/.local/share/swift-toolchains/swift-*/usr/bin/swift))))

LIBDIR       := $(PREFIX)/lib/ibus-azookey
DATADIR      := $(PREFIX)/share/ibus-azookey
COMPONENTDIR := $(PREFIX)/share/ibus/component
DOCDIR       := $(PREFIX)/share/doc/ibus-azookey
STAGE        := build/stage

.PHONY: all llama model engine stage test e2e install uninstall deb clean check-swift

all: stage

check-swift:
	@test -x "$(SWIFT)" || { echo "Swift 6.1+ not found; run scripts/install-swift.sh or set SWIFT=/path/to/swift" >&2; exit 1; }

llama: build/lib/libllama.so

build/lib/libllama.so: scripts/build-llama.sh
	./scripts/build-llama.sh

model:
	./scripts/fetch-model.sh $(MODEL)

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
		$(STAGE)$(COMPONENTDIR) $(STAGE)$(DOCDIR)/licenses
	install -m 755 $(BIN)/ibus-engine-azookey $(STAGE)$(LIBDIR)/
	install -m 755 tools/ibus-setup-azookey $(STAGE)$(LIBDIR)/
	strip --strip-unneeded $(STAGE)$(LIBDIR)/ibus-engine-azookey
	cp -r $(BIN)/*.resources $(STAGE)$(LIBDIR)/
	install -m 644 build/lib/*.so $(STAGE)$(LIBDIR)/lib/
	cp -r build/models/zenz-v3.2-$(MODEL) $(STAGE)$(DATADIR)/models/
	install -m 644 data/icons/ibus-azookey.svg $(STAGE)$(DATADIR)/icons/
	sed -e 's|@LIBDIR@|$(LIBDIR)|g' -e 's|@DATADIR@|$(DATADIR)|g' -e 's|@VERSION@|$(VERSION)|g' \
		data/azookey.xml.in > $(STAGE)$(COMPONENTDIR)/azookey.xml
	install -m 644 LICENSE THIRD_PARTY_NOTICES.md $(STAGE)$(DOCDIR)/
	install -m 644 data/licenses/Apache-2.0.txt $(STAGE)$(DOCDIR)/licenses/
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
	rm -f $(DESTDIR)$(COMPONENTDIR)/azookey.xml

deb: stage
	./scripts/build-deb.sh $(VERSION) $(STAGE)

clean:
	rm -rf .build build/stage build/*.deb
