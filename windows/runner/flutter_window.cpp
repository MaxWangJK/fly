#include "flutter_window.h"

#include <optional>
#include <flutter/method_result_functions.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  file_transfer_ = CreateFileTransferChannel(flutter_controller_->engine()->messenger());
  license_storage_ = CreateLicenseStorageChannel(flutter_controller_->engine()->messenger());
  lifecycle_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(flutter_controller_->engine()->messenger(), "fly/window_lifecycle", &flutter::StandardMethodCodec::GetInstance());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  license_storage_.reset();
  lifecycle_.reset();
  file_transfer_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE && lifecycle_ && !close_approved_) {
    if (close_pending_) return 0;
    close_pending_ = true;
    auto finish = [this, hwnd](bool allowed) {
      close_pending_ = false;
      if (allowed) { close_approved_ = true; PostMessage(hwnd, WM_CLOSE, 0, 0); }
    };
    lifecycle_->InvokeMethod("prepareClose", nullptr,
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
        [finish](const flutter::EncodableValue* value) { const auto* allowed = value ? std::get_if<bool>(value) : nullptr; finish(allowed && *allowed); },
        [finish](const std::string&, const std::string&, const flutter::EncodableValue*) { finish(false); },
        [finish]() { finish(true); }));
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
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
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
