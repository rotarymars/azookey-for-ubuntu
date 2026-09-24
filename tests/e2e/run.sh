#!/usr/bin/env bash
# End-to-end test: start the staged engine under a private ibus-daemon and type
# into it with a scripted IBus client (client.py).
#
# Run it through `make e2e`, which wraps it in dbus-run-session. Everything is
# isolated from the desktop's IBus: a private D-Bus session, a private daemon
# address, temporary XDG directories (config, learning data, IBus cache) and
# in-memory GSettings.
#
# Usage: dbus-run-session --config-file=tests/e2e/session.conf -- tests/e2e/run.sh build/stage/usr
set -euo pipefail

STAGED_PREFIX="$(cd "$1" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
DAEMON_PID=""
cleanup() {
    if [ -n "$DAEMON_PID" ]; then
        kill "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
    fi
    if [ -n "${KEEP_E2E_TMP:-}" ]; then
        echo "kept $TMP"
    else
        rm -rf "$TMP"
    fi
}
trap cleanup EXIT

export XDG_CONFIG_HOME="$TMP/config"
export XDG_CACHE_HOME="$TMP/cache"
export XDG_DATA_HOME="$TMP/data"
export GSETTINGS_BACKEND=memory
export GIO_USE_VFS=local
unset DISPLAY WAYLAND_DISPLAY
export IBUS_ADDRESS_FILE="$TMP/ibus-address"
export IBUS_COMPONENT_PATH="$TMP/component"
export IBUS_ADDRESS="unix:path=$TMP/ibus.sock"
mkdir -p "$IBUS_COMPONENT_PATH" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"

# A model "downloaded" by the settings window, to test switching models.
if [ -n "${E2E_DOWNLOADED_MODEL:-}" ]; then
    mkdir -p "$XDG_DATA_HOME/ibus-azookey/models"
    cp -r "$E2E_DOWNLOADED_MODEL" "$XDG_DATA_HOME/ibus-azookey/models/"
fi

# The staged component points at /usr; aim it at the staged engine instead.
sed "s|/usr/lib/ibus-azookey|$STAGED_PREFIX/lib/ibus-azookey|g" \
    "$STAGED_PREFIX/share/ibus/component/azookey.xml" > "$IBUS_COMPONENT_PATH/azookey.xml"
# The keyboard-layout engines, to test switching input sources.
cp /usr/share/ibus/component/simple.xml "$IBUS_COMPONENT_PATH/"

# --cache=refresh makes the daemon serialize every component into its registry
# cache (inside $TMP), as the desktop daemon does; that is where a component
# with a missing field shows up as a GLib assertion.
ibus-daemon --single --panel=disable --emoji-extension=disable --config=disable \
    --cache=refresh --address="$IBUS_ADDRESS" --verbose > "$TMP/daemon.log" 2>&1 &
DAEMON_PID=$!
for _ in $(seq 100); do
    [ -S "$TMP/ibus.sock" ] && break
    sleep 0.1
done
[ -S "$TMP/ibus.sock" ] || { echo "ibus-daemon did not start"; cat "$TMP/daemon.log"; exit 1; }

status=0
/usr/bin/python3 "$HERE/client.py" || status=$?
if grep -E "assertion .* failed|CRITICAL" "$TMP/daemon.log"; then
    echo "FAIL ibus-daemon or the engine logged GLib assertions (see above)"
    status=1
fi
# client.py switched to the downloaded model and then to a missing one.
if [ -n "${E2E_DOWNLOADED_MODEL:-}" ]; then
    downloaded="$XDG_DATA_HOME/ibus-azookey/models/$(basename "$E2E_DOWNLOADED_MODEL")"
    if grep -q "Zenzai model: $downloaded" "$TMP/daemon.log"; then
        echo "ok   the engine loaded the downloaded model"
    else
        echo "FAIL the engine never loaded the downloaded model"
        status=1
    fi
    if grep -q "zenz-v3.1-small is not installed; using zenz-v3.2-small" "$TMP/daemon.log"; then
        echo "ok   a missing model falls back to the bundled one"
    else
        echo "FAIL selecting a missing model did not fall back to the bundled one"
        status=1
    fi
fi
if [ $status -ne 0 ]; then
    echo "---- ibus-daemon / engine log ----"
    cat "$TMP/daemon.log"
fi
exit $status
