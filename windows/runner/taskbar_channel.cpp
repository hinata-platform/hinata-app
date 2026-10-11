#include "taskbar_channel.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <memory>
#include <string>

#include "resource.h"

namespace hinata {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

constexpr UINT kToggleButton = 1001;
constexpr UINT kFocusButton = 1002;

// What Dart asked for, kept so it can be drawn whenever the button exists.
struct TaskbarState {
  bool drawn = false;
  bool progress = false;
  int value = 0;
  bool running = false;
  std::wstring description;
  bool buttons = false;
  std::wstring toggle_tip;
  std::wstring focus_tip;
  std::wstring tooltip;
};

std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_channel;
HWND g_window = nullptr;
UINT g_button_created = 0;
ComPtr<ITaskbarList3> g_taskbar;
bool g_buttons_added = false;
TaskbarState g_state;

std::wstring Wide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                       static_cast<int>(utf8.size()), nullptr,
                                       0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), size);
  return wide;
}

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::wstring String(const EncodableMap& map, const char* key) {
  const auto* value = Find(map, key);
  const auto* text = value ? std::get_if<std::string>(value) : nullptr;
  return text ? Wide(*text) : std::wstring();
}

bool Bool(const EncodableMap& map, const char* key) {
  const auto* value = Find(map, key);
  const auto* flag = value ? std::get_if<bool>(value) : nullptr;
  return flag && *flag;
}

int Int(const EncodableMap& map, const char* key) {
  const auto* value = Find(map, key);
  if (!value) return 0;
  if (const auto* narrow = std::get_if<int32_t>(value)) return *narrow;
  if (const auto* wide = std::get_if<int64_t>(value)) {
    return static_cast<int>(*wide);
  }
  return 0;
}

HICON SmallIcon(int id) {
  const int size = GetSystemMetrics(SM_CXSMICON);
  return static_cast<HICON>(LoadImage(GetModuleHandle(nullptr),
                                      MAKEINTRESOURCE(id), IMAGE_ICON, size,
                                      size, LR_DEFAULTCOLOR));
}

// Loaded once and kept: the icons are drawn again on every change, and loading
// and destroying them each time costs Explorer and us for nothing.
struct Icons {
  HICON running = nullptr;
  HICON play = nullptr;
  HICON stop = nullptr;
  HICON focus = nullptr;

  void Load() {
    if (!running) running = SmallIcon(IDI_TASKBAR_RUNNING);
    if (!play) play = SmallIcon(IDI_THUMB_PLAY);
    if (!stop) stop = SmallIcon(IDI_THUMB_STOP);
    if (!focus) focus = SmallIcon(IDI_THUMB_FOCUS);
  }

  void Free() {
    for (HICON* icon : {&running, &play, &stop, &focus}) {
      if (*icon) DestroyIcon(*icon);
      *icon = nullptr;
    }
  }
};
Icons g_icons;

void CopyTip(WCHAR* target, size_t capacity, const std::wstring& text) {
  wcsncpy_s(target, capacity, text.c_str(), _TRUNCATE);
}

THUMBBUTTON Button(UINT id, HICON icon, const std::wstring& tip, bool visible) {
  THUMBBUTTON button = {};
  button.dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  button.iId = id;
  button.hIcon = icon;
  CopyTip(button.szTip, ARRAYSIZE(button.szTip), tip);
  button.dwFlags = visible ? THBF_ENABLED : THBF_HIDDEN;
  return button;
}

bool ButtonsShown() {
  return g_buttons_added && g_state.drawn && g_state.buttons;
}

// Each part is drawn on its own, so a call from Dart touches only what it
// changed; Draw() does all of them when the button is (re)created.
void DrawProgress() {
  const auto& s = g_state;
  const bool on = s.drawn && s.progress;
  g_taskbar->SetProgressState(g_window, on ? TBPF_NORMAL : TBPF_NOPROGRESS);
  if (on) g_taskbar->SetProgressValue(g_window, s.value, 1000);
}

void DrawOverlay() {
  const auto& s = g_state;
  const bool on = s.drawn && s.running;
  g_taskbar->SetOverlayIcon(g_window, on ? g_icons.running : nullptr,
                            on ? s.description.c_str() : L"");
}

void DrawButtons() {
  const auto& s = g_state;
  // The toolbar can be added only once per button; afterwards it is updated,
  // and hidden rather than removed.
  const bool show = s.drawn && s.buttons;
  THUMBBUTTON buttons[2] = {
      Button(kToggleButton, s.running ? g_icons.stop : g_icons.play,
             s.toggle_tip, show),
      Button(kFocusButton, g_icons.focus, s.focus_tip, show),
  };
  if (!g_buttons_added) {
    if (show && SUCCEEDED(g_taskbar->ThumbBarAddButtons(
                    g_window, ARRAYSIZE(buttons), buttons))) {
      g_buttons_added = true;
    }
  } else {
    g_taskbar->ThumbBarUpdateButtons(g_window, ARRAYSIZE(buttons), buttons);
  }
}

void DrawTooltip() {
  const auto& s = g_state;
  g_taskbar->SetThumbnailTooltip(
      g_window, s.drawn && !s.tooltip.empty() ? s.tooltip.c_str() : nullptr);
}

// Draws g_state in full, when Explorer (re)creates the button and on clear;
// does nothing while the button does not exist yet.
void Draw() {
  if (!g_taskbar || !g_window) return;
  DrawProgress();
  DrawOverlay();
  DrawButtons();
  DrawTooltip();
}

void Handle(const flutter::MethodCall<EncodableValue>& call,
            std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  const auto& method = call.method_name();
  if (method == "clear") {
    g_state = TaskbarState();
    Draw();
    result->Success();
    return;
  }
  if (!args) {
    result->Error("bad_args", "a map was expected");
    return;
  }
  g_state.drawn = true;
  void (*draw)() = nullptr;
  if (method == "setProgress") {
    g_state.progress = String(*args, "state") == L"normal";
    g_state.value = Int(*args, "value");
    draw = DrawProgress;
  } else if (method == "setOverlay") {
    g_state.running = Bool(*args, "running");
    g_state.description = String(*args, "description");
    draw = DrawOverlay;
  } else if (method == "setButtons") {
    g_state.buttons = true;
    g_state.running = Bool(*args, "running");
    g_state.toggle_tip = String(*args, "toggle");
    g_state.focus_tip = String(*args, "focus");
    draw = DrawButtons;
  } else if (method == "setTooltip") {
    g_state.tooltip = String(*args, "text");
    draw = DrawTooltip;
  } else {
    result->NotImplemented();
    return;
  }
  if (g_taskbar && g_window) draw();
  result->Success();
}

}  // namespace

void RegisterTaskbarChannel(flutter::FlutterEngine* engine, HWND window) {
  g_window = window;
  g_icons.Load();
  g_button_created = RegisterWindowMessage(L"TaskbarButtonCreated");
  g_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), "hinata/taskbar",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      [](const auto& call, auto result) { Handle(call, std::move(result)); });
}

bool HandleTaskbarMessage(HWND /*window*/, UINT message, WPARAM wparam,
                          LPARAM /*lparam*/) {
  if (g_button_created != 0 && message == g_button_created) {
    // Also after Explorer restarts: a new button, so a new toolbar.
    g_taskbar.Reset();
    g_buttons_added = false;
    ComPtr<ITaskbarList3> taskbar;
    if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&taskbar))) &&
        SUCCEEDED(taskbar->HrInit())) {
      g_taskbar = taskbar;
      Draw();
    }
    return true;
  }
  // Only a button on screen can have been clicked; another process posting
  // the same message to this window starts nothing.
  if (message == WM_COMMAND && HIWORD(wparam) == THBN_CLICKED && g_channel &&
      ButtonsShown()) {
    const UINT id = LOWORD(wparam);
    if (id == kToggleButton || id == kFocusButton) {
      g_channel->InvokeMethod(
          "thumbClicked",
          std::make_unique<EncodableValue>(id == kToggleButton ? "toggle"
                                                               : "focus"));
      return true;
    }
  }
  return false;
}

void UnregisterTaskbarChannel() {
  if (g_channel) g_channel->SetMethodCallHandler(nullptr);
  g_channel.reset();
  // Released while COM is still initialised, not by a static destructor after
  // CoUninitialize.
  g_taskbar.Reset();
  g_icons.Free();
  g_window = nullptr;
  g_buttons_added = false;
  g_state = TaskbarState();
}

}  // namespace hinata
