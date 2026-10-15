#include "flutter_window.h"

#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr char kWindowThemeChannel[] = "uai_capoeira/windows_window";

uint32_t ReadArgb(const flutter::EncodableMap& map,
                  const char* key,
                  uint32_t fallback) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return fallback;

  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    return static_cast<uint32_t>(*value);
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<uint32_t>(*value);
  }
  return fallback;
}

bool ReadBool(const flutter::EncodableMap& map,
              const char* key,
              bool fallback) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return fallback;
  if (const auto* value = std::get_if<bool>(&it->second)) {
    return *value;
  }
  return fallback;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  window_theme_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowThemeChannel,
          &flutter::StandardMethodCodec::GetInstance());

  window_theme_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setTitleBarTheme") {
          const auto* arguments = call.arguments();
          const auto* map =
              arguments == nullptr
                  ? nullptr
                  : std::get_if<flutter::EncodableMap>(arguments);

          if (map == nullptr) {
            result->Error("invalid_args", "Theme payload must be a map.");
            return;
          }

          const uint32_t caption =
              ReadArgb(*map, "captionColor", 0xFF202331u);
          const uint32_t text = ReadArgb(*map, "textColor", 0xFFFFFFFFu);
          const uint32_t border = ReadArgb(*map, "borderColor", caption);
          const bool dark_icons = ReadBool(*map, "darkIcons", false);

          SetTitleBarTheme(caption, text, border, dark_icons);
          result->Success();
          return;
        }

        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_theme_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
