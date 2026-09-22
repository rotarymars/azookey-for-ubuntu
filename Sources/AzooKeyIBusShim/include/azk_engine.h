// A minimal C interface between the IBus engine (a GObject subclass, which
// needs C) and the Swift code that implements its behavior. Only plain C types
// cross this boundary, so Swift never has to import GLib or IBus headers.
#ifndef AZK_ENGINE_H
#define AZK_ENGINE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// An IBusEngine instance. IBus creates one per input context.
typedef struct _AzkEngine AzkEngine;

/// Callbacks into Swift. `ctx` is the value `create` returned for the engine.
typedef struct {
    void *(*create)(AzkEngine *engine);
    void (*destroy)(void *ctx);
    bool (*process_key_event)(void *ctx, uint32_t keyval, uint32_t keycode, uint32_t state, uint32_t unicode);
    void (*focus_in)(void *ctx);
    void (*focus_out)(void *ctx);
    void (*reset)(void *ctx);
    void (*enable)(void *ctx);
    void (*disable)(void *ctx);
    void (*set_content_type)(void *ctx, uint32_t purpose, uint32_t hints);
    void (*property_activate)(void *ctx, const char *name, uint32_t state);
    void (*candidate_clicked)(void *ctx, uint32_t index, uint32_t button, uint32_t state);
    void (*page_up)(void *ctx);
    void (*page_down)(void *ctx);
    void (*cursor_up)(void *ctx);
    void (*cursor_down)(void *ctx);
    /// Called once when the process is about to exit (bus lost or SIGTERM).
    void (*shutdown)(void);
} AzkCallbacks;

void azk_set_callbacks(const AzkCallbacks *callbacks);

/// Connects to ibus-daemon and runs the main loop until the bus disconnects
/// or SIGTERM/SIGINT arrives. With `launched_by_ibus`, claims the component's
/// bus name (ibus-daemon started us from the component XML); otherwise
/// registers the component itself, which is handy for development.
int azk_main(bool launched_by_ibus, const char *version);

// ---- Engine -> client ----

void azk_engine_commit_text(AzkEngine *engine, const char *text);

typedef enum {
    AZK_PREEDIT_UNDERLINE = 0,
    /// The conversion segment in focus.
    AZK_PREEDIT_HIGHLIGHT = 1,
} AzkPreeditStyle;

/// Offsets are in Unicode characters, as IBus counts them.
void azk_engine_preedit_begin(AzkEngine *engine);
void azk_engine_preedit_append(AzkEngine *engine, const char *text, AzkPreeditStyle style);
void azk_engine_preedit_end(AzkEngine *engine, uint32_t cursor);
void azk_engine_hide_preedit(AzkEngine *engine);

void azk_engine_lookup_begin(AzkEngine *engine, uint32_t page_size, bool with_labels);
void azk_engine_lookup_append(AzkEngine *engine, const char *candidate, const char *annotation);
void azk_engine_lookup_end(AzkEngine *engine, uint32_t cursor, bool cursor_visible);
void azk_engine_hide_lookup(AzkEngine *engine);

void azk_engine_set_auxiliary_text(AzkEngine *engine, const char *text);

/// Returns the text around the cursor (without the preedit) if the client
/// provides it, as a newly allocated string to release with azk_free().
char *azk_engine_dup_surrounding_text(AzkEngine *engine, uint32_t *cursor, uint32_t *anchor);
void azk_free(void *pointer);

// ---- Status menu (IBus properties) ----

typedef enum {
    AZK_PROP_NORMAL = 0,
    AZK_PROP_TOGGLE = 1,
    AZK_PROP_RADIO = 2,
    AZK_PROP_MENU = 3,
    AZK_PROP_SEPARATOR = 4,
} AzkPropType;

/// Builds the property tree: `parent` is NULL for top-level items or the key
/// of an earlier AZK_PROP_MENU item. Call register_properties at the end.
void azk_engine_props_begin(AzkEngine *engine);
void azk_engine_props_append(AzkEngine *engine, const char *parent, const char *key, AzkPropType type,
                             const char *label, const char *symbol, const char *tooltip, bool checked);
void azk_engine_props_register(AzkEngine *engine);

// ---- Main loop helpers ----

/// Calls `callback(data)` once after `milliseconds`; returns a source id.
uint32_t azk_timeout_add(uint32_t milliseconds, void (*callback)(void *data), void *data);
void azk_source_remove(uint32_t source_id);
/// Runs a command line asynchronously (e.g. the settings window).
bool azk_spawn_command_line(const char *command_line);

#ifdef __cplusplus
}
#endif

#endif
