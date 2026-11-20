#pragma once

// Fork: native WebView2 tabs for the in-app browser. Hosted like the YouTube
// player and the mpv video: child windows of the Flutter view, laid out under
// the Flutter toolbar. Unlike the YouTube host these windows take mouse and
// keyboard input, since the page itself is what the user works with.
//
// One WebView2 environment with its own profile folder (separate from the
// YouTube sign-in), one controller per tab. Only the visible tab is shown;
// the Dart side suspends the others after a while.

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wrl.h>

#include <map>
#include <memory>
#include <string>
#include <vector>

#include "WebView2.h"

void BrowserWebPluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar);

namespace browser_web {

struct BrowserTab {
  int id = 0;
  HWND host = nullptr;
  Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller;
  Microsoft::WRL::ComPtr<ICoreWebView2> webview;
  std::vector<std::pair<int, EventRegistrationToken>> tokens;
  EventRegistrationToken accelerator_token{};
  // Hosts the user chose to open over plain http (no https upgrade).
  std::vector<std::wstring> http_hosts;
  // Last layout applied, so unchanged layouts don't touch the windows again.
  RECT placed{0, 0, 0, 0};
  bool shown = false;
  bool placed_once = false;
  // When this tab last opened a pop-up (GetTickCount64), for the tab-under check.
  ULONGLONG popup_at = 0;
  // The link the user last clicked in the top page, reported by kLinkScript.
  std::wstring last_link;
  ULONGLONG link_at = 0;
  bool in_private = false;
  // Id of the installed dark mode script, to remove it again.
  std::wstring dark_script_id;
};

class BrowserWebPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit BrowserWebPlugin(flutter::PluginRegistrarWindows* registrar);
  ~BrowserWebPlugin() override;

  BrowserWebPlugin(const BrowserWebPlugin&) = delete;
  BrowserWebPlugin& operator=(const BrowserWebPlugin&) = delete;

 private:
  using Result = std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;

  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call, Result result);
  void Initialize(const flutter::EncodableMap& args, Result result);
  void CreateTab(int id, const std::wstring& url, bool in_private, Result result);
  void ApplyTracking(BrowserTab& tab);
  void WatchDownload(int request);
  void SendDownload(int request, const char* state);
  void CloseTab(int id);
  void DisposeAll();
  void ApplyLayout();
  BrowserTab* Find(int id);
  void Send(int tab, const std::string& type, const flutter::EncodableMap& data = {});
  void SendState(BrowserTab& tab);
  void Wire(BrowserTab& tab);
  void OpenPopup(int id, const std::wstring& uri, bool allowed);
  void SendFavicon(int id);
  void InstallDarkScript(BrowserTab& tab);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  Microsoft::WRL::ComPtr<ICoreWebView2Environment> environment_;
  bool initializing_ = false;
  std::vector<Result> pending_inits_;
  std::map<int, std::unique_ptr<BrowserTab>> tabs_;
  int active_ = 0;
  bool visible_ = false;
  bool https_upgrade_ = true;
  // Sites (registrable domains) the user allowed to open pop-ups.
  std::vector<std::wstring> popup_sites_;
  // Tracking prevention: 0 off, 1 basic, 2 balanced, 3 strict.
  int tracking_level_ = 2;
  // Dark mode for websites (Dark Reader), run in every new page; empty = off.
  std::wstring dark_script_;
  int dark_generation_ = 0;

  // Downloads the user allowed, by request id, until they finish.
  struct Download {
    int tab = 0;
    Microsoft::WRL::ComPtr<ICoreWebView2DownloadOperation> operation;
    ULONGLONG last_report = 0;
  };
  std::map<int, Download> downloads_;
  std::map<int, Microsoft::WRL::ComPtr<ICoreWebView2DownloadOperation>> pending_downloads_;
  std::map<int, int> pending_download_tabs_;
  RECT rect_{0, 0, 0, 0};
  int generation_ = 0;

  // Permission and download requests waiting for the Dart side's answer.
  int next_request_ = 1;
  std::map<int, Microsoft::WRL::ComPtr<ICoreWebView2Deferral>> deferrals_;
  std::map<int, Microsoft::WRL::ComPtr<ICoreWebView2PermissionRequestedEventArgs>> permission_args_;
  std::map<int, Microsoft::WRL::ComPtr<ICoreWebView2DownloadStartingEventArgs>> download_args_;
};

}  // namespace browser_web
