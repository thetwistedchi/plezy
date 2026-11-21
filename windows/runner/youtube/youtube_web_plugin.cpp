#include "youtube_web_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include <optional>
#include <variant>

#include "WebView2EnvironmentOptions.h"

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

void YouTubeWebPluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  youtube_web::YouTubeWebPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

namespace youtube_web {

namespace {

constexpr char kChannel[] = "com.plezy.retrowave/youtube_web";
constexpr DWORD kHostStyle = WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN | WS_DISABLED;

std::wstring ToWide(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int size = ::MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), wide.data(), size);
  return wide;
}

std::string ToUtf8(const wchar_t* text) {
  if (!text || !*text) return std::string();
  const int length = static_cast<int>(wcslen(text));
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, text, length, nullptr, 0, nullptr, nullptr);
  std::string utf8(size, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, text, length, utf8.data(), size, nullptr, nullptr);
  return utf8;
}

std::optional<std::string> GetString(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end() || !std::holds_alternative<std::string>(it->second)) return std::nullopt;
  return std::get<std::string>(it->second);
}

int GetInt(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return 0;
  if (std::holds_alternative<int32_t>(it->second)) return std::get<int32_t>(it->second);
  if (std::holds_alternative<int64_t>(it->second)) return static_cast<int>(std::get<int64_t>(it->second));
  if (std::holds_alternative<double>(it->second)) return static_cast<int>(std::get<double>(it->second));
  return 0;
}

bool GetBool(const flutter::EncodableMap& map, const char* key, bool fallback) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end() || !std::holds_alternative<bool>(it->second)) return fallback;
  return std::get<bool>(it->second);
}

}  // namespace

void YouTubeWebPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(std::make_unique<YouTubeWebPlugin>(registrar));
}

YouTubeWebPlugin::YouTubeWebPlugin(flutter::PluginRegistrarWindows* registrar) : registrar_(registrar) {
  method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), kChannel, &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) { HandleMethodCall(call, std::move(result)); });

  event_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), std::string(kChannel) + "/events", &flutter::StandardMethodCodec::GetInstance());
  event_channel_->SetStreamHandler(std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue*, std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        event_sink_ = std::move(events);
        return nullptr;
      },
      [this](const flutter::EncodableValue*) -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        event_sink_ = nullptr;
        return nullptr;
      }));
}

YouTubeWebPlugin::~YouTubeWebPlugin() {
  AuthClose();
  Dispose();
}

void YouTubeWebPlugin::SendEvent(const std::string& type, const std::string& data) {
  if (!event_sink_) return;
  flutter::EncodableMap event;
  event[flutter::EncodableValue("type")] = flutter::EncodableValue(type);
  event[flutter::EncodableValue("data")] = flutter::EncodableValue(data);
  event_sink_->Success(flutter::EncodableValue(event));
}

void YouTubeWebPlugin::HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call, Result result) {
  const auto& method = call.method_name();
  const auto* raw = call.arguments();
  const flutter::EncodableMap empty;
  const flutter::EncodableMap& args =
      raw && std::holds_alternative<flutter::EncodableMap>(*raw) ? std::get<flutter::EncodableMap>(*raw) : empty;

  if (method == "initialize") {
    Initialize(args, std::move(result));
    return;
  }
  if (method == "dispose") {
    Dispose();
    result->Success();
    return;
  }
  if (method == "setRect") {
    if (host_) {
      const int left = GetInt(args, "left");
      const int top = GetInt(args, "top");
      const int width = (std::max)(0, GetInt(args, "right") - left);
      const int height = (std::max)(0, GetInt(args, "bottom") - top);
      ::SetWindowPos(host_, HWND_TOP, left, top, width, height, SWP_NOACTIVATE);
      UpdateBounds();
    }
    result->Success();
    return;
  }
  if (method == "setVisible") {
    visible_ = GetBool(args, "visible", true);
    if (host_) ::ShowWindow(host_, visible_ ? SW_SHOWNA : SW_HIDE);
    if (controller_) controller_->put_IsVisible(visible_ ? TRUE : FALSE);
    result->Success();
    return;
  }

  if (method == "runtimeVersion") {
    LPWSTR version = nullptr;
    if (SUCCEEDED(GetAvailableCoreWebView2BrowserVersionString(nullptr, &version)) && version) {
      result->Success(flutter::EncodableValue(ToUtf8(version)));
      ::CoTaskMemFree(version);
    } else {
      result->Success();
    }
    return;
  }
  if (method == "authOpen") {
    const std::string url = GetString(args, "url").value_or("");
    auto shared = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
    AuthCreate(args, true, [this, shared, url](bool ok, const std::string& error) {
      if (!ok) {
        shared->Error("INIT_FAILED", error);
        return;
      }
      if (!url.empty()) auth_webview_->Navigate(ToWide(url).c_str());
      shared->Success();
    });
    return;
  }
  if (method == "authVisit") {
    // YouTube history: the watch page in a hidden, muted view that takes
    // no input, beneath the Flutter UI. Dart closes it (authClose) later.
    if (auth_webview_) {
      result->Success();
      return;
    }
    const std::string url = GetString(args, "url").value_or("");
    auto shared = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
    flutter::EncodableMap visit = args;
    visit[flutter::EncodableValue("interactive")] = flutter::EncodableValue(false);
    AuthCreate(visit, true, [this, shared, url](bool ok, const std::string& error) {
      if (!ok) {
        shared->Error("INIT_FAILED", error);
        return;
      }
      if (auth_host_) ::SetWindowPos(auth_host_, HWND_BOTTOM, 0, 0, 640, 360, SWP_NOACTIVATE);
      if (auth_controller_) {
        RECT bounds{0, 0, 640, 360};
        auth_controller_->put_Bounds(bounds);
      }
      ComPtr<ICoreWebView2_8> webview8;
      if (auth_webview_ && SUCCEEDED(auth_webview_.As(&webview8))) webview8->put_IsMuted(TRUE);
      if (auth_webview_ && !url.empty()) auth_webview_->Navigate(ToWide(url).c_str());
      shared->Success();
    });
    return;
  }
  if (method == "authRect") {
    if (auth_host_) {
      const int left = GetInt(args, "left");
      const int top = GetInt(args, "top");
      const int width = (std::max)(0, GetInt(args, "right") - left);
      const int height = (std::max)(0, GetInt(args, "bottom") - top);
      ::SetWindowPos(auth_host_, HWND_TOP, left, top, width, height, SWP_NOACTIVATE);
      if (auth_controller_) {
        RECT bounds{};
        ::GetClientRect(auth_host_, &bounds);
        auth_controller_->put_Bounds(bounds);
        auth_controller_->NotifyParentWindowPositionChanged();
      }
    }
    result->Success();
    return;
  }
  if (method == "authClose") {
    AuthClose();
    result->Success();
    return;
  }
  if (method == "authRun") {
    // clearCookies / clearCache, on the open sign-in view or a hidden one.
    const std::string action = GetString(args, "action").value_or("");
    auto shared = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
    auto run = [this, shared, action](bool temporary) {
      if (temporary && auth_host_) ::ShowWindow(auth_host_, SW_HIDE);
      // Closing the view inside the WebView's own completion callback
      // crashed the app; Dart closes a temporary view afterwards (authClose)
      // when told so by the result.
      AuthRun(action, [shared, temporary](bool ok) {
        if (ok) {
          shared->Success(flutter::EncodableValue(temporary));
        } else {
          shared->Error("FAILED", "The action failed");
        }
      });
    };
    if (auth_webview_) {
      run(false);
      return;
    }
    AuthCreate(args, false, [shared, run](bool ok, const std::string& error) {
      if (!ok) {
        shared->Error("INIT_FAILED", error);
        return;
      }
      run(true);
    });
    return;
  }

  if (!webview_) {
    result->Error("NOT_READY", "The YouTube WebView is not initialized");
    return;
  }

  if (method == "loadUrl") {
    const auto url = GetString(args, "url");
    if (!url) {
      result->Error("INVALID_ARGS", "Missing url");
      return;
    }
    const HRESULT hr = webview_->Navigate(ToWide(*url).c_str());
    if (FAILED(hr)) {
      result->Error("NAVIGATE_FAILED", "Navigate failed");
      return;
    }
    result->Success();
  } else if (method == "postWebMessage") {
    const auto json = GetString(args, "json");
    if (json) webview_->PostWebMessageAsJson(ToWide(*json).c_str());
    result->Success();
  } else if (method == "executeScript") {
    const auto script = GetString(args, "script").value_or("");
    auto shared = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
    const HRESULT hr = webview_->ExecuteScript(
        ToWide(script).c_str(),
        Callback<ICoreWebView2ExecuteScriptCompletedHandler>([shared](HRESULT error, LPCWSTR value) -> HRESULT {
          if (FAILED(error)) {
            shared->Error("SCRIPT_FAILED", "ExecuteScript failed");
          } else {
            shared->Success(flutter::EncodableValue(ToUtf8(value)));
          }
          return S_OK;
        }).Get());
    if (FAILED(hr)) shared->Error("SCRIPT_FAILED", "ExecuteScript could not start");
  } else if (method == "suspend") {
    ComPtr<ICoreWebView2_3> webview3;
    if (SUCCEEDED(webview_.As(&webview3))) {
      if (controller_) controller_->put_IsVisible(FALSE);
      webview3->TrySuspend(nullptr);
    }
    result->Success();
  } else if (method == "resume") {
    ComPtr<ICoreWebView2_3> webview3;
    if (SUCCEEDED(webview_.As(&webview3))) webview3->Resume();
    if (controller_) controller_->put_IsVisible(visible_ ? TRUE : FALSE);
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void YouTubeWebPlugin::Initialize(const flutter::EncodableMap& args, Result result) {
  if (webview_) {
    result->Success(flutter::EncodableValue(true));
    return;
  }
  pending_inits_.push_back(std::move(result));
  if (initializing_) return;
  initializing_ = true;

  const int generation = ++generation_;
  const std::wstring user_data = ToWide(GetString(args, "userDataFolder").value_or(""));
  const std::wstring arguments = ToWide(GetString(args, "arguments").value_or(""));
  const std::wstring host_name = ToWide(GetString(args, "hostName").value_or(""));
  const std::wstring host_folder = ToWide(GetString(args, "hostFolder").value_or(""));
  const std::wstring script = ToWide(GetString(args, "script").value_or(""));

  auto finish = [this, generation](bool ok, const std::string& error) {
    if (generation != generation_) return;
    initializing_ = false;
    auto pending = std::move(pending_inits_);
    pending_inits_.clear();
    for (auto& r : pending) {
      if (ok) {
        r->Success(flutter::EncodableValue(true));
      } else {
        r->Error("INIT_FAILED", error);
      }
    }
  };

  if (!host_) {
    // Child of the Flutter view, like the mpv video window: it composites
    // beneath the engine's topmost UI visual. WS_DISABLED keeps it (and the
    // WebView's own windows inside it) out of input targeting, so the mouse
    // and keyboard stay with Flutter's controls.
    const HWND view = registrar_->GetView()->GetNativeWindow();
    host_ = ::CreateWindowExW(
        WS_EX_NOPARENTNOTIFY, L"STATIC", L"", kHostStyle, 0, 0, 16, 16, view, nullptr, ::GetModuleHandle(nullptr),
        nullptr);
    if (!host_) {
      finish(false, "Could not create the host window");
      return;
    }
    ::ShowWindow(host_, visible_ ? SW_SHOWNA : SW_HIDE);
  }

  auto options = Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
  options->put_AdditionalBrowserArguments(arguments.c_str());

  const HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
      nullptr, user_data.empty() ? nullptr : user_data.c_str(), options.Get(),
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [this, generation, finish, host_name, host_folder, script](
              HRESULT env_result, ICoreWebView2Environment* environment) -> HRESULT {
            if (generation != generation_) return S_OK;
            if (FAILED(env_result) || !environment) {
              finish(false, "WebView2 environment failed");
              return S_OK;
            }
            environment_ = environment;
            const HRESULT create = environment_->CreateCoreWebView2Controller(
                host_,
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                    [this, generation, finish, host_name, host_folder, script](
                        HRESULT controller_result, ICoreWebView2Controller* controller) -> HRESULT {
                      if (generation != generation_) {
                        if (controller) controller->Close();
                        return S_OK;
                      }
                      if (FAILED(controller_result) || !controller) {
                        finish(false, "WebView2 controller failed");
                        return S_OK;
                      }
                      controller_ = controller;
                      controller_->get_CoreWebView2(&webview_);

                      ComPtr<ICoreWebView2Controller2> controller2;
                      if (SUCCEEDED(controller_.As(&controller2))) {
                        COREWEBVIEW2_COLOR black{255, 0, 0, 0};
                        controller2->put_DefaultBackgroundColor(black);
                      }

                      ComPtr<ICoreWebView2Settings> settings;
                      if (SUCCEEDED(webview_->get_Settings(&settings))) {
                        settings->put_AreDefaultContextMenusEnabled(FALSE);
                        settings->put_AreDevToolsEnabled(FALSE);
                        settings->put_IsStatusBarEnabled(FALSE);
                        settings->put_IsZoomControlEnabled(FALSE);
                      }

                      ComPtr<ICoreWebView2_3> webview3;
                      if (!host_name.empty() && SUCCEEDED(webview_.As(&webview3))) {
                        webview3->SetVirtualHostNameToFolderMapping(
                            host_name.c_str(), host_folder.c_str(), COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);
                      }
                      if (!script.empty()) webview_->AddScriptToExecuteOnDocumentCreated(script.c_str(), nullptr);

                      webview_->add_WebMessageReceived(
                          Callback<ICoreWebView2WebMessageReceivedEventHandler>(
                              [this](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* message) -> HRESULT {
                                LPWSTR json = nullptr;
                                if (SUCCEEDED(message->get_WebMessageAsJson(&json)) && json) {
                                  SendEvent("message", ToUtf8(json));
                                  ::CoTaskMemFree(json);
                                }
                                return S_OK;
                              })
                              .Get(),
                          &message_token_);

                      webview_->add_NewWindowRequested(
                          Callback<ICoreWebView2NewWindowRequestedEventHandler>(
                              [](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* request) -> HRESULT {
                                request->put_Handled(TRUE);
                                return S_OK;
                              })
                              .Get(),
                          &new_window_token_);

                      webview_->add_ProcessFailed(
                          Callback<ICoreWebView2ProcessFailedEventHandler>(
                              [this](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs* failure) -> HRESULT {
                                COREWEBVIEW2_PROCESS_FAILED_KIND kind{};
                                failure->get_ProcessFailedKind(&kind);
                                SendEvent("processFailed", std::to_string(static_cast<int>(kind)));
                                return S_OK;
                              })
                              .Get(),
                          &process_failed_token_);

                      webview_->add_NavigationCompleted(
                          Callback<ICoreWebView2NavigationCompletedEventHandler>(
                              [this](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
                                BOOL success = FALSE;
                                args->get_IsSuccess(&success);
                                SendEvent("navigated", success ? "ok" : "failed");
                                return S_OK;
                              })
                              .Get(),
                          &navigation_token_);

                      controller_->put_IsVisible(visible_ ? TRUE : FALSE);
                      UpdateBounds();
                      finish(true, "");
                      return S_OK;
                    })
                    .Get());
            if (FAILED(create)) finish(false, "WebView2 controller could not start");
            return S_OK;
          })
          .Get());

  if (FAILED(hr)) finish(false, "WebView2 runtime not available");
}

void YouTubeWebPlugin::AuthCreate(const flutter::EncodableMap& args, bool visible, AuthReady ready) {
  if (auth_webview_) {
    if (visible && auth_host_) ::ShowWindow(auth_host_, SW_SHOWNA);
    if (visible && auth_controller_) auth_controller_->put_IsVisible(TRUE);
    ready(true, "");
    return;
  }
  AuthClose();
  const int generation = ++auth_generation_;
  const std::wstring user_data = ToWide(GetString(args, "userDataFolder").value_or(""));
  const std::wstring arguments = ToWide(GetString(args, "arguments").value_or(""));

  // Not WS_DISABLED like the player's host: the sign-in page takes input.
  // The hidden history visit (authVisit) takes none.
  const bool interactive = GetBool(args, "interactive", true);
  const HWND view = registrar_->GetView()->GetNativeWindow();
  auth_host_ = ::CreateWindowExW(WS_EX_NOPARENTNOTIFY, L"STATIC", L"",
                                 WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN | (interactive ? 0 : WS_DISABLED),
                                 0, 0, 16, 16, view, nullptr, ::GetModuleHandle(nullptr), nullptr);
  if (!auth_host_) {
    ready(false, "Could not create the host window");
    return;
  }
  if (visible) ::ShowWindow(auth_host_, SW_SHOWNA);

  auto options = Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
  options->put_AdditionalBrowserArguments(arguments.c_str());
  const HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
      nullptr, user_data.empty() ? nullptr : user_data.c_str(), options.Get(),
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [this, generation, visible, ready](HRESULT env_result, ICoreWebView2Environment* environment) -> HRESULT {
            if (generation != auth_generation_) return S_OK;
            if (FAILED(env_result) || !environment) {
              ready(false, "WebView2 environment failed");
              return S_OK;
            }
            const HRESULT create = environment->CreateCoreWebView2Controller(
                auth_host_,
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                    [this, generation, visible, ready](HRESULT controller_result,
                                                       ICoreWebView2Controller* controller) -> HRESULT {
                      if (generation != auth_generation_) {
                        if (controller) controller->Close();
                        return S_OK;
                      }
                      if (FAILED(controller_result) || !controller) {
                        ready(false, "WebView2 controller failed");
                        return S_OK;
                      }
                      auth_controller_ = controller;
                      auth_controller_->get_CoreWebView2(&auth_webview_);
                      ComPtr<ICoreWebView2Settings> settings;
                      if (SUCCEEDED(auth_webview_->get_Settings(&settings))) {
                        settings->put_AreDevToolsEnabled(FALSE);
                        settings->put_IsStatusBarEnabled(FALSE);
                      }
                      // Google's sign-in opens some steps as pop-ups: keep
                      // them in the same view.
                      auth_webview_->add_NewWindowRequested(
                          Callback<ICoreWebView2NewWindowRequestedEventHandler>(
                              [this](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* request) -> HRESULT {
                                LPWSTR uri = nullptr;
                                if (SUCCEEDED(request->get_Uri(&uri)) && uri) {
                                  if (auth_webview_) auth_webview_->Navigate(uri);
                                  ::CoTaskMemFree(uri);
                                }
                                request->put_Handled(TRUE);
                                return S_OK;
                              })
                              .Get(),
                          &auth_new_window_token_);
                      RECT bounds{};
                      ::GetClientRect(auth_host_, &bounds);
                      auth_controller_->put_Bounds(bounds);
                      auth_controller_->put_IsVisible(visible ? TRUE : FALSE);
                      ready(true, "");
                      return S_OK;
                    })
                    .Get());
            if (FAILED(create)) ready(false, "WebView2 controller could not start");
            return S_OK;
          })
          .Get());
  if (FAILED(hr)) ready(false, "WebView2 runtime not available");
}

void YouTubeWebPlugin::AuthRun(const std::string& action, std::function<void(bool ok)> done) {
  if (!auth_webview_) {
    done(false);
    return;
  }
  if (action == "clearCookies") {
    ComPtr<ICoreWebView2_2> webview2;
    ComPtr<ICoreWebView2CookieManager> cookies;
    if (SUCCEEDED(auth_webview_.As(&webview2)) && SUCCEEDED(webview2->get_CookieManager(&cookies)) && cookies) {
      cookies->DeleteAllCookies();
      done(true);
    } else {
      done(false);
    }
    return;
  }
  if (action == "clearCache") {
    const HRESULT hr = auth_webview_->CallDevToolsProtocolMethod(
        L"Network.clearBrowserCache", L"{}",
        Callback<ICoreWebView2CallDevToolsProtocolMethodCompletedHandler>([done](HRESULT error, LPCWSTR) -> HRESULT {
          done(SUCCEEDED(error));
          return S_OK;
        }).Get());
    if (FAILED(hr)) done(false);
    return;
  }
  done(false);
}

void YouTubeWebPlugin::AuthClose() {
  ++auth_generation_;
  if (auth_webview_) auth_webview_->remove_NewWindowRequested(auth_new_window_token_);
  if (auth_controller_) auth_controller_->Close();
  auth_webview_.Reset();
  auth_controller_.Reset();
  if (auth_host_) {
    ::DestroyWindow(auth_host_);
    auth_host_ = nullptr;
  }
}

void YouTubeWebPlugin::UpdateBounds() {
  if (!host_ || !controller_) return;
  RECT bounds{};
  ::GetClientRect(host_, &bounds);
  controller_->put_Bounds(bounds);
  controller_->NotifyParentWindowPositionChanged();
}

void YouTubeWebPlugin::Dispose() {
  ++generation_;
  initializing_ = false;
  auto pending = std::move(pending_inits_);
  pending_inits_.clear();
  for (auto& r : pending) r->Error("DISPOSED", "The YouTube WebView was disposed");

  if (webview_) {
    webview_->remove_WebMessageReceived(message_token_);
    webview_->remove_NewWindowRequested(new_window_token_);
    webview_->remove_ProcessFailed(process_failed_token_);
    webview_->remove_NavigationCompleted(navigation_token_);
  }
  if (controller_) controller_->Close();
  webview_.Reset();
  controller_.Reset();
  environment_.Reset();
  if (host_) {
    ::DestroyWindow(host_);
    host_ = nullptr;
  }
}

}  // namespace youtube_web
