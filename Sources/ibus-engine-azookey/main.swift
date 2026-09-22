import AzooKeyCore
import AzooKeyIBusShim
import Foundation

// ibus-engine-azookey [--ibus]
//   --ibus  started by ibus-daemon from the component XML. Without it the
//           engine registers itself with the running daemon (development).

if CommandLine.arguments.contains("--version") {
    print("ibus-engine-azookey \(PackageMetadata.version)")
    exit(0)
}

// All callbacks arrive on the main thread, from the GLib main loop.
private func controller(_ context: UnsafeMutableRawPointer?) -> EngineController {
    Unmanaged<EngineController>.fromOpaque(context!).takeUnretainedValue()
}

var callbacks = AzkCallbacks()
callbacks.create = { engine in
    nonisolated(unsafe) let engine = engine!
    let controller = MainActor.assumeIsolated { EngineController(engine: engine) }
    return Unmanaged.passRetained(controller).toOpaque()
}
callbacks.destroy = { context in
    MainActor.assumeIsolated {
        let unmanaged = Unmanaged<EngineController>.fromOpaque(context!)
        unmanaged.takeUnretainedValue().destroy()
        unmanaged.release()
    }
}
callbacks.process_key_event = { context, keyval, keycode, state, unicode in
    MainActor.assumeIsolated {
        controller(context).processKey(keyval: keyval, keycode: keycode, state: state, unicode: unicode)
    }
}
callbacks.focus_in = { context in
    MainActor.assumeIsolated { controller(context).focusIn() }
}
callbacks.focus_out = { context in
    MainActor.assumeIsolated { controller(context).focusOut() }
}
callbacks.reset = { context in
    MainActor.assumeIsolated { controller(context).reset() }
}
callbacks.enable = { context in
    MainActor.assumeIsolated { controller(context).enable() }
}
callbacks.disable = { context in
    MainActor.assumeIsolated { controller(context).disable() }
}
callbacks.set_content_type = { context, purpose, hints in
    MainActor.assumeIsolated { controller(context).setContentType(purpose: purpose, hints: hints) }
}
callbacks.property_activate = { context, name, state in
    MainActor.assumeIsolated { controller(context).propertyActivate(name: String(cString: name!), state: state) }
}
callbacks.candidate_clicked = { context, index, _, _ in
    MainActor.assumeIsolated { controller(context).candidateClicked(index: index) }
}
callbacks.page_up = { context in
    MainActor.assumeIsolated { controller(context).moveSelection(by: -controller(context).pageSize) }
}
callbacks.page_down = { context in
    MainActor.assumeIsolated { controller(context).moveSelection(by: controller(context).pageSize) }
}
callbacks.cursor_up = { context in
    MainActor.assumeIsolated { controller(context).moveSelection(by: -1) }
}
callbacks.cursor_down = { context in
    MainActor.assumeIsolated { controller(context).moveSelection(by: 1) }
}
callbacks.shutdown = {
    MainActor.assumeIsolated { App.shared.commitLearningData() }
}
azk_set_callbacks(&callbacks)

Log.info("starting \(PackageMetadata.version)")
exit(azk_main(CommandLine.arguments.contains("--ibus"), PackageMetadata.version))
