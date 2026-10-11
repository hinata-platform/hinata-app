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

void CopyTip(WCHAR* target, size_t capacity, const std::wstring& text) {
  wcsncpy_s(target, capacity, text.c_str(), _TRUNCATE);
}

THUMBBUTTON Button(UINT id, int icon, const std::wstring& tip, bool visible) {
  THUMBBUTTON button = {};
  button.dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  button.iId = id;
  button.hIcon = SmallIcon(icon);
  CopyTip(button.szTip, ARRAYSIZE(button.szTip), tip);
  button.dwFlags = visible ? THBF_ENABLED : THBF_HIDDEN;
  return button;
}

// Draws g_state. Called after every change and when Explorer (re)creates the
// button; does nothing while the button does not exist yet.
void Draw() {
  if (!g_taskbar || !g_window) return;
  const auto& s = g_state;
  const bool on = s.drawn;

  g_taskbar->SetProgressState(
      g_window, on && s.progress ? TBPF_NORMAL : TBPF_NOPROGRESS);
  if (on && s.progress) {
    g_taskbar->SetProgressValue(g_window, s.value, 1000);
  }

  HICON overlay = on && s.running ? SmallIcon(IDI_TASKBAR_RUNNING) : nullptr;
  g_taskbar->SetOverlayIcon(g_window, overlay,
                            on && s.running ? s.description.c_str() : L"");
  if (overlay) DestroyIcon(overlay);

  // The toolbar can be added only once per button; afterwards it is updated,
  // and hidden rather than removed.
  const bool show = on && s.buttons;
  THUMBBUTTON buttons[2] = {
      Button(kToggleButton, s.running ? IDI_THUMB_STOP : IDI_THUMB_PLAY,
             s.toggle_tip, show),
      Button(kFocusButton, IDI_THUMB_FOCUS, s.focus_tip, show),
  };
  if (!g_buttons_added) {
    if (show && SUCCEEDED(g_taskbar->ThumbBarAddButtons(
                    g_window, ARRAYSIZE(buttons), buttons))) {
      g_buttons_added = true;
    }
  } else {
    g_taskbar->ThumbBarUpdateButtons(g_window, ARRAYSIZE(buttons), buttons);
  }
  for (auto& button : buttons) {
    if (button.hIcon) DestroyIcon(button.hIcon);
  }

  g_taskbar->SetThumbnailTooltip(
      g_window, on && !s.tooltip.empty() ? s.tooltip.c_str() : nullptr);
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
  if (method == "setProgress") {
    g_state.progress = String(*args, "state") == L"normal";
    g_state.value = Int(*args, "value");
  } else if (method == "setOverlay") {
    g_state.running = Bool(*args, "running");
    g_state.description = String(*args, "description");
  } else if (method == "setButtons") {
    g_state.buttons = true;
    g_state.running = Bool(*args, "running");
    g_state.toggle_tip = String(*args, "toggle");
    g_state.focus_tip = String(*args, "focus");
  } else if (method == "setTooltip") {
    g_state.tooltip = String(*args, "text");
  } else {
    result->NotImplemented();
    return;
  }
  Draw();
  result->Success();
}

}  // namespace

void RegisterTaskbarChannel(flutter::FlutterEngine* engine, HWND window) {
  g_window = window;
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
  if (message == WM_COMMAND && HIWORD(wparam) == THBN_CLICKED && g_channel) {
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

}  // namespace hinata
