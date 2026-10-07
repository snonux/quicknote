#include "clipboard_channel.h"

#include <gtk/gtk.h>

static FlMethodChannel* channel = nullptr;

// GTK hands the clipboard image over asynchronously; the method call is
// answered from here.
static void image_received(GtkClipboard* clipboard, GdkPixbuf* pixbuf,
                           gpointer user_data) {
  g_autoptr(FlMethodCall) call = FL_METHOD_CALL(user_data);
  g_autoptr(FlValue) result = nullptr;
  if (pixbuf != nullptr) {
    gchar* buffer = nullptr;
    gsize size = 0;
    g_autoptr(GError) error = nullptr;
    if (gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &size, "png", &error,
                                  nullptr)) {
      result = fl_value_new_map();
      fl_value_set_string_take(
          result, "bytes",
          fl_value_new_uint8_list(reinterpret_cast<const uint8_t*>(buffer),
                                  size));
      fl_value_set_string_take(result, "mime", fl_value_new_string("image/png"));
      g_free(buffer);
    } else {
      g_warning("Cannot encode the clipboard image: %s", error->message);
    }
  }
  if (result == nullptr) result = fl_value_new_null();
  fl_method_call_respond_success(call, result, nullptr);
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  if (g_strcmp0(fl_method_call_get_name(call), "readImage") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  gtk_clipboard_request_image(clipboard, image_received, g_object_ref(call));
}

void clipboard_channel_register(FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_clear_object(&channel);
  channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                                  "org.buetow.turbonotes/clipboard",
                                  FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr,
                                            nullptr);
}
