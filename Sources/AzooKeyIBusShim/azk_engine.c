#include "azk_engine.h"

#include <glib-unix.h>
#include <ibus.h>
#include <signal.h>
#include <sys/eventfd.h>

#define AZK_COMPONENT_NAME "org.freedesktop.IBus.AzooKey"
#define AZK_ENGINE_NAME "azookey"

/* Colors of the focused conversion segment, for clients that honor preedit
 * attributes (X11 and Qt applications; GNOME Shell only shows the cursor). */
#define AZK_HIGHLIGHT_BACKGROUND 0xc8d9ffu
#define AZK_HIGHLIGHT_FOREGROUND 0x000000u

struct _AzkEngine {
    IBusEngine parent;
    void *ctx;
    /* Built up by the *_begin / *_append / *_end calls. */
    GString *preedit_text;
    IBusAttrList *preedit_attrs;
    guint preedit_length;
    IBusLookupTable *table;
    IBusPropList *props;
    GHashTable *menus; /* key -> IBusPropList owned by `props` */
};

typedef struct {
    IBusEngineClass parent;
} AzkEngineClass;

G_DEFINE_TYPE(AzkEngine, azk_engine, IBUS_TYPE_ENGINE)

static AzkCallbacks azk_callbacks;

void azk_set_callbacks(const AzkCallbacks *callbacks) {
    azk_callbacks = *callbacks;
}

/* ---- GObject / IBusEngine plumbing ---- */

static void azk_engine_init(AzkEngine *engine) {
    engine->preedit_text = g_string_new(NULL);
    engine->menus = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
}

static void azk_engine_constructed(GObject *object) {
    G_OBJECT_CLASS(azk_engine_parent_class)->constructed(object);
    AzkEngine *engine = (AzkEngine *)object;
    if (azk_callbacks.create != NULL) {
        engine->ctx = azk_callbacks.create(engine);
    }
}

static void azk_engine_destroy(IBusObject *object) {
    AzkEngine *engine = (AzkEngine *)object;
    if (engine->ctx != NULL && azk_callbacks.destroy != NULL) {
        azk_callbacks.destroy(engine->ctx);
    }
    engine->ctx = NULL;
    g_clear_object(&engine->preedit_attrs);
    g_clear_object(&engine->table);
    g_clear_object(&engine->props);
    g_clear_pointer(&engine->menus, g_hash_table_destroy);
    if (engine->preedit_text != NULL) {
        g_string_free(engine->preedit_text, TRUE);
        engine->preedit_text = NULL;
    }
    IBUS_OBJECT_CLASS(azk_engine_parent_class)->destroy(object);
}

static gboolean azk_engine_process_key_event(IBusEngine *ibus_engine, guint keyval, guint keycode, guint state) {
    AzkEngine *engine = (AzkEngine *)ibus_engine;
    if (engine->ctx == NULL || azk_callbacks.process_key_event == NULL) {
        return FALSE;
    }
    return azk_callbacks.process_key_event(engine->ctx, keyval, keycode, state, ibus_keyval_to_unicode(keyval));
}

#define AZK_FORWARD(name)                                                       \
    static void azk_engine_##name(IBusEngine *ibus_engine) {                    \
        AzkEngine *engine = (AzkEngine *)ibus_engine;                           \
        if (engine->ctx != NULL && azk_callbacks.name != NULL) {                \
            azk_callbacks.name(engine->ctx);                                    \
        }                                                                       \
    }

AZK_FORWARD(focus_in)
AZK_FORWARD(focus_out)
AZK_FORWARD(reset)
AZK_FORWARD(enable)
AZK_FORWARD(disable)
AZK_FORWARD(page_up)
AZK_FORWARD(page_down)
AZK_FORWARD(cursor_up)
AZK_FORWARD(cursor_down)

static void azk_engine_set_content_type(IBusEngine *ibus_engine, guint purpose, guint hints) {
    AzkEngine *engine = (AzkEngine *)ibus_engine;
    if (engine->ctx != NULL && azk_callbacks.set_content_type != NULL) {
        azk_callbacks.set_content_type(engine->ctx, purpose, hints);
    }
}

static void azk_engine_property_activate(IBusEngine *ibus_engine, const gchar *name, guint state) {
    AzkEngine *engine = (AzkEngine *)ibus_engine;
    if (engine->ctx != NULL && azk_callbacks.property_activate != NULL) {
        azk_callbacks.property_activate(engine->ctx, name, state);
    }
}

static void azk_engine_candidate_clicked(IBusEngine *ibus_engine, guint index, guint button, guint state) {
    AzkEngine *engine = (AzkEngine *)ibus_engine;
    if (engine->ctx != NULL && azk_callbacks.candidate_clicked != NULL) {
        azk_callbacks.candidate_clicked(engine->ctx, index, button, state);
    }
}

static void azk_engine_class_init(AzkEngineClass *klass) {
    GObjectClass *object_class = G_OBJECT_CLASS(klass);
    IBusObjectClass *ibus_object_class = IBUS_OBJECT_CLASS(klass);
    IBusEngineClass *engine_class = IBUS_ENGINE_CLASS(klass);

    object_class->constructed = azk_engine_constructed;
    ibus_object_class->destroy = azk_engine_destroy;
    engine_class->process_key_event = azk_engine_process_key_event;
    engine_class->focus_in = azk_engine_focus_in;
    engine_class->focus_out = azk_engine_focus_out;
    engine_class->reset = azk_engine_reset;
    engine_class->enable = azk_engine_enable;
    engine_class->disable = azk_engine_disable;
    engine_class->page_up = azk_engine_page_up;
    engine_class->page_down = azk_engine_page_down;
    engine_class->cursor_up = azk_engine_cursor_up;
    engine_class->cursor_down = azk_engine_cursor_down;
    engine_class->set_content_type = azk_engine_set_content_type;
    engine_class->property_activate = azk_engine_property_activate;
    engine_class->candidate_clicked = azk_engine_candidate_clicked;
}

/* ---- Engine -> client ---- */

void azk_engine_commit_text(AzkEngine *engine, const char *text) {
    ibus_engine_commit_text(IBUS_ENGINE(engine), ibus_text_new_from_string(text));
}

void azk_engine_preedit_begin(AzkEngine *engine) {
    g_string_truncate(engine->preedit_text, 0);
    engine->preedit_length = 0;
    g_clear_object(&engine->preedit_attrs);
    engine->preedit_attrs = g_object_ref_sink(ibus_attr_list_new());
}

void azk_engine_preedit_append(AzkEngine *engine, const char *text, AzkPreeditStyle style) {
    guint start = engine->preedit_length;
    guint end = start + (guint)g_utf8_strlen(text, -1);
    g_string_append(engine->preedit_text, text);
    engine->preedit_length = end;
    if (start == end) {
        return;
    }
    ibus_attr_list_append(engine->preedit_attrs, ibus_attr_underline_new(IBUS_ATTR_UNDERLINE_SINGLE, start, end));
    if (style == AZK_PREEDIT_HIGHLIGHT) {
        ibus_attr_list_append(engine->preedit_attrs, ibus_attr_background_new(AZK_HIGHLIGHT_BACKGROUND, start, end));
        ibus_attr_list_append(engine->preedit_attrs, ibus_attr_foreground_new(AZK_HIGHLIGHT_FOREGROUND, start, end));
    }
}

void azk_engine_preedit_end(AzkEngine *engine, uint32_t cursor) {
    IBusText *text = ibus_text_new_from_string(engine->preedit_text->str);
    ibus_text_set_attributes(text, engine->preedit_attrs);
    /* COMMIT: if focus moves away mid-composition, the client commits the
     * preedit instead of dropping it. */
    ibus_engine_update_preedit_text_with_mode(IBUS_ENGINE(engine), text, MIN(cursor, engine->preedit_length),
                                              engine->preedit_length > 0, IBUS_ENGINE_PREEDIT_COMMIT);
}

void azk_engine_hide_preedit(AzkEngine *engine) {
    ibus_engine_update_preedit_text_with_mode(IBUS_ENGINE(engine), ibus_text_new_from_static_string(""), 0, FALSE,
                                              IBUS_ENGINE_PREEDIT_CLEAR);
}

void azk_engine_lookup_begin(AzkEngine *engine, uint32_t page_size, bool with_labels) {
    g_clear_object(&engine->table);
    engine->table = g_object_ref_sink(ibus_lookup_table_new(page_size, 0, TRUE, FALSE));
    ibus_lookup_table_set_orientation(engine->table, IBUS_ORIENTATION_VERTICAL);
    for (guint i = 0; i < page_size; i++) {
        gchar *label = with_labels ? g_strdup_printf("%u", (i + 1) % 10) : g_strdup("");
        ibus_lookup_table_append_label(engine->table, ibus_text_new_from_string(label));
        g_free(label);
    }
}

void azk_engine_lookup_append(AzkEngine *engine, const char *candidate, const char *annotation) {
    if (annotation != NULL && annotation[0] != '\0') {
        gchar *text = g_strdup_printf("%s  (%s)", candidate, annotation);
        ibus_lookup_table_append_candidate(engine->table, ibus_text_new_from_string(text));
        g_free(text);
    } else {
        ibus_lookup_table_append_candidate(engine->table, ibus_text_new_from_string(candidate));
    }
}

void azk_engine_lookup_end(AzkEngine *engine, uint32_t cursor, bool cursor_visible) {
    ibus_lookup_table_set_cursor_pos(engine->table, cursor);
    ibus_lookup_table_set_cursor_visible(engine->table, cursor_visible);
    ibus_engine_update_lookup_table(IBUS_ENGINE(engine), engine->table, TRUE);
}

void azk_engine_hide_lookup(AzkEngine *engine) {
    ibus_engine_hide_lookup_table(IBUS_ENGINE(engine));
}

void azk_engine_set_auxiliary_text(AzkEngine *engine, const char *text) {
    if (text == NULL || text[0] == '\0') {
        ibus_engine_hide_auxiliary_text(IBUS_ENGINE(engine));
    } else {
        ibus_engine_update_auxiliary_text(IBUS_ENGINE(engine), ibus_text_new_from_string(text), TRUE);
    }
}

char *azk_engine_dup_surrounding_text(AzkEngine *engine, uint32_t *cursor, uint32_t *anchor) {
    IBusEngine *ibus_engine = IBUS_ENGINE(engine);
    if ((ibus_engine->client_capabilities & IBUS_CAP_SURROUNDING_TEXT) == 0) {
        return NULL;
    }
    IBusText *text = NULL;
    guint cursor_pos = 0;
    guint anchor_pos = 0;
    ibus_engine_get_surrounding_text(ibus_engine, &text, &cursor_pos, &anchor_pos);
    if (text == NULL) {
        return NULL;
    }
    *cursor = cursor_pos;
    *anchor = anchor_pos;
    return g_strdup(ibus_text_get_text(text));
}

void azk_free(void *pointer) {
    g_free(pointer);
}

/* ---- Properties ---- */

void azk_engine_props_begin(AzkEngine *engine) {
    g_clear_object(&engine->props);
    g_hash_table_remove_all(engine->menus);
    engine->props = g_object_ref_sink(ibus_prop_list_new());
}

void azk_engine_props_append(AzkEngine *engine, const char *parent, const char *key, AzkPropType type,
                             const char *label, const char *symbol, const char *tooltip, bool checked) {
    IBusPropList *list = engine->props;
    if (parent != NULL) {
        list = g_hash_table_lookup(engine->menus, parent);
        g_return_if_fail(list != NULL);
    }
    IBusPropList *sub_props = NULL;
    if (type == AZK_PROP_MENU) {
        sub_props = ibus_prop_list_new();
    }
    IBusProperty *property = ibus_property_new(
        key, (IBusPropType)type, ibus_text_new_from_string(label != NULL ? label : ""), NULL,
        ibus_text_new_from_string(tooltip != NULL ? tooltip : ""), TRUE, TRUE,
        checked ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, sub_props);
    if (symbol != NULL) {
        ibus_property_set_symbol(property, ibus_text_new_from_string(symbol));
    }
    if (sub_props != NULL) {
        g_hash_table_insert(engine->menus, g_strdup(key), sub_props);
    }
    ibus_prop_list_append(list, property);
}

void azk_engine_props_register(AzkEngine *engine) {
    ibus_engine_register_properties(IBUS_ENGINE(engine), engine->props);
}

/* ---- Main loop ---- */

uint32_t azk_timeout_add(uint32_t milliseconds, void (*callback)(void *data), void *data) {
    return g_timeout_add_once(milliseconds, (GSourceOnceFunc)callback, data);
}

void azk_source_remove(uint32_t source_id) {
    g_source_remove(source_id);
}

bool azk_spawn_command_line(const char *command_line) {
    GError *error = NULL;
    if (!g_spawn_command_line_async(command_line, &error)) {
        g_warning("could not run %s: %s", command_line, error->message);
        g_error_free(error);
        return false;
    }
    return true;
}

/* libdispatch's hooks for integrating the main queue into a foreign run loop
 * (Foundation's RunLoop uses them on Linux). With them, DispatchQueue.main
 * and @MainActor tasks run inside the GLib main loop. */
extern int _dispatch_get_main_queue_handle_4CF(void);
extern void _dispatch_main_queue_callback_4CF(void *message);

static gboolean azk_drain_main_queue(gint fd, GIOCondition condition, gpointer user_data) {
    (void)condition;
    (void)user_data;
    eventfd_t value;
    (void)eventfd_read(fd, &value);
    _dispatch_main_queue_callback_4CF(NULL);
    return G_SOURCE_CONTINUE;
}

static gboolean azk_quitting = FALSE;

static void azk_quit(void) {
    if (azk_quitting) {
        return;
    }
    azk_quitting = TRUE;
    if (azk_callbacks.shutdown != NULL) {
        azk_callbacks.shutdown();
    }
    ibus_quit();
}

static void azk_on_disconnected(IBusBus *bus, gpointer user_data) {
    (void)bus;
    (void)user_data;
    azk_quit();
}

static gboolean azk_on_signal(gpointer user_data) {
    (void)user_data;
    azk_quit();
    return G_SOURCE_REMOVE;
}

int azk_main(bool launched_by_ibus, const char *version) {
    ibus_init();
    IBusBus *bus = ibus_bus_new();
    g_object_ref_sink(bus);
    if (!ibus_bus_is_connected(bus)) {
        g_printerr("ibus-azookey: cannot connect to ibus-daemon\n");
        return 1;
    }
    g_signal_connect(bus, "disconnected", G_CALLBACK(azk_on_disconnected), NULL);

    IBusFactory *factory = ibus_factory_new(ibus_bus_get_connection(bus));
    g_object_ref_sink(factory);
    ibus_factory_add_engine(factory, AZK_ENGINE_NAME, azk_engine_get_type());

    if (launched_by_ibus) {
        if (ibus_bus_request_name(bus, AZK_COMPONENT_NAME, 0) == 0) {
            g_printerr("ibus-azookey: could not claim %s\n", AZK_COMPONENT_NAME);
            return 1;
        }
    } else {
        IBusComponent *component = ibus_component_new(
            AZK_COMPONENT_NAME, "azooKey Japanese input (unofficial Linux port)", version, "MIT", "rotarymars",
            "", "", "ibus-azookey");
        ibus_component_add_engine(component,
                                  ibus_engine_desc_new_varargs(
                                      "name", AZK_ENGINE_NAME,
                                      "longname", "azooKey",
                                      "description", "Japanese input with azooKey's converter and the Zenzai model",
                                      "language", "ja",
                                      "license", "MIT",
                                      "author", "rotarymars",
                                      "layout", "default",
                                      "symbol", "あ",
                                      "rank", 0,
                                      "icon-prop-key", "InputMode",
                                      NULL));
        ibus_bus_register_component(bus, component);
    }

    g_unix_signal_add(SIGTERM, azk_on_signal, NULL);
    g_unix_signal_add(SIGINT, azk_on_signal, NULL);
    int main_queue = _dispatch_get_main_queue_handle_4CF();
    if (main_queue >= 0) {
        g_unix_fd_add(main_queue, G_IO_IN, azk_drain_main_queue, NULL);
    }

    ibus_main();
    azk_quit();

    g_object_unref(factory);
    g_object_unref(bus);
    return 0;
}
