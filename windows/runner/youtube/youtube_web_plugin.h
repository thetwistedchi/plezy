#pragma once

// Native WebView2 for the YouTube player, hosted like the mpv video: a
// disabled child window of the Flutter view, so it composites beneath the
// engine's topmost DirectComposition UI visual. No frame capture and no
// texture copies, which is what made the earlier texture-based WebView go
// black when out of focus, on resizes and after hibernation.

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wrl.h>

#include <memory>
#include <string>
#include <vector>

#include "WebView2.h"

void YouTubeWebPluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar);

namespace youtube_web {

class YouTubeWebPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit YouTubeWebPlugin(flutter::PluginRegistrarWindows* registrar);
  ~YouTubeWebPlugin() override;

  YouTubeWebPlugin(const YouTubeWebPlugin&) = delete;
  YouTubeWebPlugin& operator=(const YouTubeWebPlugin&) = delete;

 private:
  using Result = std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;

  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call, Result result);
  void Initialize(const flutter::EncodableMap& args, Result result);
  void Dispose();
  void UpdateBounds();
  void SendEvent(const std::string& type, const std::string& data);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  HWND host_ = nullptr;
  bool visible_ = true;
  bool initializing_ = false;
  std::vector<Result> pending_inits_;
  Microsoft::WRL::ComPtr<ICoreWebView2Environment> environment_;
  Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller_;
  Microsoft::WRL::ComPtr<ICoreWebView2> webview_;
  EventRegistrationToken message_token_{};
  EventRegistrationToken new_window_token_{};
  EventRegistrationToken process_failed_token_{};
  EventRegistrationToken navigation_token_{};
  // Bumped on dispose so callbacks of a torn-down WebView do nothing.
  int generation_ = 0;
};

}  // namespace youtube_web
