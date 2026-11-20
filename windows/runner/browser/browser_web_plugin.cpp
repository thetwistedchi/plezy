#include "browser_web_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include <algorithm>
#include <cwctype>
#include <optional>
#include <thread>
#include <variant>

#include <shlwapi.h>

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

// The site of a host, roughly its registrable domain: "news.example.co.uk"
// and "example.co.uk" are one site, like the browser's same-site check.
std::wstring SiteOf(const std::wstring& host) {
  std::vector<std::wstring> labels;
  size_t start = 0;
  while (true) {
    const auto dot = host.find(L'.', start);
    labels.push_back(host.substr(start, dot == std::wstring::npos ? std::wstring::npos : dot - start));
    if (dot == std::wstring::npos) break;
    start = dot + 1;
  }
  if (labels.size() <= 2) return host;
  // Two-letter country endings with a short second level: co.uk, com.au.
  size_t keep = 2;
  const auto& last = labels[labels.size() - 1];
  const auto& second = labels[labels.size() - 2];
  if (last.size() == 2 && second.size() <= 3) keep = 3;
  if (labels.size() <= keep) return host;
  std::wstring site;
  for (size_t i = labels.size() - keep; i < labels.size(); ++i) {
    if (!site.empty()) site += L'.';
    site += labels[i];
  }
  return site;
}

// Reports the link the user clicked (or middle-clicked) in the top page to
// the app, so a new window can be told apart from a script's pop-up. It must
// not be asked for while the page waits on window.open (that deadlocks the
// page), so the page sends it on the click, before any script reacts.
constexpr wchar_t kLinkScript[] =
    L"(()=>{if(window.top!==window||!window.chrome||!chrome.webview)return;"
    // Keep the channel for this script, then take it away from the page, so
    // pages see a plain Edge rather than an embedded WebView2.
    L"const w=chrome.webview;try{delete chrome.webview;}catch(_){}"
    L"if(chrome.webview){try{Object.defineProperty(chrome,'webview',{value:undefined,configurable:true});}catch(_){}}"
    L"const r=e=>{const p=e.composedPath?e.composedPath():[];"
    L"const a=p.find(n=>n&&n.tagName==='A'&&n.href);"
    L"try{w.postMessage('plezy-link:'+(a?a.href:''));}catch(_){}};"
    L"addEventListener('click',r,true);addEventListener('auxclick',r,true);"
    // Ad blocking: report the page's class and id names, so the app can add
    // the generic hiding rules that apply to them. New names only, batched.
    L"const sc=new Set(),si=new Set();let pc=[],pi=[],tm=0;"
    L"const fl=()=>{tm=0;if(!pc.length&&!pi.length)return;"
    L"try{w.postMessage('plezy-cosm:'+JSON.stringify({c:pc,i:pi}));}catch(_){}pc=[];pi=[];};"
    L"const ad=e=>{if(sc.size>20000)return;const id=e.id;if(id&&typeof id==='string'&&!si.has(id)){si.add(id);pi.push(id);}"
    L"const cl=e.classList;if(cl)for(const c of cl)if(!sc.has(c)){sc.add(c);pc.push(c);}};"
    L"const sn=n=>{if(!n||n.nodeType!==1)return;ad(n);if(n.querySelectorAll)for(const e of n.querySelectorAll('[id],[class]'))ad(e);"
    L"if(!tm)tm=setTimeout(fl,120);};"
    L"const st=()=>{sn(document.documentElement);new MutationObserver(ms=>{for(const m of ms){"
    L"if(m.type==='attributes'){ad(m.target);if(!tm)tm=setTimeout(fl,120);}else for(const n of m.addedNodes)sn(n);}})"
    L".observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['class','id']});};"
    L"if(document.readyState==='loading')addEventListener('DOMContentLoaded',st,{once:true});else st();"
    L"})();";

constexpr wchar_t kLinkPrefix[] = L"plezy-link:";
constexpr wchar_t kCosmeticPrefix[] = L"plezy-cosm:";

// Adblock request types for WebView2's resource contexts.
const char* RequestTypeOf(COREWEBVIEW2_WEB_RESOURCE_CONTEXT context) {
  switch (context) {
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_DOCUMENT: return "sub_frame";
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_STYLESHEET: return "stylesheet";
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_IMAGE: return "image";
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_MEDIA: return "media";
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_TEXT_TRACK: return "media";
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_FONT: return "font";
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_SCRIPT: return "script";
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_XML_HTTP_REQUEST: return "xmlhttprequest";
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_FETCH: return "xmlhttprequest";
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_EVENT_SOURCE: return "xmlhttprequest";
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_WEBSOCKET: return "websocket";
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_PING: return "ping";
    case COREWEBVIEW2_WEB_RESOURCE_CONTEXT_CSP_VIOLATION_REPORT: return "csp_report";
    default: return "other";
  }
}

// Decodes standard base64; stops at the first character that isn't base64.
std::string DecodeBase64(const std::string& text) {
  static const std::string chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string out;
  int value = 0;
  int bits = -8;
  for (const char c : text) {
    if (c == '=') break;
    const auto pos = chars.find(c);
    if (pos == std::string::npos) continue;
    value = (value << 6) + static_cast<int>(pos);
    bits += 6;
    if (bits >= 0) {
      out.push_back(static_cast<char>((value >> bits) & 0xFF));
      bits -= 8;
    }
  }
  return out;
}

// Splits "data:<mime>;base64,<data>" into its type and bytes.
bool ParseDataUrl(const std::string& url, std::string& mime, std::string& body) {
  if (url.rfind("data:", 0) != 0) return false;
  const auto comma = url.find(',');
  if (comma == std::string::npos) return false;
  std::string meta = url.substr(5, comma - 5);
  const bool base64 = meta.size() >= 7 && meta.compare(meta.size() - 7, 7, ";base64") == 0;
  if (base64) meta = meta.substr(0, meta.size() - 7);
  mime = meta.empty() ? "text/plain" : meta;
  body = base64 ? DecodeBase64(url.substr(comma + 1)) : url.substr(comma + 1);
  return true;
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

  // Engines are built on a worker thread and handed over through the window.
  adblock_message_ = ::RegisterWindowMessageW(L"PlezyBrowserAdblockReady");
  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND, UINT message, WPARAM wparam, LPARAM lparam) -> std::optional<LRESULT> {
        if (adblock_message_ && message == adblock_message_) {
          auto* loaded = reinterpret_cast<std::pair<PlezyAdblock*, ULONGLONG>*>(lparam);
          OnAdblockLoaded(static_cast<int>(wparam), loaded->first, loaded->second);
          delete loaded;
          return 0;
        }
        return std::nullopt;
      });
}

BrowserWebPlugin::~BrowserWebPlugin() {
  if (window_proc_id_) registrar_->UnregisterTopLevelWindowProcDelegate(*window_proc_id_);
  DisposeAll();
  if (adblock_) plezy_adblock_free(adblock_);
  adblock_ = nullptr;
}

bool BrowserWebPlugin::AdblockActive(const std::string& page_url) const {
  if (!adblock_ || !adblock_enabled_) return false;
  const std::wstring site = SiteOf(HostOf(ToWide(page_url)));
  return std::find(adblock_off_sites_.begin(), adblock_off_sites_.end(), site) == adblock_off_sites_.end();
}

void BrowserWebPlugin::OnAdblockLoaded(int generation, PlezyAdblock* engine, ULONGLONG started) {
  if (generation != adblock_generation_) {
    if (engine) plezy_adblock_free(engine);
    return;
  }
  if (engine) {
    if (adblock_) plezy_adblock_free(adblock_);
    adblock_ = engine;
  }
  Send(0, "adblockReady",
       {{flutter::EncodableValue("ok"), flutter::EncodableValue(engine != nullptr)},
        {flutter::EncodableValue("ms"), flutter::EncodableValue(static_cast<int64_t>(::GetTickCount64() - started))}});
}

void BrowserWebPlugin::ReportBlocked(BrowserTab& tab, bool force) {
  const ULONGLONG now = ::GetTickCount64();
  if (!force && now - tab.blocked_report < 400) return;
  tab.blocked_report = now;
  Send(tab.id, "blocked", {{flutter::EncodableValue("count"), flutter::EncodableValue(tab.blocked)}});
}

// Sets up the next page of a tab: its hiding rules and scriptlets run at the
// start of each of its documents. Replaces the previous page's script.
void BrowserWebPlugin::PreparePage(BrowserTab& tab, const std::wstring& uri) {
  tab.page_url = ToUtf8(uri.c_str());
  tab.blocked = 0;
  tab.blocked_report = 0;
  tab.checked = 0;
  tab.check_ticks = 0;
  tab.cosmetic_exceptions = "[]";
  tab.generichide = false;
  if (!tab.webview) return;
  std::wstring js;
  if (AdblockActive(tab.page_url)) {
    char* exceptions = nullptr;
    int generichide = 0;
    char* script = plezy_adblock_page_script(adblock_, tab.page_url.c_str(), &exceptions, &generichide);
    if (exceptions) {
      tab.cosmetic_exceptions = exceptions;
      plezy_adblock_free_string(exceptions);
    }
    tab.generichide = generichide != 0;
    if (script) {
      js = ToWide(script);
      plezy_adblock_free_string(script);
    }
  }
  // Same site as before: the registered script stays and runs at the very
  // start of the new document, with no registration to wait for.
  if (js == tab.page_script_text && (!tab.page_script_id.empty() || tab.page_script_pending || js.empty())) return;
  ++tab.page_script_generation;
  if (!tab.page_script_id.empty()) {
    tab.webview->RemoveScriptToExecuteOnDocumentCreated(tab.page_script_id.c_str());
    tab.page_script_id.clear();
  }
  tab.page_script_text = js;
  tab.page_script_pending = false;
  if (js.empty()) return;
  tab.page_script_pending = true;
  const int id = tab.id;
  const int generation = tab.page_script_generation;
  tab.webview->AddScriptToExecuteOnDocumentCreated(
      js.c_str(), Callback<ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
                      [this, id, generation](HRESULT hr, LPCWSTR script_id) -> HRESULT {
                        BrowserTab* t = Find(id);
                        if (!t || !t->webview) return S_OK;
                        if (generation != t->page_script_generation) {
                          if (SUCCEEDED(hr) && script_id) t->webview->RemoveScriptToExecuteOnDocumentCreated(script_id);
                          return S_OK;
                        }
                        t->page_script_pending = false;
                        if (SUCCEEDED(hr) && script_id) t->page_script_id = script_id;
                        return S_OK;
                      })
                      .Get());
}

// Every request of a page passes here: blocked, replaced by a harmless stub
// (redirect filters), or let through.
void BrowserWebPlugin::OnResourceRequested(int id, ICoreWebView2WebResourceRequestedEventArgs* args) {
  BrowserTab* tab = Find(id);
  if (!tab || !environment_ || !AdblockActive(tab->page_url)) return;
  ComPtr<ICoreWebView2WebResourceRequest> request;
  if (FAILED(args->get_Request(&request)) || !request) return;
  LPWSTR raw = nullptr;
  request->get_Uri(&raw);
  const std::wstring uri = raw ? raw : L"";
  if (raw) ::CoTaskMemFree(raw);
  if (!StartsWith(Lower(uri), L"http")) return;
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT context = COREWEBVIEW2_WEB_RESOURCE_CONTEXT_OTHER;
  args->get_ResourceContext(&context);
  // The page itself was checked when its navigation started.
  if (context == COREWEBVIEW2_WEB_RESOURCE_CONTEXT_DOCUMENT && uri == tab->pending_nav) return;
  const std::string url = ToUtf8(uri.c_str());
  char* redirect = nullptr;
  LARGE_INTEGER before{};
  LARGE_INTEGER after{};
  ::QueryPerformanceCounter(&before);
  const int verdict = plezy_adblock_check(adblock_, url.c_str(), tab->page_url.c_str(), RequestTypeOf(context), &redirect);
  ::QueryPerformanceCounter(&after);
  ++tab->checked;
  tab->check_ticks += after.QuadPart - before.QuadPart;
  if (verdict == 0) return;
  ComPtr<ICoreWebView2WebResourceResponse> response;
  std::string mime;
  std::string body;
  if (verdict == 2 && redirect && ParseDataUrl(redirect, mime, body)) {
    ComPtr<IStream> stream;
    stream.Attach(::SHCreateMemStream(reinterpret_cast<const BYTE*>(body.data()), static_cast<UINT>(body.size())));
    const std::wstring headers = L"Content-Type: " + ToWide(mime) + L"\r\nAccess-Control-Allow-Origin: *";
    environment_->CreateWebResourceResponse(stream.Get(), 200, L"OK", headers.c_str(), &response);
  } else {
    environment_->CreateWebResourceResponse(nullptr, 403, L"Blocked", L"", &response);
  }
  if (redirect) plezy_adblock_free_string(redirect);
  if (response) args->put_Response(response.Get());
  ++tab->blocked;
  ReportBlocked(*tab, false);
}

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
    const bool moved = !tab->placed_once || !::EqualRect(&tab->placed, &rect_);
    // Hidden tabs are only hidden; they are placed when they are shown.
    if (!show) {
      if (tab->shown || !tab->placed_once) {
        if (tab->controller) tab->controller->put_IsVisible(FALSE);
        ::ShowWindow(tab->host, SW_HIDE);
        tab->shown = false;
        tab->placed_once = true;
      }
      continue;
    }
    if (moved) {
      ::SetWindowPos(tab->host, nullptr, rect_.left, rect_.top, width, height,
                     SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER);
      if (tab->controller) {
        RECT bounds{0, 0, width, height};
        tab->controller->put_Bounds(bounds);
        tab->controller->NotifyParentWindowPositionChanged();
      }
      tab->placed = rect_;
      tab->placed_once = true;
    }
    if (!tab->shown) {
      ::ShowWindow(tab->host, SW_SHOWNA);
      if (tab->controller) tab->controller->put_IsVisible(TRUE);
      tab->shown = true;
    }
    if (moved || !cutouts_.empty() || tab->has_region) ApplyRegion(*tab);
  }
}

void BrowserWebPlugin::ApplyRegion(BrowserTab& tab) {
  if (!tab.host) return;
  if (cutouts_.empty()) {
    if (tab.has_region) {
      ::SetWindowRgn(tab.host, nullptr, TRUE);
      tab.has_region = false;
    }
    return;
  }
  const int width = (std::max)(0, static_cast<int>(rect_.right - rect_.left));
  const int height = (std::max)(0, static_cast<int>(rect_.bottom - rect_.top));
  HRGN region = ::CreateRectRgn(0, 0, width, height);
  for (const Cutout& cutout : cutouts_) {
    const RECT& cut = cutout.rect;
    // Rounded like the popup, so no gap shows at its corners.
    HRGN hole = ::CreateRoundRectRgn(cut.left - rect_.left, cut.top - rect_.top, cut.right - rect_.left + 1,
                                     cut.bottom - rect_.top + 1, cutout.radius * 2, cutout.radius * 2);
    ::CombineRgn(region, region, hole, RGN_DIFF);
    ::DeleteObject(hole);
  }
  // The window owns the region from here on.
  if (::SetWindowRgn(tab.host, region, TRUE)) {
    tab.has_region = true;
  } else {
    ::DeleteObject(region);
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
  if (method == "setCutouts") {
    cutouts_.clear();
    const auto it = args.find(flutter::EncodableValue("rects"));
    if (it != args.end() && std::holds_alternative<flutter::EncodableList>(it->second)) {
      const auto& list = std::get<flutter::EncodableList>(it->second);
      auto num = [](const flutter::EncodableValue& v) -> LONG {
        if (std::holds_alternative<int32_t>(v)) return std::get<int32_t>(v);
        if (std::holds_alternative<int64_t>(v)) return static_cast<LONG>(std::get<int64_t>(v));
        if (std::holds_alternative<double>(v)) return static_cast<LONG>(std::get<double>(v));
        return 0;
      };
      // left, top, right, bottom, corner radius
      for (size_t i = 0; i + 4 < list.size(); i += 5) {
        cutouts_.push_back(Cutout{RECT{num(list[i]), num(list[i + 1]), num(list[i + 2]), num(list[i + 3])},
                                  static_cast<int>(num(list[i + 4]))});
      }
    }
    for (auto& [tab_id, tab] : tabs_) {
      if (tab->shown || tab->has_region) ApplyRegion(*tab);
    }
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
  if (method == "setPopupSites") {
    popup_sites_.clear();
    const auto it = args.find(flutter::EncodableValue("sites"));
    if (it != args.end() && std::holds_alternative<flutter::EncodableList>(it->second)) {
      for (const auto& v : std::get<flutter::EncodableList>(it->second)) {
        if (std::holds_alternative<std::string>(v)) popup_sites_.push_back(Lower(ToWide(std::get<std::string>(v))));
      }
    }
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
        // Where the user chose to save it (the download folder setting or
        // "save as"); empty keeps WebView2's default path.
        const std::wstring path = ToWide(GetString(args, "path").value_or(""));
        if (allow && !path.empty()) it->second->put_ResultFilePath(path.c_str());
        it->second->put_Cancel(allow ? FALSE : TRUE);
        // The app lists downloads itself: no Edge download flyout.
        it->second->put_Handled(TRUE);
        download_args_.erase(it);
      }
      auto op = pending_downloads_.find(request);
      if (op != pending_downloads_.end()) {
        if (allow) downloads_[request] = Download{pending_download_tabs_[request], op->second, 0};
        pending_downloads_.erase(op);
        pending_download_tabs_.erase(request);
      }
    }
    auto deferral = deferrals_.find(request);
    if (deferral != deferrals_.end()) {
      deferral->second->Complete();
      deferrals_.erase(deferral);
    }
    if (method == "answerDownload" && allow) WatchDownload(request);
    result->Success();
    return;
  }
  if (method == "cancelDownload" || method == "pauseDownload" || method == "resumeDownload") {
    auto it = downloads_.find(GetInt(args, "download"));
    if (it != downloads_.end() && it->second.operation) {
      if (method == "cancelDownload") it->second.operation->Cancel();
      if (method == "pauseDownload") it->second.operation->Pause();
      if (method == "resumeDownload") it->second.operation->Resume();
    }
    result->Success();
    return;
  }
  if (method == "adblockLoad") {
    // Built on a worker thread; the result comes back through the window.
    const std::string config = GetString(args, "config").value_or("{}");
    const int generation = ++adblock_generation_;
    const HWND window = ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
    const UINT message = adblock_message_;
    const ULONGLONG started = ::GetTickCount64();
    std::thread([config, generation, window, message, started]() {
      PlezyAdblock* engine = plezy_adblock_load(config.c_str());
      auto* loaded = new std::pair<PlezyAdblock*, ULONGLONG>(engine, started);
      if (!::PostMessageW(window, message, static_cast<WPARAM>(generation), reinterpret_cast<LPARAM>(loaded))) {
        if (engine) plezy_adblock_free(engine);
        delete loaded;
      }
    }).detach();
    result->Success();
    return;
  }
  if (method == "adblockSetEnabled") {
    adblock_enabled_ = GetBool(args, "value", true);
    result->Success();
    return;
  }
  if (method == "adblockSetOffSites") {
    adblock_off_sites_.clear();
    const auto it = args.find(flutter::EncodableValue("sites"));
    if (it != args.end() && std::holds_alternative<flutter::EncodableList>(it->second)) {
      for (const auto& v : std::get<flutter::EncodableList>(it->second)) {
        if (std::holds_alternative<std::string>(v)) adblock_off_sites_.push_back(Lower(ToWide(std::get<std::string>(v))));
      }
    }
    result->Success();
    return;
  }
  if (method == "setDarkScript") {
    dark_script_ = ToWide(GetString(args, "script").value_or(""));
    ++dark_generation_;
    for (auto& [tab_id, tab] : tabs_) {
      InstallDarkScript(*tab);
      if (!tab->webview) continue;
      // Open pages change right away; the script itself undoes an earlier run.
      if (dark_script_.empty()) {
        tab->webview->ExecuteScript(L"try{window.__plezyDark&&window.__plezyDark.disable();}catch(e){}", nullptr);
      } else {
        tab->webview->ExecuteScript(dark_script_.c_str(), nullptr);
      }
    }
    result->Success();
    return;
  }
  if (method == "setTrackingPrevention") {
    tracking_level_ = GetInt(args, "level");
    for (auto& [tab_id, tab] : tabs_) ApplyTracking(*tab);
    result->Success();
    return;
  }

  const int id = GetInt(args, "id");
  if (method == "createTab") {
    CreateTab(id, ToWide(GetString(args, "url").value_or("")), GetBool(args, "private", false), std::move(result));
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
  } else if (method == "proceedBlocked") {
    const std::wstring url = ToWide(GetString(args, "url").value_or(""));
    const std::wstring host = HostOf(url);
    if (!host.empty()) tab->allowed_hosts.push_back(host);
    tab->webview->Navigate(url.c_str());
    result->Success();
  } else if (method == "setMuted") {
    ComPtr<ICoreWebView2_8> webview8;
    if (SUCCEEDED(tab->webview.As(&webview8))) webview8->put_IsMuted(GetBool(args, "value", false) ? TRUE : FALSE);
    result->Success();
  } else if (method == "suspend") {
    ComPtr<ICoreWebView2_3> webview3;
    if (SUCCEEDED(tab->webview.As(&webview3))) {
      if (tab->controller) tab->controller->put_IsVisible(FALSE);
      tab->shown = false;
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
  tracking_level_ = GetInt(args, "tracking");
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
  const std::wstring arguments = ToWide(GetString(args, "arguments").value_or(""));
  if (!arguments.empty()) options->put_AdditionalBrowserArguments(arguments.c_str());
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

void BrowserWebPlugin::CreateTab(int id, const std::wstring& url, bool in_private, Result result) {
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
  tab->in_private = in_private;
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
  auto handler = Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
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
          // Only the link reports of kLinkScript; nothing goes to the page.
          settings->put_IsWebMessageEnabled(TRUE);
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
          // SmartScreen stays on.
          ComPtr<ICoreWebView2Settings8> settings8;
          if (SUCCEEDED(settings.As(&settings8))) settings8->put_IsReputationCheckingRequired(TRUE);
        }
        ApplyTracking(*tab);
        Wire(*tab);
        InstallDarkScript(*tab);
        // The host may have been placed before the WebView existed.
        tab->placed_once = false;
        tab->shown = false;
        ApplyLayout();
        if (!url.empty()) tab->webview->Navigate(url.c_str());
        shared->Success(flutter::EncodableValue(true));
        return S_OK;
      });

  // Private tabs share one InPrivate profile: nothing of them is kept after
  // the last private tab closes.
  HRESULT hr = E_FAIL;
  ComPtr<ICoreWebView2Environment10> environment10;
  ComPtr<ICoreWebView2ControllerOptions> options;
  if (in_private && SUCCEEDED(environment_.As(&environment10)) &&
      SUCCEEDED(environment10->CreateCoreWebView2ControllerOptions(&options)) && options) {
    options->put_IsInPrivateModeEnabled(TRUE);
    options->put_ProfileName(L"Private");
    hr = environment10->CreateCoreWebView2ControllerWithOptions(raw->host, options.Get(), handler.Get());
  } else if (!in_private) {
    hr = environment_->CreateCoreWebView2Controller(raw->host, handler.Get());
  }
  if (FAILED(hr)) {
    CloseTab(id);
    shared->Error("CREATE_FAILED", "WebView2 controller could not start");
  }
}

void BrowserWebPlugin::ApplyTracking(BrowserTab& tab) {
  if (!tab.webview) return;
  ComPtr<ICoreWebView2_13> webview13;
  ComPtr<ICoreWebView2Profile> profile;
  ComPtr<ICoreWebView2Profile3> profile3;
  if (SUCCEEDED(tab.webview.As(&webview13)) && SUCCEEDED(webview13->get_Profile(&profile)) && profile &&
      SUCCEEDED(profile.As(&profile3))) {
    const COREWEBVIEW2_TRACKING_PREVENTION_LEVEL levels[] = {
        COREWEBVIEW2_TRACKING_PREVENTION_LEVEL_NONE, COREWEBVIEW2_TRACKING_PREVENTION_LEVEL_BASIC,
        COREWEBVIEW2_TRACKING_PREVENTION_LEVEL_BALANCED, COREWEBVIEW2_TRACKING_PREVENTION_LEVEL_STRICT};
    profile3->put_PreferredTrackingPreventionLevel(levels[(std::min)(3, (std::max)(0, tracking_level_))]);
  }
}

void BrowserWebPlugin::InstallDarkScript(BrowserTab& tab) {
  if (!tab.webview) return;
  if (!tab.dark_script_id.empty()) {
    tab.webview->RemoveScriptToExecuteOnDocumentCreated(tab.dark_script_id.c_str());
    tab.dark_script_id.clear();
  }
  if (dark_script_.empty()) return;
  const int id = tab.id;
  const int generation = dark_generation_;
  tab.webview->AddScriptToExecuteOnDocumentCreated(
      dark_script_.c_str(),
      Callback<ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
          [this, id, generation](HRESULT hr, LPCWSTR script_id) -> HRESULT {
            BrowserTab* t = Find(id);
            if (!t || !t->webview || FAILED(hr) || !script_id) return S_OK;
            // Replaced again meanwhile: this one is stale.
            if (generation != dark_generation_) {
              t->webview->RemoveScriptToExecuteOnDocumentCreated(script_id);
              return S_OK;
            }
            t->dark_script_id = script_id;
            return S_OK;
          })
          .Get());
}

void BrowserWebPlugin::SendFavicon(int id) {
  BrowserTab* tab = Find(id);
  if (!tab || !tab->webview) return;
  ComPtr<ICoreWebView2_15> webview15;
  if (FAILED(tab->webview.As(&webview15))) return;
  webview15->GetFavicon(
      COREWEBVIEW2_FAVICON_IMAGE_FORMAT_PNG,
      Callback<ICoreWebView2GetFaviconCompletedHandler>([this, id](HRESULT hr, IStream* stream) -> HRESULT {
        std::vector<uint8_t> bytes;
        if (SUCCEEDED(hr) && stream) {
          uint8_t buffer[4096];
          ULONG read = 0;
          while (SUCCEEDED(stream->Read(buffer, sizeof(buffer), &read)) && read > 0) {
            bytes.insert(bytes.end(), buffer, buffer + read);
            if (bytes.size() > 512 * 1024) break;
          }
        }
        Send(id, "favicon", {{flutter::EncodableValue("data"), flutter::EncodableValue(bytes)}});
        return S_OK;
      }).Get());
}

void BrowserWebPlugin::SendDownload(int request, const char* state) {
  auto it = downloads_.find(request);
  if (it == downloads_.end() || !it->second.operation) return;
  auto& op = it->second.operation;
  INT64 received = 0;
  INT64 total = 0;
  LPWSTR path = nullptr;
  LPWSTR uri = nullptr;
  COREWEBVIEW2_DOWNLOAD_INTERRUPT_REASON reason = COREWEBVIEW2_DOWNLOAD_INTERRUPT_REASON_NONE;
  op->get_BytesReceived(&received);
  op->get_TotalBytesToReceive(&total);
  op->get_ResultFilePath(&path);
  op->get_Uri(&uri);
  op->get_InterruptReason(&reason);
  Send(it->second.tab, "downloadState",
       {{flutter::EncodableValue("download"), flutter::EncodableValue(request)},
        {flutter::EncodableValue("state"), flutter::EncodableValue(std::string(state))},
        {flutter::EncodableValue("received"), flutter::EncodableValue(static_cast<int64_t>(received))},
        {flutter::EncodableValue("total"), flutter::EncodableValue(static_cast<int64_t>(total))},
        {flutter::EncodableValue("path"), flutter::EncodableValue(TakeString(path))},
        {flutter::EncodableValue("url"), flutter::EncodableValue(TakeString(uri))},
        {flutter::EncodableValue("reason"), flutter::EncodableValue(static_cast<int>(reason))}});
}

void BrowserWebPlugin::WatchDownload(int request) {
  auto it = downloads_.find(request);
  if (it == downloads_.end()) return;
  auto op = it->second.operation;
  EventRegistrationToken token{};
  op->add_BytesReceivedChanged(
      Callback<ICoreWebView2BytesReceivedChangedEventHandler>(
          [this, request](ICoreWebView2DownloadOperation*, IUnknown*) -> HRESULT {
            auto d = downloads_.find(request);
            if (d == downloads_.end()) return S_OK;
            COREWEBVIEW2_DOWNLOAD_STATE state = COREWEBVIEW2_DOWNLOAD_STATE_IN_PROGRESS;
            if (d->second.operation) d->second.operation->get_State(&state);
            if (state == COREWEBVIEW2_DOWNLOAD_STATE_COMPLETED) {
              SendDownload(request, "completed");
              downloads_.erase(d);
              return S_OK;
            }
            // At most twice a second.
            const ULONGLONG now = ::GetTickCount64();
            if (now - d->second.last_report < 500) return S_OK;
            d->second.last_report = now;
            SendDownload(request, "running");
            return S_OK;
          })
          .Get(),
      &token);
  op->add_StateChanged(
      Callback<ICoreWebView2StateChangedEventHandler>(
          [this, request](ICoreWebView2DownloadOperation* sender, IUnknown*) -> HRESULT {
            COREWEBVIEW2_DOWNLOAD_STATE state = COREWEBVIEW2_DOWNLOAD_STATE_IN_PROGRESS;
            sender->get_State(&state);
            if (state == COREWEBVIEW2_DOWNLOAD_STATE_COMPLETED) {
              SendDownload(request, "completed");
              downloads_.erase(request);
            } else if (state == COREWEBVIEW2_DOWNLOAD_STATE_INTERRUPTED) {
              BOOL resumable = FALSE;
              sender->get_CanResume(&resumable);
              SendDownload(request, resumable ? "paused" : "failed");
              if (!resumable) downloads_.erase(request);
            } else {
              SendDownload(request, "running");
            }
            return S_OK;
          })
          .Get(),
      &token);
  SendDownload(request, "running");
}

void BrowserWebPlugin::OpenPopup(int id, const std::wstring& uri, bool) {
  if (auto* tab = Find(id)) tab->popup_at = ::GetTickCount64();
  Send(id, "openTab", {{flutter::EncodableValue("url"), flutter::EncodableValue(ToUtf8(uri.c_str()))}});
}

void BrowserWebPlugin::Wire(BrowserTab& tab) {
  const int id = tab.id;
  auto& webview = tab.webview;
  EventRegistrationToken token{};
  webview->AddScriptToExecuteOnDocumentCreated(kLinkScript, nullptr);

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
            // Tab-under: right after opening a pop-up, the page itself moves to
            // another site without a click. Blocked like in Chrome.
            if (tab && tab->popup_at && ::GetTickCount64() - tab->popup_at < 10000) {
              BOOL user = FALSE;
              BOOL redirect = FALSE;
              args->get_IsUserInitiated(&user);
              args->get_IsRedirected(&redirect);
              LPWSTR current = nullptr;
              sender->get_Source(&current);
              const std::wstring from = current ? current : L"";
              if (current) ::CoTaskMemFree(current);
              const std::wstring site = SiteOf(HostOf(uri));
              const bool allowed =
                  std::find(popup_sites_.begin(), popup_sites_.end(), SiteOf(HostOf(from))) != popup_sites_.end();
              if (!user && !redirect && !allowed && !site.empty() && site != SiteOf(HostOf(from))) {
                args->put_Cancel(TRUE);
                Send(id, "popupBlocked",
                     {{flutter::EncodableValue("url"), flutter::EncodableValue(ToUtf8(uri.c_str()))},
                      {flutter::EncodableValue("site"), flutter::EncodableValue(ToUtf8(SiteOf(HostOf(from)).c_str()))},
                      {flutter::EncodableValue("redirect"), flutter::EncodableValue(true)}});
                return S_OK;
              }
            }
            if (tab) {
              // Pages on a filter list (malware, trackers, ad servers) are not
              // opened; the app shows a warning with a way to continue.
              const std::string page = ToUtf8(uri.c_str());
              const std::wstring host = HostOf(uri);
              const bool let_through =
                  std::find(tab->allowed_hosts.begin(), tab->allowed_hosts.end(), host) != tab->allowed_hosts.end();
              if (!let_through && AdblockActive(page) &&
                  plezy_adblock_check(adblock_, page.c_str(), page.c_str(), "main_frame", nullptr) != 0) {
                args->put_Cancel(TRUE);
                Send(id, "pageBlocked", {{flutter::EncodableValue("url"), flutter::EncodableValue(page)}});
                return S_OK;
              }
              tab->pending_nav = uri;
              PreparePage(*tab, uri);
              ReportBlocked(*tab, true);
            }
            Send(id, "loading", {{flutter::EncodableValue("url"), flutter::EncodableValue(ToUtf8(uri.c_str()))}});
            return S_OK;
          })
          .Get(),
      &token);
  tab.tokens.push_back({3, token});

  // A fast page can start before its script finished registering: then the
  // script runs right away instead, a moment late but still before most of
  // the page's own scripts.
  webview->add_ContentLoading(Callback<ICoreWebView2ContentLoadingEventHandler>(
                                  [this, id](ICoreWebView2* sender, ICoreWebView2ContentLoadingEventArgs*) -> HRESULT {
                                    BrowserTab* t = Find(id);
                                    if (t && t->page_script_pending && !t->page_script_text.empty()) {
                                      sender->ExecuteScript(t->page_script_text.c_str(), nullptr);
                                    }
                                    return S_OK;
                                  })
                                  .Get(),
                              &token);
  tab.tokens.push_back({14, token});

  webview->add_NavigationCompleted(
      Callback<ICoreWebView2NavigationCompletedEventHandler>(
          [this, id](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
            BOOL success = FALSE;
            COREWEBVIEW2_WEB_ERROR_STATUS status = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
            args->get_IsSuccess(&success);
            args->get_WebErrorStatus(&status);
            if (auto* t = Find(id)) {
              ReportBlocked(*t, true);
              if (t->checked > 0) {
                LARGE_INTEGER frequency{};
                ::QueryPerformanceFrequency(&frequency);
                const double ms = frequency.QuadPart ? 1000.0 * t->check_ticks / frequency.QuadPart : 0;
                Send(id, "adblockStats",
                     {{flutter::EncodableValue("checked"), flutter::EncodableValue(t->checked)},
                      {flutter::EncodableValue("blocked"), flutter::EncodableValue(t->blocked)},
                      {flutter::EncodableValue("ms"), flutter::EncodableValue(ms)}});
              }
            }
            Send(id, "loaded",
                 {{flutter::EncodableValue("ok"), flutter::EncodableValue(success == TRUE)},
                  {flutter::EncodableValue("error"), flutter::EncodableValue(static_cast<int>(status))}});
            if (auto* t = Find(id)) SendState(*t);
            return S_OK;
          })
          .Get(),
      &token);
  tab.tokens.push_back({4, token});

  // Pop-up blocker, along the lines of Chrome's: a new window opens (as a
  // tab) only after a click, and then only for the clicked link or a page of
  // the same site. Scripts opening other sites on a click (the usual ad
  // pop-up) are blocked with a notice, unless the user allowed the site.
  webview->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [this, id](ICoreWebView2* sender, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
            args->put_Handled(TRUE);
            LPWSTR raw = nullptr;
            args->get_Uri(&raw);
            const std::wstring uri = raw ? raw : L"";
            if (raw) ::CoTaskMemFree(raw);
            BOOL user = FALSE;
            args->get_IsUserInitiated(&user);
            LPWSTR current = nullptr;
            sender->get_Source(&current);
            const std::wstring opener = current ? current : L"";
            if (current) ::CoTaskMemFree(current);
            const std::wstring opener_site = SiteOf(HostOf(opener));
            const bool site_allowed =
                std::find(popup_sites_.begin(), popup_sites_.end(), opener_site) != popup_sites_.end();
            if (site_allowed) {
              OpenPopup(id, uri, true);
              return S_OK;
            }
            if (!user) {
              Send(id, "popupBlocked",
                   {{flutter::EncodableValue("url"), flutter::EncodableValue(ToUtf8(uri.c_str()))},
                    {flutter::EncodableValue("site"), flutter::EncodableValue(ToUtf8(opener_site.c_str()))}});
              return S_OK;
            }
            const std::wstring target_site = SiteOf(HostOf(uri));
            if (!target_site.empty() && target_site == opener_site) {
              OpenPopup(id, uri, true);
              return S_OK;
            }
            // Another site: open it only if it is the link the user clicked.
            auto trim = [](std::wstring u) {
              while (!u.empty() && u.back() == L'/') u.pop_back();
              return u;
            };
            BrowserTab* t = Find(id);
            const bool clicked_link = t && !t->last_link.empty() && ::GetTickCount64() - t->link_at < 3000 &&
                                      trim(t->last_link) == trim(uri);
            if (clicked_link) {
              t->last_link.clear();
              OpenPopup(id, uri, true);
            } else {
              Send(id, "popupBlocked",
                   {{flutter::EncodableValue("url"), flutter::EncodableValue(ToUtf8(uri.c_str()))},
                    {flutter::EncodableValue("site"), flutter::EncodableValue(ToUtf8(opener_site.c_str()))}});
            }
            return S_OK;
          })
          .Get(),
      &token);
  tab.tokens.push_back({5, token});

  webview->add_WebMessageReceived(
      Callback<ICoreWebView2WebMessageReceivedEventHandler>(
          [this, id](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
            LPWSTR raw = nullptr;
            if (FAILED(args->TryGetWebMessageAsString(&raw)) || !raw) return S_OK;
            const std::wstring message = raw;
            ::CoTaskMemFree(raw);
            if (StartsWith(message, kCosmeticPrefix) && message.size() < 512 * 1024) {
              BrowserTab* t = Find(id);
              if (!t || t->generichide || !t->webview || !AdblockActive(t->page_url)) return S_OK;
              const std::string query = ToUtf8(message.substr(wcslen(kCosmeticPrefix)).c_str());
              char* script = plezy_adblock_generic_script(adblock_, query.c_str(), t->cosmetic_exceptions.c_str());
              if (script) {
                t->webview->ExecuteScript(ToWide(script).c_str(), nullptr);
                plezy_adblock_free_string(script);
              }
              return S_OK;
            }
            const std::wstring prefix = kLinkPrefix;
            if (message.size() > 4096 || !StartsWith(message, prefix)) return S_OK;
            if (auto* t = Find(id)) {
              t->last_link = message.substr(prefix.size());
              t->link_at = ::GetTickCount64();
            }
            return S_OK;
          })
          .Get(),
      &token);
  tab.tokens.push_back({11, token});

  // Ad blocking sees every request of the page, its frames and its workers.
  ComPtr<ICoreWebView2_22> webview22;
  if (SUCCEEDED(webview.As(&webview22))) {
    webview22->AddWebResourceRequestedFilterWithRequestSourceKinds(
        L"*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL, COREWEBVIEW2_WEB_RESOURCE_REQUEST_SOURCE_KINDS_ALL);
  } else {
    webview->AddWebResourceRequestedFilter(L"*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
  }
  webview->add_WebResourceRequested(
      Callback<ICoreWebView2WebResourceRequestedEventHandler>(
          [this, id](ICoreWebView2*, ICoreWebView2WebResourceRequestedEventArgs* args) -> HRESULT {
            OnResourceRequested(id, args);
            return S_OK;
          })
          .Get(),
      &token);
  tab.tokens.push_back({13, token});

  ComPtr<ICoreWebView2_15> webview15;
  if (SUCCEEDED(webview.As(&webview15))) {
    webview15->add_FaviconChanged(Callback<ICoreWebView2FaviconChangedEventHandler>(
                                      [this, id](ICoreWebView2*, IUnknown*) -> HRESULT {
                                        SendFavicon(id);
                                        return S_OK;
                                      })
                                      .Get(),
                                  &token);
    tab.tokens.push_back({12, token});
  }

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
              if (operation) {
                pending_downloads_[request] = operation;
                pending_download_tabs_[request] = id;
              }
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
                                 [this, id](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs* args) -> HRESULT {
                                   COREWEBVIEW2_PROCESS_FAILED_KIND kind{};
                                   args->get_ProcessFailedKind(&kind);
                                   int reason = -1;
                                   int exit_code = 0;
                                   ComPtr<ICoreWebView2ProcessFailedEventArgs2> args2;
                                   if (SUCCEEDED(args->QueryInterface(IID_PPV_ARGS(&args2)))) {
                                     COREWEBVIEW2_PROCESS_FAILED_REASON r{};
                                     args2->get_Reason(&r);
                                     reason = static_cast<int>(r);
                                     args2->get_ExitCode(&exit_code);
                                   }
                                   Send(id, "crashed",
                                        {{flutter::EncodableValue("kind"), flutter::EncodableValue(static_cast<int>(kind))},
                                         {flutter::EncodableValue("reason"), flutter::EncodableValue(reason)},
                                         {flutter::EncodableValue("exitCode"), flutter::EncodableValue(exit_code)}});
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

  // A click into the page closes Flutter popups lying over it.
  tab.controller->add_GotFocus(Callback<ICoreWebView2FocusChangedEventHandler>(
                                   [this, id](ICoreWebView2Controller*, IUnknown*) -> HRESULT {
                                     Send(id, "pageFocus");
                                     return S_OK;
                                   })
                                   .Get(),
                               &tab.focus_token);

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
            if (ctrl && shift && key == 'T') name = "reopenTab";
            else if (ctrl && shift && key == 'N') name = "newPrivateTab";
            else if (ctrl && key == 'T') name = "newTab";
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
    ComPtr<ICoreWebView2_15> webview15;
    tab.webview.As(&webview4);
    tab.webview.As(&webview8);
    tab.webview.As(&webview15);
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
        case 11: tab.webview->remove_WebMessageReceived(token); break;
        case 12: if (webview15) webview15->remove_FaviconChanged(token); break;
        case 13: tab.webview->remove_WebResourceRequested(token); break;
        case 14: tab.webview->remove_ContentLoading(token); break;
        default: break;
      }
    }
  }
  if (tab.controller) {
    tab.controller->remove_AcceleratorKeyPressed(tab.accelerator_token);
    tab.controller->remove_GotFocus(tab.focus_token);
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
  pending_downloads_.clear();
  pending_download_tabs_.clear();
  downloads_.clear();
  deferrals_.clear();
  std::vector<int> ids;
  for (const auto& [id, tab] : tabs_) ids.push_back(id);
  for (int id : ids) CloseTab(id);
  environment_.Reset();
}

}  // namespace browser_web
