#ifndef RUNNER_CLIPBOARD_CHANNEL_H_
#define RUNNER_CLIPBOARD_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// Registers the org.buetow.turbonotes/clipboard channel on [view]'s engine:
// "readImage" answers {bytes: PNG, mime: "image/png"} for an image on the
// clipboard, or null. Flutter's own clipboard API only carries text.
void clipboard_channel_register(FlView* view);

#endif  // RUNNER_CLIPBOARD_CHANNEL_H_
