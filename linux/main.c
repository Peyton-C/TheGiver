/*
 * The Giver's GTK 4 frontend: one picker per open request, laid out like the
 * macOS app, with the applications in a row above the path or URL.
 */
#include <gtk/gtk.h>

#define APP_ID "io.github.peyton_c.TheGiver"

// Make sure 5 apps are always visible, like The Giver on macOS and 
#define APP_WIDTH 124
#define APP_SPACING 6
#define APPS_VISIBLE 5

typedef struct {
    GtkWindow *window;
    GtkWidget *row;
    GtkWidget *entry;
    /* What will be opened. Several files opened together share one picker. */
    GStrv uris;
    /* GAppInfo, in the order shown. */
    GPtrArray *apps;
} Picker;

static void show_error(GtkWindow *parent, const char *heading, const char *detail)
{
    GtkAlertDialog *dialog = gtk_alert_dialog_new("%s", heading);
    gtk_alert_dialog_set_detail(dialog, detail);
    gtk_alert_dialog_show(dialog, parent);
    g_object_unref(dialog);
}

/* --- Applications ------------------------------------------------------- */

/* The content type of a file, or the handler type GIO uses for a scheme. */
static char *type_of(const char *uri)
{
    char *scheme = g_uri_parse_scheme(uri);
    char *type = NULL;
    if (!scheme)
        return NULL;
    if (g_str_equal(scheme, "file")) {
        GFile *file = g_file_new_for_uri(uri);
        GFileInfo *info = g_file_query_info(file, G_FILE_ATTRIBUTE_STANDARD_CONTENT_TYPE,
                                            G_FILE_QUERY_INFO_NONE, NULL, NULL);
        if (info) {
            type = g_strdup(g_file_info_get_content_type(info));
            g_object_unref(info);
        }
        g_object_unref(file);
    } else {
        type = g_strconcat("x-scheme-handler/", scheme, NULL);
    }
    g_free(scheme);
    return type;
}

static int compare_app(gconstpointer a, gconstpointer b)
{
    return g_app_info_equal(G_APP_INFO(a), G_APP_INFO(b)) ? 0 : 1;
}

/* The applications able to open every URI, in GIO's order for the first,
 * without The Giver itself. */
static GPtrArray *apps_for(GStrv uris)
{
    GPtrArray *apps = NULL;
    for (; uris && *uris; uris++) {
        char *type = type_of(*uris);
        GList *all = type ? g_app_info_get_all_for_type(type) : NULL;
        g_free(type);
        if (!apps) {
            apps = g_ptr_array_new_with_free_func(g_object_unref);
            for (GList *l = all; l; l = l->next)
                if (g_strcmp0(g_app_info_get_id(l->data), APP_ID ".desktop") != 0)
                    g_ptr_array_add(apps, g_object_ref(l->data));
        } else {
            for (guint i = apps->len; i-- > 0;)
                if (!g_list_find_custom(all, apps->pdata[i], compare_app))
                    g_ptr_array_remove_index(apps, i);
        }
        g_list_free_full(all, g_object_unref);
    }
    return apps ? apps : g_ptr_array_new_with_free_func(g_object_unref);
}

static void launch(Picker *p, guint index, gboolean keep_open)
{
    if (index >= p->apps->len || !p->uris || !*p->uris) {
        gtk_widget_error_bell(GTK_WIDGET(p->window));
        return;
    }
    GAppInfo *info = p->apps->pdata[index];
    GList *uris = NULL;
    for (GStrv uri = p->uris; *uri; uri++)
        uris = g_list_append(uris, *uri);

    GdkAppLaunchContext *context = gdk_display_get_app_launch_context(gtk_widget_get_display(GTK_WIDGET(p->window)));
    GError *error = NULL;
    gboolean launched = g_app_info_launch_uris(info, uris, G_APP_LAUNCH_CONTEXT(context), &error);
    g_object_unref(context);
    g_list_free(uris);

    if (!launched) {
        char *heading = g_strdup_printf("Can’t Open with %s", g_app_info_get_display_name(info));
        show_error(p->window, heading, error->message);
        g_free(heading);
        g_error_free(error);
    } else if (!keep_open) {
        gtk_window_close(p->window);
    }
}

/* GTK 4 passes no event to "clicked", so ask the keyboard directly. */
static gboolean control_held(GtkWidget *widget)
{
    GdkSeat *seat = gdk_display_get_default_seat(gtk_widget_get_display(widget));
    GdkDevice *keyboard = seat ? gdk_seat_get_keyboard(seat) : NULL;
    return keyboard && (gdk_device_get_modifier_state(keyboard) & GDK_CONTROL_MASK);
}

/* --- Row ---------------------------------------------------------------- */

static void on_app_clicked(GtkButton *button, gpointer data)
{
    guint index = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(button), "index"));
    launch(data, index, control_held(GTK_WIDGET(button)));
}

static GtkWidget *app_button(Picker *p, guint index)
{
    GAppInfo *info = p->apps->pdata[index];
    GIcon *icon = g_app_info_get_icon(info);
    GtkWidget *image = icon ? gtk_image_new_from_gicon(icon)
                            : gtk_image_new_from_icon_name("application-x-executable");
    gtk_image_set_pixel_size(GTK_IMAGE(image), 80);

    GtkWidget *label = gtk_label_new(g_app_info_get_display_name(info));
    gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
    /* Narrower than the button, so a long name ellipsizes rather than
     * widening it. */
    gtk_label_set_max_width_chars(GTK_LABEL(label), 11);

    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_box_append(GTK_BOX(box), image);
    gtk_box_append(GTK_BOX(box), label);

    GtkWidget *button = gtk_button_new();
    gtk_button_set_child(GTK_BUTTON(button), box);
    gtk_widget_add_css_class(button, "flat");
    gtk_widget_add_css_class(button, "app");
    gtk_widget_set_size_request(button, APP_WIDTH, -1);
    gtk_widget_set_tooltip_text(button, g_app_info_get_display_name(info));
    g_object_set_data(G_OBJECT(button), "index", GUINT_TO_POINTER(index));
    g_signal_connect(button, "clicked", G_CALLBACK(on_app_clicked), p);
    return button;
}

static void rebuild_row(Picker *p)
{
    GtkWidget *child;
    while ((child = gtk_widget_get_first_child(p->row)))
        gtk_box_remove(GTK_BOX(p->row), child);

    g_clear_pointer(&p->apps, g_ptr_array_unref);
    p->apps = apps_for(p->uris);
    for (guint i = 0; i < p->apps->len; i++)
        gtk_box_append(GTK_BOX(p->row), app_button(p, i));

    if (p->apps->len == 0) {
        GtkWidget *label = gtk_label_new(p->uris && *p->uris ? "No application can open this" : "Not a path or URL");
        gtk_widget_add_css_class(label, "dim-label");
        gtk_widget_set_hexpand(label, TRUE);
        gtk_box_append(GTK_BOX(p->row), label);
    }
}

/* --- Path --------------------------------------------------------------- */

static char *text_from_uri(const char *uri)
{
    char *path = g_filename_from_uri(uri, NULL, NULL);
    return path ? path : g_strdup(uri);
}

static char *uri_from_text(const char *text)
{
    char *scheme = g_uri_parse_scheme(text);
    if (scheme) {
        g_free(scheme);
        return g_strdup(text);
    }
    char *path = text[0] == '~' ? g_build_filename(g_get_home_dir(), text + 1, NULL) : g_strdup(text);
    char *uri = g_path_is_absolute(path) ? g_filename_to_uri(path, NULL, NULL) : NULL;
    g_free(path);
    return uri;
}

static void on_entry_changed(GtkEditable *editable, gpointer data)
{
    Picker *p = data;
    char *text = g_strstrip(g_strdup(gtk_editable_get_text(editable)));
    char *uri = uri_from_text(text);
    g_free(text);

    g_strfreev(p->uris);
    p->uris = g_new0(char *, 2);
    p->uris[0] = uri;
    rebuild_row(p);
}

static void on_entry_activate(GtkEntry *entry, gpointer data)
{
    launch(data, 0, control_held(GTK_WIDGET(entry)));
}

/* --- Menu --------------------------------------------------------------- */

static void on_copy(GSimpleAction *action, GVariant *parameter, gpointer data)
{
    (void)action;
    (void)parameter;
    Picker *p = data;
    gdk_clipboard_set_text(gtk_widget_get_clipboard(p->entry), gtk_editable_get_text(GTK_EDITABLE(p->entry)));
}

static void on_open_location(GSimpleAction *action, GVariant *parameter, gpointer data)
{
    (void)action;
    (void)parameter;
    Picker *p = data;
    if (!p->uris || !*p->uris)
        return;
    GFile *file = g_file_new_for_uri(p->uris[0]);
    GtkFileLauncher *launcher = gtk_file_launcher_new(file);
    gtk_file_launcher_open_containing_folder(launcher, NULL, NULL, NULL, NULL);
    g_object_unref(launcher);
    g_object_unref(file);
    gtk_window_close(p->window);
}

static const GActionEntry picker_actions[] = {
    {.name = "copy", .activate = on_copy},
    {.name = "open-location", .activate = on_open_location},
};

/* --- Window ------------------------------------------------------------- */

/* Sees only the keys nothing else wanted, so digits typed into the entry
 * stay there. */
static gboolean on_key_pressed(GtkEventControllerKey *controller, guint keyval, guint keycode,
                               GdkModifierType state, gpointer data)
{
    (void)controller;
    (void)keycode;
    Picker *p = data;
    if (keyval == GDK_KEY_Escape) {
        gtk_window_close(p->window);
        return TRUE;
    }
    if (keyval >= GDK_KEY_1 && keyval <= GDK_KEY_9) {
        launch(p, keyval - GDK_KEY_1, state & GDK_CONTROL_MASK);
        return TRUE;
    }
    return FALSE;
}

// Makes vertical scrolling into horizontal scrolling
static gboolean on_row_scroll(GtkEventControllerScroll *controller, double dx, double dy, gpointer data)
{
    (void)dx;
    GtkAdjustment *adjustment = gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(data));
    // Mouse wheel clicks are each worth one application
    // Trackpads go by pixel
    if (gtk_event_controller_scroll_get_unit(controller) == GDK_SCROLL_UNIT_WHEEL)
        dy *= APP_WIDTH + APP_SPACING;
    gtk_adjustment_set_value(adjustment, gtk_adjustment_get_value(adjustment) + dy);
    return TRUE;
}

static void picker_free(gpointer data)
{
    Picker *p = data;
    g_strfreev(p->uris);
    g_clear_pointer(&p->apps, g_ptr_array_unref);
    g_free(p);
}

static void on_close_clicked(GtkButton *button, gpointer data)
{
    (void)button;
    gtk_window_close(GTK_WINDOW(data));
}

static gboolean focus_first_app(gpointer data)
{
    Picker *p = g_object_get_data(G_OBJECT(data), "picker");
    if (p->apps->len > 0)
        gtk_widget_grab_focus(gtk_widget_get_first_child(p->row));
    return G_SOURCE_REMOVE;
}

static void open_picker(GtkApplication *app, GStrv uris)
{
    Picker *p = g_new0(Picker, 1);
    p->uris = uris;

    GtkWidget *window = gtk_application_window_new(app);
    p->window = GTK_WINDOW(window);
    gtk_window_set_title(p->window, "The Giver");
    gtk_window_set_resizable(p->window, FALSE);
    gtk_widget_add_css_class(window, "picker");
    g_object_set_data_full(G_OBJECT(window), "picker", p, picker_free);

    /* An empty title bar keeps the rounded corners and shadow of a
     * client-decorated window while drawing no header. */
    GtkWidget *titlebar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_visible(titlebar, FALSE);
    gtk_window_set_titlebar(p->window, titlebar);

    p->row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, APP_SPACING);
    GtkWidget *scroller = gtk_scrolled_window_new();
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroller), GTK_POLICY_AUTOMATIC, GTK_POLICY_NEVER);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), p->row);
    /* Only the width is fixed. A fixed height squashed the row under themes
     * with roomier buttons, so the row's own height is used instead. */
    gtk_widget_set_size_request(scroller, APPS_VISIBLE * APP_WIDTH + (APPS_VISIBLE - 1) * APP_SPACING, -1);
    gtk_scrolled_window_set_propagate_natural_height(GTK_SCROLLED_WINDOW(scroller), TRUE);

    GtkEventController *wheel = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_VERTICAL);
    gtk_event_controller_set_propagation_phase(wheel, GTK_PHASE_CAPTURE);
    g_signal_connect(wheel, "scroll", G_CALLBACK(on_row_scroll), scroller);
    gtk_widget_add_controller(scroller, wheel);

    GMenu *menu = g_menu_new();
    g_menu_append(menu, "Copy", "picker.copy");
    g_menu_append(menu, "Open Location", "picker.open-location");
    GtkWidget *menu_button = gtk_menu_button_new();
    gtk_menu_button_set_icon_name(GTK_MENU_BUTTON(menu_button), "open-menu-symbolic");
    gtk_menu_button_set_menu_model(GTK_MENU_BUTTON(menu_button), G_MENU_MODEL(menu));
    gtk_widget_add_css_class(menu_button, "flat");
    g_object_unref(menu);

    GSimpleActionGroup *actions = g_simple_action_group_new();
    g_action_map_add_action_entries(G_ACTION_MAP(actions), picker_actions, G_N_ELEMENTS(picker_actions), p);
    gtk_widget_insert_action_group(window, "picker", G_ACTION_GROUP(actions));
    g_object_unref(actions);

    p->entry = gtk_entry_new();
    gtk_widget_set_hexpand(p->entry, TRUE);
    if (g_strv_length(uris) == 1) {
        char *text = text_from_uri(uris[0]);
        gtk_editable_set_text(GTK_EDITABLE(p->entry), text);
        /* Show the end of a long path, where the file name is. */
        gtk_editable_set_position(GTK_EDITABLE(p->entry), -1);
        g_free(text);
        g_signal_connect(p->entry, "changed", G_CALLBACK(on_entry_changed), p);
        g_signal_connect(p->entry, "activate", G_CALLBACK(on_entry_activate), p);
    } else {
        char *text = g_strdup_printf("%u items", g_strv_length(uris));
        gtk_editable_set_text(GTK_EDITABLE(p->entry), text);
        gtk_widget_set_sensitive(p->entry, FALSE);
        g_free(text);
    }

    GtkWidget *close_button = gtk_button_new_from_icon_name("window-close-symbolic");
    gtk_widget_add_css_class(close_button, "circular");
    g_signal_connect(close_button, "clicked", G_CALLBACK(on_close_clicked), window);

    GtkWidget *bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_box_append(GTK_BOX(bar), menu_button);
    gtk_box_append(GTK_BOX(bar), p->entry);
    gtk_box_append(GTK_BOX(bar), close_button);

    GtkWidget *content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16);
    gtk_widget_add_css_class(content, "content");
    gtk_box_append(GTK_BOX(content), scroller);
    gtk_box_append(GTK_BOX(content), bar);

    /* With no header, the content is what the window is dragged by. */
    GtkWidget *handle = gtk_window_handle_new();
    gtk_window_handle_set_child(GTK_WINDOW_HANDLE(handle), content);
    gtk_window_set_child(p->window, handle);

    GtkEventController *keys = gtk_event_controller_key_new();
    g_signal_connect(keys, "key-pressed", G_CALLBACK(on_key_pressed), p);
    gtk_widget_add_controller(window, keys);

    rebuild_row(p);
    gtk_window_present(p->window);
    /* Start on the first application rather than the entry, so the arrow
     * keys and Return pick one straight away. GTK gives the entry focus as
     * the window maps, so this has to wait until it has. */
    g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, focus_first_app, g_object_ref(window), g_object_unref);
}

/* --- Application -------------------------------------------------------- */

static void on_open(GApplication *app, GFile **files, int n_files, const char *hint, gpointer data)
{
    (void)hint;
    (void)data;
    /* Files opened together share a picker. Links each get their own, as one
     * application rarely suits a mixed handful. */
    GStrvBuilder *local = g_strv_builder_new();
    for (int i = 0; i < n_files; i++) {
        char *uri = g_file_get_uri(files[i]);
        if (g_file_has_uri_scheme(files[i], "file")) {
            g_strv_builder_add(local, uri);
        } else {
            char *single[] = {uri, NULL};
            open_picker(GTK_APPLICATION(app), g_strdupv(single));
        }
        g_free(uri);
    }
    GStrv uris = g_strv_builder_end(local);
    g_strv_builder_unref(local);
    if (*uris)
        open_picker(GTK_APPLICATION(app), uris);
    else
        g_strfreev(uris);
}

/* Started on its own there is nothing to pick for, so say how to get one. */
static void on_activate(GApplication *app, gpointer data)
{
    (void)data;
    GtkWidget *window = gtk_application_window_new(GTK_APPLICATION(app));
    gtk_window_set_title(GTK_WINDOW(window), "The Giver");
    gtk_window_set_resizable(GTK_WINDOW(window), FALSE);

    GtkWidget *label = gtk_label_new(
        "The Giver appears when you open something it is the default application for.\n\n"
        "Choose it in Settings under Default Applications, in a file’s Open With dialog, "
        "or with xdg-mime default " APP_ID ".desktop followed by a type.");
    gtk_label_set_wrap(GTK_LABEL(label), TRUE);
    gtk_label_set_max_width_chars(GTK_LABEL(label), 48);
    gtk_label_set_selectable(GTK_LABEL(label), TRUE);
    gtk_widget_add_css_class(label, "content");
    gtk_window_set_child(GTK_WINDOW(window), label);
    gtk_window_present(GTK_WINDOW(window));
}

/* The accent colour chosen in the desktop's settings, as CSS. GTK on its own
 * always answers blue; following the setting is otherwise libadwaita's job,
 * so ask the settings portal the way it does. */
static char *accent_color(GApplication *app)
{
    GVariant *reply = g_dbus_connection_call_sync(
        g_application_get_dbus_connection(app), "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings", "ReadOne",
        g_variant_new("(ss)", "org.freedesktop.appearance", "accent-color"),
        G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 500, NULL, NULL);
    char *color = NULL;
    if (reply) {
        GVariant *value;
        double r, g, b;
        g_variant_get(reply, "(v)", &value);
        /* Out of range means no accent is set. */
        if (g_variant_is_of_type(value, G_VARIANT_TYPE("(ddd)"))) {
            g_variant_get(value, "(ddd)", &r, &g, &b);
            if (r >= 0 && r <= 1 && g >= 0 && g <= 1 && b >= 0 && b <= 1)
                color = g_strdup_printf("rgba(%d, %d, %d, 0.4)", (int)(r * 255), (int)(g * 255), (int)(b * 255));
        }
        g_variant_unref(value);
        g_variant_unref(reply);
    }
    return color ? color : g_strdup("alpha(@accent_bg_color, 0.35)");
}

static void on_startup(GApplication *app, gpointer data)
{
    (void)data;
    char *accent = accent_color(app);
    char *style = g_strdup_printf(
        ".content { margin: 18px; }\n"
        ".picker .app { padding: 16px 10px; border-radius: 18px; }\n"
        ".picker .app label { margin-top: 4px; }\n"
        /* The focused application is the selected one, so it is shown
         * whether or not focus came from the keyboard. */
        ".picker .app:focus { background-color: %s; outline: none; }\n"
        ".picker entry { border-radius: 999px; padding: 0 14px; min-height: 38px; }\n",
        accent);
    GtkCssProvider *css = gtk_css_provider_new();
    gtk_css_provider_load_from_string(css, style);
    g_free(style);
    g_free(accent);
    gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(css),
                                               GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(css);
}

int main(int argc, char **argv)
{
    GtkApplication *app = gtk_application_new(APP_ID, G_APPLICATION_HANDLES_OPEN);
    g_signal_connect(app, "startup", G_CALLBACK(on_startup), NULL);
    g_signal_connect(app, "activate", G_CALLBACK(on_activate), NULL);
    g_signal_connect(app, "open", G_CALLBACK(on_open), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
