#!/usr/bin/python3
"""Types into the azookey engine through a real IBus input context.

Started by run.sh against a private ibus-daemon (IBUS_ADDRESS is set there).
Prints what the engine sends back and exits non-zero on the first failure.
"""

import sys
import time

import gi

gi.require_version("IBus", "1.0")
from gi.repository import GLib, IBus  # noqa: E402

KEY = {
    "space": IBus.KEY_space,
    "Return": IBus.KEY_Return,
    "BackSpace": IBus.KEY_BackSpace,
    "Escape": IBus.KEY_Escape,
    "Down": IBus.KEY_Down,
    "F7": IBus.KEY_F7,
    "Home": IBus.KEY_Home,
}


class Client:
    def __init__(self):
        IBus.init()
        self.bus = IBus.Bus()
        if not self.bus.is_connected():
            sys.exit("cannot connect to the private ibus-daemon")
        self.context = self.bus.create_input_context("azookey-e2e")
        self.context.set_capabilities(
            IBus.Capabilite.PREEDIT_TEXT
            | IBus.Capabilite.AUXILIARY_TEXT
            | IBus.Capabilite.LOOKUP_TABLE
            | IBus.Capabilite.FOCUS
            | IBus.Capabilite.PROPERTY
            | IBus.Capabilite.SURROUNDING_TEXT
        )
        self.committed = []
        self.preedit = ""
        self.candidates = []
        self.properties = {}
        self.context.connect("commit-text", lambda _c, text: self.committed.append(text.get_text()))
        self.context.connect("update-preedit-text", self._on_preedit)
        self.context.connect("hide-preedit-text", lambda _c: setattr(self, "preedit", ""))
        self.context.connect("update-lookup-table", self._on_lookup)
        self.context.connect("hide-lookup-table", lambda _c: setattr(self, "candidates", []))
        self.context.connect("register-properties", self._on_properties)
        self.context.focus_in()

    def _on_preedit(self, _context, text, _cursor, visible):
        self.preedit = text.get_text() if visible else ""

    def _on_lookup(self, _context, table, visible):
        count = table.get_number_of_candidates()
        self.candidates = [table.get_candidate(i).get_text() for i in range(count)] if visible else []

    def _on_properties(self, _context, props):
        self.properties = {}

        def walk(prop_list):
            index = 0
            while (prop := prop_list.get(index)) is not None:
                self.properties[prop.get_key()] = prop
                walk(prop.get_sub_props())
                index += 1

        walk(props)

    def pump(self, seconds=0.05):
        end = time.monotonic() + seconds
        context = GLib.MainContext.default()
        while time.monotonic() < end:
            while context.iteration(False):
                pass
            time.sleep(0.005)

    def press(self, key, state=0):
        keyval = KEY.get(key) if isinstance(key, str) and len(key) > 1 else ord(key)
        start = time.monotonic()
        handled = self.context.process_key_event(keyval, 0, state)
        elapsed = (time.monotonic() - start) * 1000
        self.context.process_key_event(keyval, 0, state | IBus.ModifierType.RELEASE_MASK)
        self.pump()
        return handled, elapsed

    def type(self, text):
        latencies = [self.press(c)[1] for c in text]
        return latencies

    def take_committed(self):
        text = "".join(self.committed)
        self.committed.clear()
        return text


failures = 0


def check(label, condition, detail=""):
    global failures
    print(("ok   " if condition else "FAIL ") + label + (f"  [{detail}]" if detail else ""))
    if not condition:
        failures += 1


def main():
    client = Client()
    client.context.set_engine("azookey")
    for _ in range(100):
        client.pump(0.1)
        engine = client.context.get_engine()
        if engine is not None and engine.get_name() == "azookey":
            break
    engine = client.context.get_engine()
    check("engine is active", engine is not None and engine.get_name() == "azookey")

    # First key loads the dictionary and the model.
    handled, first_latency = client.press("k")
    check("first key is handled", handled, f"{first_latency:.0f} ms incl. loading")
    latencies = client.type("youhaiitenki")
    check("preedit shows hiragana", client.preedit == "きょうはいいてんき", client.preedit)
    check("preview shows a conversion", client.candidates[:1] == ["今日はいい天気"], str(client.candidates[:1]))
    print(f"     per-key latency: avg {sum(latencies) / len(latencies):.1f} ms, max {max(latencies):.1f} ms")

    client.press("space")
    check("space converts", client.preedit == "今日はいい天気", client.preedit)
    client.press("Return")
    check("enter commits", client.take_committed() == "今日はいい天気")
    check("preedit cleared", client.preedit == "")

    client.type("kisha")
    client.press("space")
    client.press("space")
    check("second space opens the candidate list", len(client.candidates) >= 3, " ".join(client.candidates[:6]))
    expected = client.candidates[1] if len(client.candidates) > 1 else None
    client.press("2")
    check("number key picks a candidate", client.take_committed() == expected, expected or "")

    client.type("kyou")
    client.press("F7")
    check("F7 commits katakana", client.take_committed() == "キョウ")

    client.type("ka")
    handled, _ = client.press("Home")
    check("Home is swallowed while composing", handled and client.preedit == "か")
    client.press("Escape")
    check("escape cancels", client.preedit == "" and client.take_committed() == "")
    handled, _ = client.press("BackSpace")
    check("backspace passes through when idle", not handled)

    client.context.set_surrounding_text(IBus.Text.new_from_string("昨日は"), 3, 3)
    client.type("amedeshita")
    client.press("space")
    check("conversion with surrounding text", client.preedit != "", client.preedit)
    client.press("Return")
    client.take_committed()

    check("InputMode property registered", "InputMode" in client.properties)
    symbol = client.properties["InputMode"].get_symbol().get_text() if "InputMode" in client.properties else ""
    check("indicator shows あ", symbol == "あ", symbol)
    learning = client.properties.get("Learning.inputAndOutput")
    check("learning is on by default", learning is not None and learning.get_state() == IBus.PropState.CHECKED)

    client.context.property_activate("InputMode.Direct", IBus.PropState.CHECKED)
    client.pump(0.2)
    handled, _ = client.press("a")
    check("direct mode passes keys through", not handled)
    client.context.property_activate("InputMode.Hiragana", IBus.PropState.CHECKED)
    client.pump(0.2)

    client.type("tesuto")
    client.context.focus_out()
    client.pump(0.3)
    check("focus out commits the preedit", client.take_committed() == "てすと")
    client.context.focus_in()
    client.pump(0.2)
    handled, _ = client.press("a")
    check("typing works after refocus", handled and client.preedit == "あ", client.preedit)

    print(f"{failures} failure(s)")
    return 1 if failures else 0


sys.exit(main())
