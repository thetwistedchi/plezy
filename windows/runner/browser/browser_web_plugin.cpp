#include "browser_web_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include <algorithm>
#include <cwctype>
#include <optional>
#include <variant>

#include "WebView2EnvironmentOptions.h"

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

void BrowserWebPluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  browser_web::BrowserWebPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

namespace browser_web {

namespace {

constexpr char kChannel[] = "com.plezy.retrowave/browser";
constexpr DWORD kHostStyle = WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN;

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

// Takes ownership of a CoTaskMem string from WebView2.
std::string TakeString(LPWSTR value) {
  std::string out = ToUtf8(value);
  if (value) ::CoTaskMemFree(value);
  return out;
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

std::wstring Lower(std::wstring text) {
  std::transform(text.begin(), text.end(), text.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return text;
}

bool StartsWith(const std::wstring& text, const std::wstring& prefix) {
  return text.size() >= prefix.size() && text.compare(0, prefix.size(), prefix) == 0;
}

// The host of an http(s) address, lower case, without port.
std::wstring HostOf(const std::wstring& uri) {
  const auto scheme = uri.find(L"://");
  if (scheme == std::wstring::npos) return std::wstring();
  auto start = scheme + 3;
  auto end = uri.find_first_of(L"/?#", start);
  std::wstring authority = uri.substr(start, end == std::wstring::npos ? std::wstring::npos : end - start);
  const auto at = authority.rfind(L'@');
  if (at != std::wstring::npos) authority = authority.substr(at + 1);
  if (!authority.empty() && authority[0] == L'[') return Lower(authority);  // IPv6 literal
  const auto colon = authority.find(L':');
  if (colon != std::wstring::npos) authority = authority.substr(0, colon);
  return Lower(authority);
}

// Addresses that usually only exist over http: this machine, the local
// network (router, NAS) and single-label names. They are never upgraded.
bool IsLocalHost(const std::wstring& host) {
  if (host.empty() || host == L"localhost" || host[0] == L'[') return true;
  if (host.find(L'.') == std::wstring::npos) return true;
  const std::wstring local = L".local", lan = L".lan", home = L".home.arpa";
  auto ends = [&](const std::wstring& suffix) {
    return host.size() >= suffix.size() && host.compare(host.size() - suffix.size(), suffix.size(), suffix) == 0;
  };
  if (ends(local) || ends(lan) || ends(home)) return true;
  int a = -1, b = -1, c = -1, d = -1;
  if (swscanf_s(host.c_str(), L"%d.%d.%d.%d", &a, &b, &c, &d) == 4) {
    return a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31) ||
           (a == 169 && b == 254) || (a == 100 && b >= 64 && b <= 127);
  }
  return false;
}

}  // namespace

void BrowserWebPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(std::make_unique<BrowserWebPlugin>(registrar));
}

BrowserWebPlugin::BrowserWebPlugin(flutter::PluginRegistrarWindows* registrar) : registrar_(registrar) {
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

BrowserWebPlugin::~BrowserWebPlugin() { DisposeAll(); }

BrowserTab* BrowserWebPlugin::Find(int id) {
  auto it = tabs_.find(id);
  return it == tabs_.end() ? nullptr : it->second.get();
}

void BrowserWebPlugin::Send(int tab, const std::string& type, const flutter::EncodableMap& data) {
  if (!event_sink_) return;
  flutter::EncodableMap event = data;
  event[flutter::EncodableValue("type")] = flutter::EncodableValue(type);
  event[flutter::EncodableValue("tab")] = flutter::EncodableValue(tab);
  event_sink_->Success(flutter::EncodableValue(event));
}

void BrowserWebPlugin::SendState(BrowserTab& tab) {
  if (!tab.webview) return;
  LPWSTR source = nullptr;
  LPWSTR title = nullptr;
  BOOL back = FALSE;
  BOOL forward = FALSE;
  tab.webview->get_Source(&source);
  tab.webview->get_DocumentTitle(&title);
  tab.webview->get_CanGoBack(&back);
  tab.webview->get_CanGoForward(&forward);
  flutter::EncodableMap data;
  data[flutter::EncodableValue("url")] = flutter::EncodableValue(TakeString(source));
  data[flutter::EncodableValue("title")] = flutter::EncodableValue(TakeString(title));
  data[flutter::EncodableValue("canGoBack")] = flutter::EncodableValue(back == TRUE);
  data[flutter::EncodableValue("canGoForward")] = flutter::EncodableValue(forward == TRUE);
  Send(tab.id, "state", data);
}

void BrowserWebPlugin::ApplyLayout() {
  const int width = (std::max)(0, static_cast<int>(rect_.right - rect_.left));
  const int height = (std::max)(0, static_cast<int>(rect_.bottom - rect_.top));
  for (auto& [id, tab] : tabs_) {
    if (!tab->host) continue;
    const bool show = visible_ && id == active_ && width > 0 && height > 0;
    ::SetWindowPos(tab->host, HWND_TOP, rect_.left, rect_.top, width, height, SWP_NOACTIVATE);
    ::ShowWindow(tab->host, show ? SW_SHOWNA : SW_HIDE);
    if (tab->controller) {
      RECT bounds{0, 0, width, height};
      tab->controller->put_Bounds(bounds);
      tab->controller->put_IsVisible(show ? TRUE : FALSE);
      tab->controller->NotifyParentWindowPositionChanged();
    }
  }
}

void BrowserWebPlugin::HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call, Result result) {
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
    DisposeAll();
    result->Success();
    return;
  }
  if (method == "setRect") {
    const int left = GetInt(args, "left");
    const int top = GetInt(args, "top");
    rect_ = RECT{left, top, (std::max)(left, GetInt(args, "right")), (std::max)(top, GetInt(args, "bottom"))};
    ApplyLayout();
    result->Success();
    return;
  }
  if (method == "setVisible") {
    visible_ = GetBool(args, "visible", false);
    ApplyLayout();
    result->Success();
    return;
  }
  if (method == "setActive") {
    active_ = GetInt(args, "id");
    ApplyLayout();
    result->Success();
    return;
  }
  if (method == "setHttpsUpgrade") {
    https_upgrade_ = GetBool(args, "value", true);
    result->Success();
    return;
  }
  if (method == "answerPermission" || method == "answerDownload") {
    const int request = GetInt(args, "request");
    const bool allow = GetBool(args, "allow", false);
    if (method == "answerPermission") {
      auto it = permission_args_.find(request);
      if (it != permission_args_.end()) {
        it->second->put_State(allow ? COREWEBVIEW2_PERMISSION_STATE_ALLOW : COREWEBVIEW2_PERMISSION_STATE_DENY);
        permission_args_.erase(it);
      }
    } else {
      auto it = download_args_.find(request);
      if (it != download_args_.end()) {
        it->second->put_Cancel(allow ? FALSE : TRUE);
        download_args_.erase(it);
      }
    }
    auto deferral = deferrals_.find(request);
    if (deferral != deferrals_.end()) {
      deferral->second->Complete();
      deferrals_.erase(deferral);
    }
    result->Success();
    return;
  }

  const int id = GetInt(args, "id");
  if (method == "createTab") {
    CreateTab(id, ToWide(GetString(args, "url").value_or("")), std::move(result));
    return;
  }
  if (method == "closeTab") {
    CloseTab(id);
    result->Success();
    return;
  }

  BrowserTab* tab = Find(id);
  if (!tab || !tab->webview) {
    result->Error("NO_TAB", "No such browser tab");
    return;
  }

  if (method == "navigate") {
    const std::wstring url = ToWide(GetString(args, "url").value_or(""));
    if (GetBool(args, "allowHttp", false)) {
      const std::wstring host = HostOf(url);
      if (!host.empty() && std::find(tab->http_hosts.begin(), tab->http_hosts.end(), host) == tab->http_hosts.end()) {
        tab->http_hosts.push_back(host);
      }
    }
    if (FAILED(tab->webview->Navigate(url.c_str()))) {
      result->Error("NAVIGATE_FAILED", "Navigate failed");
      return;
    }
    result->Success();
  } else if (method == "back") {
    tab->webview->GoBack();
    result->Success();
  } else if (method == "forward") {
    tab->webview->GoForward();
    result->Success();
  } else if (method == "reload") {
    tab->webview->Reload();
    result->Success();
  } else if (method == "stop") {
    tab->webview->Stop();
    result->Success();
  } else if (method == "focus") {
    if (tab->controller) tab->controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
    result->Success();
  } else if (method == "suspend") {
    ComPtr<ICoreWebView2_3> webview3;
    if (SUCCEEDED(tab->webview.As(&webview3))) {
      if (tab->controller) tab->controller->put_IsVisible(FALSE);
      webview3->TrySuspend(nullptr);
    }
    result->Success();
  } else if (method == "resume") {
    ComPtr<ICoreWebView2_3> webview3;
    if (SUCCEEDED(tab->webview.As(&webview3))) webview3->Resume();
    ApplyLayout();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void BrowserWebPlugin::Initialize(const flutter::EncodableMap& args, Result result) {
  https_upgrade_ = GetBool(args, "httpsUpgrade", true);
  if (environment_) {
    result->Success(flutter::EncodableValue(true));
    return;
  }
  pending_inits_.push_back(std::move(result));
  if (initializing_) return;
  initializing_ = true;

  const int generation = ++generation_;
  const std::wstring user_data = ToWide(GetString(args, "userDataFolder").value_or(""));
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

  auto options = Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
  const HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
      nullptr, user_data.empty() ? nullptr : user_data.c_str(), options.Get(),
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [this, generation, finish](HRESULT env_result, ICoreWebView2Environment* environment) -> HRESULT {
            if (generation != generation_) return S_OK;
            if (FAILED(env_result) || !environment) {
              finish(false, "WebView2 environment failed");
              return S_OK;
            }
            environment_ = environment;
            finish(true, "");
            return S_OK;
          })
          .Get());
  if (FAILED(hr)) finish(false, "WebView2 runtime not available");
}

void BrowserWebPlugin::CreateTab(int id, const std::wstring& url, Result result) {
  if (!environment_) {
    result->Error("NOT_READY", "Browser not initialized");
    return;
  }
  if (Find(id)) {
    result->Success(flutter::EncodableValue(true));
    return;
  }
  auto tab = std::make_unique<BrowserTab>();
  tab->id = id;
  const HWND view = registrar_->GetView()->GetNativeWindow();
  tab->host = ::CreateWindowExW(
      WS_EX_NOPARENTNOTIFY, L"STATIC", L"", kHostStyle, 0, 0, 16, 16, view, nullptr, ::GetModuleHandle(nullptr), nullptr);
  if (!tab->host) {
    result->Error("CREATE_FAILED", "Could not create the tab window");
    return;
  }
  ::ShowWindow(tab->host, SW_HIDE);
  BrowserTab* raw = tab.get();
  tabs_[id] = std::move(tab);

  auto shared = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
  const int generation = generation_;
  const HRESULT hr = environment_->CreateCoreWebView2Controller(
      raw->host,
      Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
          [this, id, generation, url, shared](HRESULT controller_result, ICoreWebView2Controller* controller) -> HRESULT {
            BrowserTab* tab = Find(id);
            if (generation != generation_ || !tab) {
              if (controller) controller->Close();
              shared->Error("CLOSED", "The tab was closed");
              return S_OK;
            }
            if (FAILED(controller_result) || !controller) {
              shared->Error("CREATE_FAILED", "WebView2 controller failed");
              return S_OK;
            }
            tab->controller = controller;
            tab->controller->get_CoreWebView2(&tab->webview);

            ComPtr<ICoreWebView2Settings> settings;
            if (SUCCEEDED(tab->webview->get_Settings(&settings))) {
              // No bridge between web pages and the app.
              settings->put_IsWebMessageEnabled(FALSE);
              settings->put_AreHostObjectsAllowed(FALSE);
              settings->put_AreDevToolsEnabled(FALSE);
              settings->put_IsStatusBarEnabled(TRUE);
              settings->put_AreDefaultContextMenusEnabled(TRUE);
              settings->put_IsZoomControlEnabled(TRUE);
              ComPtr<ICoreWebView2Settings4> settings4;
              if (SUCCEEDED(settings.As(&settings4))) {
                settings4->put_IsPasswordAutosaveEnabled(FALSE);
                settings4->put_IsGeneralAutofillEnabled(FALSE);
              }
            }
            Wire(*tab);
            ApplyLayout();
            if (!url.empty()) tab->webview->Navigate(url.c_str());
            shared->Success(flutter::EncodableValue(true));
            return S_OK;
          })
          .Get());
  if (FAILED(hr)) {
    CloseTab(id);
    shared->Error("CREATE_FAILED", "WebView2 controller could not start");
  }
}

void BrowserWebPlugin::Wire(BrowserTab& tab) {
  const int id = tab.id;
  auto& webview = tab.webview;
  EventRegistrationToken token{};

  webview->add_SourceChanged(Callback<ICoreWebView2SourceChangedEventHandler>(
                                 [this, id](ICoreWebView2*, ICoreWebView2SourceChangedEventArgs*) -> HRESULT {
                                   if (auto* t = Find(id)) SendState(*t);
                                   return S_OK;
                                 })
                                 .Get(),
                             &token);
  tab.tokens.push_back({0, token});

  webview->add_DocumentTitleChanged(Callback<ICoreWebView2DocumentTitleChangedEventHandler>(
                                        [this, id](ICoreWebView2*, IUnknown*) -> HRESULT {
                                          if (auto* t = Find(id)) SendState(*t);
                                          return S_OK;
                                        })
                                        .Get(),
                                    &token);
  tab.tokens.push_back({1, token});

  webview->add_HistoryChanged(Callback<ICoreWebView2HistoryChangedEventHandler>(
                                  [this, id](ICoreWebView2*, IUnknown*) -> HRESULT {
                                    if (auto* t = Find(id)) SendState(*t);
                                    return S_OK;
                                  })
                                  .Get(),
                              &token);
  tab.tokens.push_back({2, token});

  webview->add_NavigationStarting(
      Callback<ICoreWebView2NavigationStartingEventHandler>(
          [this, id](ICoreWebView2* sender, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
            LPWSTR raw = nullptr;
            args->get_Uri(&raw);
            const std::wstring uri = raw ? raw : L"";
            if (raw) ::CoTaskMemFree(raw);
            const std::wstring lower = Lower(uri);
            // Local files and script addresses never load in a tab.
            if (StartsWith(lower, L"file:") || StartsWith(lower, L"javascript:")) {
              args->put_Cancel(TRUE);
              Send(id, "blockedScheme", {{flutter::EncodableValue("url"), flutter::EncodableValue(ToUtf8(uri.c_str()))}});
              return S_OK;
            }
            BrowserTab* tab = Find(id);
            if (https_upgrade_ && tab && StartsWith(lower, L"http://")) {
              const std::wstring host = HostOf(uri);
              const bool allowed =
                  std::find(tab->http_hosts.begin(), tab->http_hosts.end(), host) != tab->http_hosts.end();
              if (!IsLocalHost(host) && !allowed) {
                args->put_Cancel(TRUE);
                const std::wstring secure = L"https://" + uri.substr(7);
                sender->Navigate(secure.c_str());
                Send(id, "upgraded", {{flutter::EncodableValue("url"), flutter::EncodableValue(ToUtf8(uri.c_str()))}});
                return S_OK;
              }
            }
            Send(id, "loading", {{flutter::EncodableValue("url"), flutter::EncodableValue(ToUtf8(uri.c_str()))}});
            return S_OK;
          })
          .Get(),
      &token);
  tab.tokens.push_back({3, token});

  webview->add_NavigationCompleted(
      Callback<ICoreWebView2NavigationCompletedEventHandler>(
          [this, id](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
            BOOL success = FALSE;
            COREWEBVIEW2_WEB_ERROR_STATUS status = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
            args->get_IsSuccess(&success);
            args->get_WebErrorStatus(&status);
            Send(id, "loaded",
                 {{flutter::EncodableValue("ok"), flutter::EncodableValue(success == TRUE)},
                  {flutter::EncodableValue("error"), flutter::EncodableValue(static_cast<int>(status))}});
            if (auto* t = Find(id)) SendState(*t);
            return S_OK;
          })
          .Get(),
      &token);
  tab.tokens.push_back({4, token});

  // Pop-up blocker: a new window only opens (as a tab) after a click.
  webview->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [this, id](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
            args->put_Handled(TRUE);
            LPWSTR raw = nullptr;
            args->get_Uri(&raw);
            const std::string uri = TakeString(raw);
            BOOL user = FALSE;
            args->get_IsUserInitiated(&user);
            Send(id, user ? "openTab" : "popupBlocked", {{flutter::EncodableValue("url"), flutter::EncodableValue(uri)}});
            return S_OK;
          })
          .Get(),
      &token);
  tab.tokens.push_back({5, token});

  webview->add_PermissionRequested(
      Callback<ICoreWebView2PermissionRequestedEventHandler>(
          [this, id](ICoreWebView2*, ICoreWebView2PermissionRequestedEventArgs* args) -> HRESULT {
            COREWEBVIEW2_PERMISSION_KIND kind = COREWEBVIEW2_PERMISSION_KIND_UNKNOWN_PERMISSION;
            args->get_PermissionKind(&kind);
            // Notifications are the most common spam path: never asked.
            if (kind == COREWEBVIEW2_PERMISSION_KIND_NOTIFICATIONS) {
              args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
              return S_OK;
            }
            LPWSTR raw = nullptr;
            args->get_Uri(&raw);
            const std::string uri = TakeString(raw);
            ComPtr<ICoreWebView2Deferral> deferral;
            if (FAILED(args->GetDeferral(&deferral))) {
              args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
              return S_OK;
            }
            const int request = next_request_++;
            deferrals_[request] = deferral;
            permission_args_[request] = args;
            Send(id, "permission",
                 {{flutter::EncodableValue("request"), flutter::EncodableValue(request)},
                  {flutter::EncodableValue("kind"), flutter::EncodableValue(static_cast<int>(kind))},
                  {flutter::EncodableValue("url"), flutter::EncodableValue(uri)}});
            return S_OK;
          })
          .Get(),
      &token);
  tab.tokens.push_back({6, token});

  ComPtr<ICoreWebView2_4> webview4;
  if (SUCCEEDED(webview.As(&webview4))) {
    webview4->add_DownloadStarting(
        Callback<ICoreWebView2DownloadStartingEventHandler>(
            [this, id](ICoreWebView2*, ICoreWebView2DownloadStartingEventArgs* args) -> HRESULT {
              ComPtr<ICoreWebView2DownloadOperation> operation;
              args->get_DownloadOperation(&operation);
              LPWSTR raw_uri = nullptr;
              LPWSTR raw_path = nullptr;
              INT64 size = 0;
              if (operation) {
                operation->get_Uri(&raw_uri);
                operation->get_TotalBytesToReceive(&size);
              }
              args->get_ResultFilePath(&raw_path);
              ComPtr<ICoreWebView2Deferral> deferral;
              if (FAILED(args->GetDeferral(&deferral))) {
                args->put_Cancel(TRUE);
                return S_OK;
              }
              const int request = next_request_++;
              deferrals_[request] = deferral;
              download_args_[request] = args;
              Send(id, "download",
                   {{flutter::EncodableValue("request"), flutter::EncodableValue(request)},
                    {flutter::EncodableValue("url"), flutter::EncodableValue(TakeString(raw_uri))},
                    {flutter::EncodableValue("path"), flutter::EncodableValue(TakeString(raw_path))},
                    {flutter::EncodableValue("size"), flutter::EncodableValue(static_cast<int64_t>(size))}});
              return S_OK;
            })
            .Get(),
        &token);
    tab.tokens.push_back({7, token});
  }

  webview->add_ContainsFullScreenElementChanged(
      Callback<ICoreWebView2ContainsFullScreenElementChangedEventHandler>(
          [this, id](ICoreWebView2* sender, IUnknown*) -> HRESULT {
            BOOL full = FALSE;
            sender->get_ContainsFullScreenElement(&full);
            Send(id, "fullscreen", {{flutter::EncodableValue("value"), flutter::EncodableValue(full == TRUE)}});
            return S_OK;
          })
          .Get(),
      &token);
  tab.tokens.push_back({8, token});

  webview->add_ProcessFailed(Callback<ICoreWebView2ProcessFailedEventHandler>(
                                 [this, id](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs*) -> HRESULT {
                                   Send(id, "crashed");
                                   return S_OK;
                                 })
                                 .Get(),
                             &token);
  tab.tokens.push_back({9, token});

  ComPtr<ICoreWebView2_8> webview8;
  if (SUCCEEDED(webview.As(&webview8))) {
    webview8->add_IsDocumentPlayingAudioChanged(
        Callback<ICoreWebView2IsDocumentPlayingAudioChangedEventHandler>(
            [this, id](ICoreWebView2* sender, IUnknown*) -> HRESULT {
              ComPtr<ICoreWebView2_8> w8;
              BOOL playing = FALSE;
              if (SUCCEEDED(sender->QueryInterface(IID_PPV_ARGS(&w8)))) w8->get_IsDocumentPlayingAudio(&playing);
              Send(id, "audio", {{flutter::EncodableValue("value"), flutter::EncodableValue(playing == TRUE)}});
              return S_OK;
            })
            .Get(),
        &token);
    tab.tokens.push_back({10, token});
  }

  // Browser shortcuts keep working while the page has the keyboard.
  tab.controller->add_AcceleratorKeyPressed(
      Callback<ICoreWebView2AcceleratorKeyPressedEventHandler>(
          [this, id](ICoreWebView2Controller*, ICoreWebView2AcceleratorKeyPressedEventArgs* args) -> HRESULT {
            COREWEBVIEW2_KEY_EVENT_KIND kind{};
            args->get_KeyEventKind(&kind);
            if (kind != COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN && kind != COREWEBVIEW2_KEY_EVENT_KIND_SYSTEM_KEY_DOWN) {
              return S_OK;
            }
            UINT key = 0;
            args->get_VirtualKey(&key);
            const bool ctrl = (::GetKeyState(VK_CONTROL) & 0x8000) != 0;
            const bool shift = (::GetKeyState(VK_SHIFT) & 0x8000) != 0;
            const bool alt = (::GetKeyState(VK_MENU) & 0x8000) != 0;
            std::string name;
            if (ctrl && key == 'T') name = "newTab";
            else if (ctrl && key == 'W') name = "closeTab";
            else if (ctrl && key == 'L') name = "address";
            else if (ctrl && key == VK_TAB) name = shift ? "prevTab" : "nextTab";
            else if (alt && key == VK_LEFT) name = "back";
            else if (alt && key == VK_RIGHT) name = "forward";
            if (name.empty()) return S_OK;
            args->put_Handled(TRUE);
            Send(id, "shortcut", {{flutter::EncodableValue("key"), flutter::EncodableValue(name)}});
            return S_OK;
          })
          .Get(),
      &tab.accelerator_token);
}

void BrowserWebPlugin::CloseTab(int id) {
  auto it = tabs_.find(id);
  if (it == tabs_.end()) return;
  BrowserTab& tab = *it->second;
  if (tab.webview) {
    ComPtr<ICoreWebView2_4> webview4;
    ComPtr<ICoreWebView2_8> webview8;
    tab.webview.As(&webview4);
    tab.webview.As(&webview8);
    for (const auto& [kind, token] : tab.tokens) {
      switch (kind) {
        case 0: tab.webview->remove_SourceChanged(token); break;
        case 1: tab.webview->remove_DocumentTitleChanged(token); break;
        case 2: tab.webview->remove_HistoryChanged(token); break;
        case 3: tab.webview->remove_NavigationStarting(token); break;
        case 4: tab.webview->remove_NavigationCompleted(token); break;
        case 5: tab.webview->remove_NewWindowRequested(token); break;
        case 6: tab.webview->remove_PermissionRequested(token); break;
        case 7: if (webview4) webview4->remove_DownloadStarting(token); break;
        case 8: tab.webview->remove_ContainsFullScreenElementChanged(token); break;
        case 9: tab.webview->remove_ProcessFailed(token); break;
        case 10: if (webview8) webview8->remove_IsDocumentPlayingAudioChanged(token); break;
        default: break;
      }
    }
  }
  if (tab.controller) {
    tab.controller->remove_AcceleratorKeyPressed(tab.accelerator_token);
    tab.controller->Close();
  }
  tab.webview.Reset();
  tab.controller.Reset();
  if (tab.host) ::DestroyWindow(tab.host);
  tabs_.erase(it);
}

void BrowserWebPlugin::DisposeAll() {
  ++generation_;
  initializing_ = false;
  auto pending = std::move(pending_inits_);
  pending_inits_.clear();
  for (auto& r : pending) r->Error("DISPOSED", "The browser was disposed");
  // Unanswered requests are denied.
  for (auto& [request, args] : permission_args_) args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
  for (auto& [request, args] : download_args_) args->put_Cancel(TRUE);
  for (auto& [request, deferral] : deferrals_) deferral->Complete();
  permission_args_.clear();
  download_args_.clear();
  deferrals_.clear();
  std::vector<int> ids;
  for (const auto& [id, tab] : tabs_) ids.push_back(id);
  for (int id : ids) CloseTab(id);
  environment_.Reset();
}

}  // namespace browser_web
