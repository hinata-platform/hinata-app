#ifndef RUNNER_TASKBAR_CHANNEL_H_
#define RUNNER_TASKBAR_CHANNEL_H_

#include <flutter/flutter_engine.h>
#include <windows.h>

// The timer on the taskbar button (HIN-101), over the method channel
// "hinata/taskbar", drawn with ITaskbarList3:
//
//   setProgress({state: "none" | "normal", value: 0..1000})
//   setOverlay({running, description})   the 16 px "running" mark
//   setButtons({running, toggle, focus}) the thumbnail toolbar: start or
//                                        stop, and the focus view
//   setTooltip({text})                   the thumbnail's tooltip, "" clears
//   clear()                              all of the above
//
// and calls Dart with thumbClicked("toggle" | "focus").
//
// Nothing reaches the taskbar before Explorer has sent TaskbarButtonCreated
// for this window; what Dart asks for earlier is kept and drawn then, and
// drawn again when Explorer restarts and sends it once more.
namespace hinata {

void RegisterTaskbarChannel(flutter::FlutterEngine* engine, HWND window);

// Forwarded from the runner's window procedure. Returns true when the message
// belonged to the taskbar and was handled.
bool HandleTaskbarMessage(HWND window, UINT message, WPARAM wparam,
                          LPARAM lparam);

// Releases the channel, the taskbar and the icons. Call from the window's
// OnDestroy, before the engine goes, while COM is still initialised.
void UnregisterTaskbarChannel();

}  // namespace hinata

#endif  // RUNNER_TASKBAR_CHANNEL_H_
