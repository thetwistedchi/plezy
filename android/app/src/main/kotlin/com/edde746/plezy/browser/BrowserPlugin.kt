package com.edde746.plezy.browser

import android.annotation.SuppressLint
import android.app.Activity
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Base64
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.GeolocationPermissions
import android.webkit.JavascriptInterface
import android.webkit.PermissionRequest
import android.webkit.RenderProcessGoneDetail
import android.webkit.URLUtil
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.webkit.ProfileStore
import androidx.webkit.ScriptHandler
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.edde746.plezy.TvDetection
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Collections
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONObject

/**
 * The in-app browser on Android: the same channel as the Windows runner's
 * browser (windows/runner/browser), with Android's WebView for the tabs and
 * the same adblock-rust engine. The active tab shows in [BrowserPageView],
 * a platform view the Dart page places like the Windows page rect.
 */
class BrowserPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
  companion object {
    // Plex Web's play/pause button: its centre in view pixels, "hidden"
    // while the controls are hidden, or "none".
    private const val PLEX_PAUSED = "(()=>{const v=document.querySelector('video');return v?v.paused:null;})()"
    private const val PLEX_BUTTON = "(()=>{const q=s=>document.querySelector(s);" +
      "const b=q('[data-testid=\"pauseButton\"]')||q('[data-testid=\"resumeButton\"]')||" +
      "q('button[aria-label=\"Pause\"]')||q('button[aria-label=\"Pausieren\"]')||q('button[aria-label=\"Play\"]')||q('button[aria-label=\"Wiedergabe\"]');" +
      "if(!b)return 'hidden none';const r=b.getBoundingClientRect();const st=getComputedStyle(b);let o=1;for(let e=b;e;e=e.parentElement)o*=+getComputedStyle(e).opacity;" +
      "if(r.width<2||r.height<2||st.visibility==='hidden'||o<0.2||r.bottom<0||r.top>innerHeight)return 'hidden';" +
      "const d=devicePixelRatio;return Math.round((r.left+r.width/2)*d)+','+Math.round((r.top+r.height/2)*d);})()"

    private const val TAG = "PlezyBrowser"
    private const val CHANNEL = "com.plezy.retrowave/browser"
    const val VIEW_TYPE = "plezy/browser_page"
    const val PLAYER_VIEW_TYPE = "plezy/plex_player"
    private const val PLAYER_TAB = -1
    private const val PRIVATE_PROFILE = "Private"
    private const val BRIDGE = "plezyBridge"

    /** Link clicks and class/id names, reported from the top page (see the Windows kLinkScript). */
    private val LINK_SCRIPT = """(()=>{if(window.top!==window)return;const w=window.$BRIDGE;if(!w)return;
try{delete window.$BRIDGE;}catch(_){}
const r=e=>{const p=e.composedPath?e.composedPath():[];const a=p.find(n=>n&&n.tagName==='A'&&n.href);
try{w.postMessage('plezy-link:'+(a?a.href:''));}catch(_){}};
addEventListener('click',r,true);addEventListener('auxclick',r,true);
const sc=new Set(),si=new Set();let pc=[],pi=[],tm=0;
const fl=()=>{tm=0;if(!pc.length&&!pi.length)return;try{w.postMessage('plezy-cosm:'+JSON.stringify({c:pc,i:pi}));}catch(_){}pc=[];pi=[];};
const ad=e=>{if(sc.size>20000)return;const id=e.id;if(id&&typeof id==='string'&&!si.has(id)){si.add(id);pi.push(id);}
const cl=e.classList;if(cl)for(const c of cl)if(!sc.has(c)){sc.add(c);pc.push(c);}};
const sn=n=>{if(!n||n.nodeType!==1)return;ad(n);if(n.querySelectorAll)for(const e of n.querySelectorAll('[id],[class]'))ad(e);if(!tm)tm=setTimeout(fl,120);};
const st=()=>{sn(document.documentElement);new MutationObserver(ms=>{for(const m of ms){
if(m.type==='attributes'){ad(m.target);if(!tm)tm=setTimeout(fl,120);}else for(const n of m.addedNodes)sn(n);}})
.observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['class','id']});};
if(document.readyState==='loading')addEventListener('DOMContentLoaded',st,{once:true});else st();})();"""

    private val ALL_ORIGINS = setOf("*")

    /**
     * In every frame: reports whether the frame plays sound
     * ('plezy-audio:1/0') and mutes its media on the app's message, passed
     * on to its own frames (embedded players included).
     */
    private val MEDIA_SCRIPT = """(()=>{const w=window.$BRIDGE;let muted=false,last=-1;
const media=()=>Array.from(document.querySelectorAll('video,audio'));
const report=()=>{const on=media().some(m=>!m.paused&&!m.ended&&!m.muted&&m.volume>0)?1:0;
if(on!==last){last=on;try{w&&w.postMessage('plezy-audio:'+on);}catch(_){}}};
const apply=()=>{for(const m of media())m.muted=muted;};
const pass=d=>{for(const f of document.querySelectorAll('iframe')){try{f.contentWindow.postMessage(d,'*');}catch(_){}}};
addEventListener('message',e=>{const d=e.data;if(!d)return;
if(typeof d.plezyMute==='boolean'){muted=d.plezyMute;apply();pass(d);report();return;}
if(typeof d.plezyMedia!=='string')return;pass(d);
const vs=media().filter(m=>m.tagName==='VIDEO'||!m.paused);if(!vs.length)return;
const v=vs.find(m=>!m.paused)||vs.sort((a,b)=>b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight)[0];
if(d.plezyMedia==='toggle'){if(v.paused)v.play().catch(()=>{});else v.pause();}
else if(d.plezyMedia==='play')v.play().catch(()=>{});else if(d.plezyMedia==='pause')v.pause();
else if(d.plezyMedia==='seek'&&isFinite(v.duration))v.currentTime=Math.max(0,Math.min(v.duration,v.currentTime+(d.by||0)));});
for(const t of ['play','playing','pause','ended','volumechange','emptied'])
document.addEventListener(t,e=>{if(muted&&t!=='volumechange'&&e.target&&'muted' in e.target)e.target.muted=true;report();},true);})();"""

    @Volatile private var instance: BrowserPlugin? = null

    /**
     * The remote's media keys (and, in a video's fullscreen, OK and the
     * arrows) for the video on screen: in a page's fullscreen, the Plex
     * player page, or the browser page with the focus. Null when they are
     * not the browser's.
     */
    @JvmStatic
    fun dispatchMedia(event: android.view.KeyEvent): Boolean? = instance?.mediaKey(event)

    /** The page view on screen, for [dispatchToPage]. */
    @Volatile private var shownPage: BrowserPageView? = null

    /**
     * The activity's key dispatch: while the browser page has the focus, the
     * D-pad and OK go straight to it. Null for every other key or state.
     */
    @JvmStatic
    fun dispatchToPage(event: android.view.KeyEvent): Boolean? {
      val page = shownPage ?: return null
      if (!page.isAttachedToWindow) return null
      // Up three times quickly from the page: the address bar. Counted here
      // so presses still count when the first one left the page.
      // The page is focused in Flutter: its keys go straight to it. Through
      // Flutter they could arrive before the page had the focus and be lost.
      val onPage = page.hasFocus() || page.flutterFocused
      if (page.tripleUp(event, onPage)) return true
      if (!onPage) return null
      if (!page.hasFocus()) page.requestFocus()
      return when (event.keyCode) {
        android.view.KeyEvent.KEYCODE_DPAD_UP, android.view.KeyEvent.KEYCODE_DPAD_DOWN,
        android.view.KeyEvent.KEYCODE_DPAD_LEFT, android.view.KeyEvent.KEYCODE_DPAD_RIGHT,
        android.view.KeyEvent.KEYCODE_DPAD_CENTER, android.view.KeyEvent.KEYCODE_ENTER,
        android.view.KeyEvent.KEYCODE_NUMPAD_ENTER, android.view.KeyEvent.KEYCODE_BUTTON_A,
        -> page.handleRemoteKey(event)
        else -> null
      }
    }
  }

  private class Tab(val id: Int, val private: Boolean) {
    var webView: WebView? = null
    var lastUrl: String = ""
    @Volatile var pageUrl: String = ""
    val blocked = AtomicInteger()
    val checked = AtomicInteger()
    @Volatile var blockedReport = 0L
    var checkNanos = 0L
    @Volatile var cosmeticExceptions = "[]"
    @Volatile var generichide = false
    var pageScript: ScriptHandler? = null
    var pageScriptText: String? = null
    var preparedFor: String? = null
    var darkScript: ScriptHandler? = null
    val allowedHosts: MutableSet<String> = Collections.newSetFromMap(ConcurrentHashMap())
    val httpHosts = mutableSetOf<String>()
    var lastLink = ""
    var linkAt = 0L
    var popupAt = 0L
    var error: Int? = null
    var muted = false
    var suspended = false
    var autoplayFor: String? = null
    val audioFrames = mutableSetOf<Int>()
    var crashed = false
    var privacyScript: ScriptHandler? = null
  }

  private class PendingDownload(
    val tab: Int, val url: String, val userAgent: String, val mime: String?, val name: String, val referer: String,
  )

  private lateinit var appContext: Context
  private var activity: Activity? = null
  private var channel: MethodChannel? = null
  private var events: EventChannel.EventSink? = null
  private val main = Handler(Looper.getMainLooper())

  private val tabs = HashMap<Int, Tab>()
  private var activeId = 0
  private var visible = false
  private var page: BrowserPageView? = null
  private var tv = false

  private var httpsUpgrade = true
  private var tracking = 2
  private var popupSites = emptySet<String>()
  private var darkScript = ""

  @Volatile private var adblock = 0L
  @Volatile private var adblockEnabled = true
  @Volatile private var adblockOffSites = emptySet<String>()
  private var adblockGeneration = 0

  private var nextRequest = 1
  private val pendingDownloads = HashMap<Int, PendingDownload>()
  private val downloads = HashMap<Int, Pair<Int, Long>>() // request -> (tab, DownloadManager id)
  private var polling = false
  private val finished = HashMap<String, Long>() // path -> DownloadManager id

  @Volatile private var remoteState = JSONObject()
  private val remoteTouch = RemoteTouch { activity }
  private val remote by lazy {
    PhoneRemoteServer(appContext, { events -> main.post { onRemote(events) } }, { remoteState })
  }

  private var fullscreenView: View? = null
  private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null
  private var fullscreenTab = 0

  // ---------------------------------------------------------------- plugin

  /**
   * Requests a site makes from its service worker skip the tabs'
   * shouldInterceptRequest: checked here, against the page that asked
   * (Referer) or else the request's own site.
   */
  private fun installServiceWorkerBlocking() {
    try {
      android.webkit.ServiceWorkerController.getInstance().setServiceWorkerClient(object : android.webkit.ServiceWorkerClient() {
        override fun shouldInterceptRequest(request: WebResourceRequest): WebResourceResponse? {
          val url = request.url.toString()
          val engine = adblock
          if (engine == 0L || !url.startsWith("http")) return null
          val source = request.requestHeaders.entries.firstOrNull { it.key.equals("Referer", true) }?.value ?: url
          if (!adblockActive(source)) return null
          val verdict = AdblockEngine.check(engine, url, source, requestType(request)) ?: return null
          return if (verdict.isEmpty()) blockedResponse() else dataResponse(verdict) ?: blockedResponse()
        }
      })
    } catch (e: Throwable) {
      Log.d(TAG, "service worker blocking unavailable: $e")
    }
  }

  /**
   * When Android runs low on memory, background tabs that play nothing give
   * up their WebView (about 50-150 MB each); they load their page again
   * when shown (their back history is lost).
   */
  private val memoryCallbacks = object : android.content.ComponentCallbacks2 {
    override fun onTrimMemory(level: Int) {
      if (level < android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) return
      main.post { discardBackgroundTabs() }
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {}

    @Deprecated("Deprecated in Java")
    override fun onLowMemory() {
      main.post { discardBackgroundTabs() }
    }
  }

  private fun discardBackgroundTabs() {
    var count = 0
    for (tab in tabs.values) {
      if (tab.id == activeId && visible) continue
      val web = tab.webView ?: continue
      if (tab.audioFrames.isNotEmpty() || tab.id == fullscreenTab) continue
      (web.parent as? ViewGroup)?.removeView(web)
      web.stopLoading()
      web.destroy()
      tab.webView = null
      tab.pageScript = null
      tab.pageScriptText = null
      tab.preparedFor = null
      tab.darkScript = null
      count++
    }
    if (count > 0) Log.i(TAG, "Low memory: $count background tabs released")
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    instance = this
    appContext = binding.applicationContext
    appContext.registerComponentCallbacks(memoryCallbacks)
    tv = TvDetection.isTv(appContext)
    channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    EventChannel(binding.binaryMessenger, "$CHANNEL/events").setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
      }

      override fun onCancel(arguments: Any?) {
        events = null
      }
    })
    binding.platformViewRegistry.registerViewFactory(VIEW_TYPE, object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
      override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        BrowserPageView(activity ?: context, this@BrowserPlugin, tv)
    })
    binding.platformViewRegistry.registerViewFactory(PLAYER_VIEW_TYPE, object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
      override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        createPlayerView(
          activity ?: context,
          (args as? Map<*, *>)?.get("url") as? String ?: "",
          (args as? Map<*, *>)?.get("plexToken") as? String ?: "",
        )
    })
  }

  /**
   * Free on plex.tv's player page: Plex Web alone, without the browser
   * around it. Its own WebView (not one of the tabs), with the same
   * protection, the automatic consent answer and autoplay; it goes when
   * the page closes.
   */
  private fun createPlayerView(context: Context, url: String, plexToken: String): PlatformView {
    val tab = Tab(PLAYER_TAB, false)
    val container = FrameLayout(context).apply { setBackgroundColor(Color.BLACK) }
    val web = createWebView(tab)
    container.addView(web, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    if (plexToken.isNotEmpty() && url.isNotEmpty() && WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
      // Plex Web signed in with the app's Plex account: it keeps the account
      // (with its token) in local storage, which is filled in before the
      // page starts. Only for app.plex.tv.
      Thread {
        val user = try {
          val c = java.net.URL("https://plex.tv/api/v2/user").openConnection() as java.net.HttpURLConnection
          c.setRequestProperty("Accept", "application/json")
          c.setRequestProperty("X-Plex-Token", plexToken)
          c.setRequestProperty("X-Plex-Product", "Plezy Retrowave")
          c.connectTimeout = 5000
          c.readTimeout = 5000
          if (c.responseCode == 200) org.json.JSONObject(c.inputStream.bufferedReader().readText()) else null
        } catch (e: Exception) {
          Log.w(TAG, "Free on plex.tv: Plex account not read", e)
          null
        }
        main.post {
          if (tab.autoplayFor == "closed") return@post
          if (user != null) {
            if (!user.has("authToken")) user.put("authToken", plexToken)
            val users = org.json.JSONObject().put("users", org.json.JSONArray().put(user)).toString()
            WebViewCompat.addDocumentStartJavaScript(
              web,
              "(()=>{try{const s=localStorage;const t=${org.json.JSONObject.quote(plexToken)};" +
                "if(s.getItem('myPlexAccessToken')!==t||!s.getItem('users')){s.setItem('myPlexAccessToken',t);s.setItem('users',${org.json.JSONObject.quote(users)});}" +
                "}catch(_){}})()",
              setOf("https://app.plex.tv"),
            )
            Log.i(TAG, "Free on plex.tv: Plex Web gets the app's account (${user.optString("username")})")
          }
          load(tab, url)
          main.postDelayed({
            if (tab.autoplayFor == "closed") return@postDelayed
            web.evaluateJavascript(
              "(()=>{try{return location.host+location.hash.slice(0,40)+' token:'+!!localStorage.getItem('myPlexAccessToken')+' users:'+!!localStorage.getItem('users');}catch(e){return ''+e;}})()",
            ) { Log.i(TAG, "Free on plex.tv: Plex Web state $it") }
          }, 8000)
        }
      }.start()
    } else if (url.isNotEmpty()) {
      load(tab, url)
    }
    main.postDelayed({ web.requestFocus() }, 300)
    playerTab = tab
    return object : PlatformView {
      override fun getView(): View = container

      override fun dispose() {
        if (fullscreenTab == PLAYER_TAB) exitFullscreen()
        if (playerTab === tab) playerTab = null
        tab.autoplayFor = "closed"
        container.removeView(web)
        web.stopLoading()
        web.destroy()
        tab.webView = null
      }
    }
  }

  private var playerTab: Tab? = null

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    appContext.unregisterComponentCallbacks(memoryCallbacks)
    if (instance === this) instance = null
    channel?.setMethodCallHandler(null)
    channel = null
    disposeAll()
  }

  private var activityBinding: ActivityPluginBinding? = null

  // Websites' file pickers (<input type=file>): the system's picker.
  private var fileCallback: android.webkit.ValueCallback<Array<Uri>>? = null
  private val fileRequest = 0x50E7

  private val resultListener = io.flutter.plugin.common.PluginRegistry.ActivityResultListener { requestCode, resultCode, data ->
    if (requestCode != fileRequest) return@ActivityResultListener false
    val callback = fileCallback
    fileCallback = null
    callback?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data))
    true
  }

  private fun bindActivity(binding: ActivityPluginBinding) {
    activityBinding?.removeActivityResultListener(resultListener)
    activityBinding = binding
    activity = binding.activity
    binding.addActivityResultListener(resultListener)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    bindActivity(binding)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    bindActivity(binding)
  }

  override fun onDetachedFromActivity() {
    exitFullscreen()
    activityBinding?.removeActivityResultListener(resultListener)
    activityBinding = null
    activity = null
  }

  private fun send(tab: Int, type: String, data: Map<String, Any?> = emptyMap()) {
    val event = HashMap<String, Any?>(data)
    event["type"] = type
    event["tab"] = tab
    if (Looper.myLooper() == Looper.getMainLooper()) {
      events?.success(event)
    } else {
      main.post { events?.success(event) }
    }
  }

  // ------------------------------------------------------------- page view

  private var pointer = false

  internal fun attachPage(view: BrowserPageView) {
    page = view
    shownPage = view
    view.pointerMode = pointer
    applyLayout()
    // Asked for before the platform view existed (a new tab's first page).
    if (focusPending) {
      focusPending = false
      main.post { if (page === view) view.focusPage() }
    }
  }

  private var focusPending = false

  internal fun detachPage(view: BrowserPageView) {
    if (page === view) page = null
    if (shownPage === view) shownPage = null
  }

  internal fun onPageTouched() = send(0, "pageFocus")

  /** Up three times quickly on the page: the keys go to the address bar. */
  internal fun onFocusAddress(view: BrowserPageView) {
    view.flutterFocused = false
    view.returnFocusToFlutter()
    send(0, "focusAddress")
  }

  /** Holding OK on the page: Dart switches the pointer for the site. */
  internal fun onTogglePointer() = send(0, "togglePointer")

  internal fun onLeavePage(view: BrowserPageView) {
    view.flutterFocused = false
    view.returnFocusToFlutter()
    send(0, "leavePage")
  }

  private fun applyLayout() {
    val tab = tabs[activeId]
    // A tab released for memory comes back with its page when shown.
    if (visible && tab != null && tab.webView == null && !tab.suspended && !tab.crashed && tab.lastUrl.isNotEmpty()) {
      try {
        createWebView(tab)
        load(tab, tab.lastUrl)
        if (tab.muted) applyMute(tab)
      } catch (e: Exception) {
        Log.w(TAG, "tab reload failed", e)
      }
    }
    val web = if (visible && tab != null && !tab.suspended) tab.webView else null
    page?.show(web)
  }

  // ------------------------------------------------------------ helpers

  private fun hostOf(url: String): String = try {
    Uri.parse(url).host?.lowercase(Locale.ROOT) ?: ""
  } catch (_: Exception) {
    ""
  }

  /** Roughly the registrable domain, like the Windows SiteOf. */
  private fun siteOf(host: String): String {
    val labels = host.split('.')
    if (labels.size <= 2) return host
    val keep = if (labels.last().length == 2 && labels[labels.size - 2].length <= 3) 3 else 2
    if (labels.size <= keep) return host
    return labels.takeLast(keep).joinToString(".")
  }

  private fun isLocalHost(host: String): Boolean {
    if (host.isEmpty() || host == "localhost" || host.startsWith("[")) return true
    if (!host.contains('.')) return true
    if (host.endsWith(".local") || host.endsWith(".lan") || host.endsWith(".home.arpa")) return true
    val parts = host.split('.').mapNotNull { it.toIntOrNull() }
    if (parts.size == 4) {
      val (a, b) = parts
      return a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && b in 16..31) ||
        (a == 169 && b == 254) || (a == 100 && b in 64..127)
    }
    return false
  }

  private fun adblockActive(pageUrl: String): Boolean {
    if (adblock == 0L || !adblockEnabled || pageUrl.isEmpty()) return false
    return siteOf(hostOf(pageUrl)) !in adblockOffSites
  }

  /** Adblock request type from what Android tells about a request. */
  private fun requestType(request: WebResourceRequest): String {
    // Chromium's own label, when the headers carry it.
    when (request.requestHeaders.entries.firstOrNull { it.key.equals("Sec-Fetch-Dest", true) }?.value?.lowercase(Locale.ROOT)) {
      "script", "serviceworker", "sharedworker", "worker" -> return "script"
      "style" -> return "stylesheet"
      "image" -> return "image"
      "font" -> return "font"
      "audio", "video", "track" -> return "media"
      "iframe", "frame" -> return "sub_frame"
      "empty" -> return "xmlhttprequest"
    }
    val accept = request.requestHeaders["Accept"]?.lowercase(Locale.ROOT) ?: ""
    val path = request.url.path?.lowercase(Locale.ROOT) ?: ""
    return when {
      accept.startsWith("text/html") -> "sub_frame"
      accept.startsWith("text/css") || path.endsWith(".css") -> "stylesheet"
      accept.startsWith("image/") || path.endsWith(".png") || path.endsWith(".jpg") || path.endsWith(".jpeg") ||
        path.endsWith(".gif") || path.endsWith(".webp") || path.endsWith(".svg") || path.endsWith(".ico") -> "image"
      path.endsWith(".js") || path.endsWith(".mjs") -> "script"
      path.endsWith(".woff") || path.endsWith(".woff2") || path.endsWith(".ttf") || path.endsWith(".otf") -> "font"
      path.endsWith(".mp4") || path.endsWith(".webm") || path.endsWith(".m3u8") || path.endsWith(".mp3") -> "media"
      request.requestHeaders["X-Requested-With"] == "XMLHttpRequest" -> "xmlhttprequest"
      accept.contains("application/json") -> "xmlhttprequest"
      else -> "other"
    }
  }

  private fun dataResponse(url: String): WebResourceResponse? {
    if (!url.startsWith("data:")) return null
    val comma = url.indexOf(',')
    if (comma < 0) return null
    var meta = url.substring(5, comma)
    val base64 = meta.endsWith(";base64")
    if (base64) meta = meta.removeSuffix(";base64")
    val data = url.substring(comma + 1)
    val bytes = if (base64) Base64.decode(data, Base64.DEFAULT) else Uri.decode(data).toByteArray()
    return WebResourceResponse(
      meta.ifEmpty { "text/plain" }, "utf-8", 200, "OK",
      mapOf("Access-Control-Allow-Origin" to "*"), ByteArrayInputStream(bytes),
    )
  }

  private fun blockedResponse() =
    WebResourceResponse("text/plain", "utf-8", 403, "Blocked", emptyMap(), ByteArrayInputStream(ByteArray(0)))

  private fun reportBlocked(tab: Tab, force: Boolean) {
    val now = System.currentTimeMillis()
    if (!force && now - tab.blockedReport < 400) return
    tab.blockedReport = now
    send(tab.id, "blocked", mapOf("count" to tab.blocked.get()))
  }

  private fun sendState(tab: Tab) {
    val web = tab.webView ?: return
    val url = web.url ?: ""
    if (url.isNotEmpty() && url != "about:blank") tab.lastUrl = url
    if (tab.id == activeId) remoteState = JSONObject().put("url", url).put("title", web.title ?: "")
    send(
      tab.id, "state",
      mapOf("url" to url, "title" to (web.title ?: ""), "canGoBack" to web.canGoBack(), "canGoForward" to web.canGoForward()),
    )
  }

  // ------------------------------------------------------- page scripts

  private val documentStart get() = WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)

  /** The next page's hiding rules and scriptlets; replaces the last page's. */
  private fun preparePage(tab: Tab, url: String, runNow: Boolean) {
    val web = tab.webView ?: return
    tab.pageUrl = url
    tab.preparedFor = siteOf(hostOf(url))
    tab.blocked.set(0)
    tab.checked.set(0)
    tab.checkNanos = 0
    tab.cosmeticExceptions = "[]"
    tab.generichide = false
    var script: String? = null
    if (adblockActive(url)) {
      AdblockEngine.pageScript(adblock, url)?.let { json ->
        try {
          val o = JSONObject(json)
          script = if (o.isNull("script")) null else o.getString("script")
          tab.cosmeticExceptions = o.optString("exceptions", "[]")
          tab.generichide = o.optBoolean("generichide", false)
        } catch (_: Exception) {
        }
      }
    }
    if (script == tab.pageScriptText && (tab.pageScript != null || script == null)) {
      if (runNow && script != null) web.evaluateJavascript(script!!, null)
      return
    }
    tab.pageScript?.remove()
    tab.pageScript = null
    tab.pageScriptText = script
    val js = script ?: return
    if (documentStart) {
      try {
        tab.pageScript = WebViewCompat.addDocumentStartJavaScript(web, js, ALL_ORIGINS)
      } catch (e: Exception) {
        Log.d(TAG, "page script: $e")
      }
    }
    if (runNow || !documentStart) web.evaluateJavascript(js, null)
  }

  /**
   * Tracking prevention at Balanced and Strict, beyond blocking third-party
   * cookies: pages are told not to track and not to sell or share data
   * (Global Privacy Control), as far as a page can read it.
   */
  private fun installPrivacyScript(tab: Tab) {
    val web = tab.webView ?: return
    tab.privacyScript?.remove()
    tab.privacyScript = null
    if (tracking < 2 || !documentStart) return
    try {
      tab.privacyScript = WebViewCompat.addDocumentStartJavaScript(
        web,
        "(()=>{try{Object.defineProperty(Navigator.prototype,'globalPrivacyControl',{get:()=>true,configurable:true});" +
          "Object.defineProperty(Navigator.prototype,'doNotTrack',{get:()=>'1',configurable:true});}catch(_){}})();",
        ALL_ORIGINS,
      )
    } catch (e: Exception) {
      Log.d(TAG, "privacy script: $e")
    }
  }

  private fun installDarkScript(tab: Tab) {
    val web = tab.webView ?: return
    tab.darkScript?.remove()
    tab.darkScript = null
    if (darkScript.isEmpty() || !documentStart) return
    try {
      tab.darkScript = WebViewCompat.addDocumentStartJavaScript(web, darkScript, ALL_ORIGINS)
    } catch (e: Exception) {
      Log.d(TAG, "dark script: $e")
    }
  }

  /** Mutes or unmutes the tab's media, in every frame (see MEDIA_SCRIPT). */
  private fun applyMute(tab: Tab) {
    val muted = if (tab.muted) "true" else "false"
    tab.webView?.evaluateJavascript("window.postMessage({plezyMute:$muted},'*');", null)
  }

  /** A frame started or stopped playing sound; the tab is audible while any frame is. */
  private fun onAudio(tab: Tab, frame: Int, playing: Boolean) {
    val was = tab.audioFrames.isNotEmpty()
    if (playing) tab.audioFrames.add(frame) else tab.audioFrames.remove(frame)
    val now = tab.audioFrames.isNotEmpty()
    if (was != now) send(tab.id, "audio", mapOf("value" to now))
  }

  private fun onBridgeMessage(tab: Tab, message: String) {
    if (message.startsWith("plezy-cosm:") && message.length < 512 * 1024) {
      if (tab.generichide || !adblockActive(tab.pageUrl)) return
      val script = AdblockEngine.genericScript(adblock, message.removePrefix("plezy-cosm:"), tab.cosmeticExceptions)
      if (script != null) tab.webView?.evaluateJavascript(script, null)
      return
    }
    if (message.length > 4096 || !message.startsWith("plezy-link:")) return
    tab.lastLink = message.removePrefix("plezy-link:")
    tab.linkAt = System.currentTimeMillis()
  }

  // ------------------------------------------------------------ WebView

  @SuppressLint("SetJavaScriptEnabled", "JavascriptInterface", "RequiresFeature")
  private fun createWebView(tab: Tab): WebView {
    val web = WebView(activity ?: appContext)
    if (tab.private && WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
      ProfileStore.getInstance().getOrCreateProfile(PRIVATE_PROFILE)
      WebViewCompat.setProfile(web, PRIVATE_PROFILE)
    }
    web.setBackgroundColor(Color.WHITE)
    with(web.settings) {
      javaScriptEnabled = true
      domStorageEnabled = true
      // Getting the focus back (the remote) must not select the page's first
      // element and scroll back up to it.
      setNeedInitialFocus(false)
      @Suppress("DEPRECATION")
      databaseEnabled = true
      setSupportMultipleWindows(true)
      javaScriptCanOpenWindowsAutomatically = true
      builtInZoomControls = true
      displayZoomControls = false
      useWideViewPort = true
      loadWithOverviewMode = true
      allowFileAccess = false
      allowContentAccess = false
      setGeolocationEnabled(false)
      mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
      mediaPlaybackRequiresUserGesture = true
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) safeBrowsingEnabled = true
      // Pages see Chrome, not an embedded WebView.
      userAgentString = userAgentString.replace("; wv)", ")").replace(Regex("Version/\\d+\\.\\d+ "), "")
      if (tab.private) cacheMode = WebSettings.LOAD_NO_CACHE
    }
    CookieManager.getInstance().setAcceptThirdPartyCookies(web, tracking < 2)

    if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
      WebViewCompat.addWebMessageListener(web, BRIDGE, ALL_ORIGINS) { _, message, _, isMainFrame, reply ->
        val data = message.data ?: return@addWebMessageListener
        if (data.startsWith("plezy-audio:")) {
          onAudio(tab, reply.hashCode(), data.endsWith("1"))
        } else if (isMainFrame) {
          onBridgeMessage(tab, data)
        }
      }
    } else {
      web.addJavascriptInterface(object {
        @JavascriptInterface
        fun postMessage(message: String) {
          main.post { onBridgeMessage(tab, message) }
        }
      }, BRIDGE)
    }
    if (documentStart) {
      try {
        // Before the link script, which hides the bridge from the page.
        WebViewCompat.addDocumentStartJavaScript(web, MEDIA_SCRIPT, ALL_ORIGINS)
      } catch (e: Exception) {
        Log.d(TAG, "media script: $e")
      }
      try {
        WebViewCompat.addDocumentStartJavaScript(web, LINK_SCRIPT, ALL_ORIGINS)
      } catch (e: Exception) {
        Log.d(TAG, "link script: $e")
      }
    }

    web.webViewClient = object : WebViewClient() {
      override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
        if (!request.isForMainFrame) return false
        val url = request.url.toString()
        val lower = url.lowercase(Locale.ROOT)
        if (lower.startsWith("file:") || lower.startsWith("javascript:") || lower.startsWith("content:")) {
          send(tab.id, "blockedScheme", mapOf("url" to url))
          return true
        }
        if (!lower.startsWith("http:") && !lower.startsWith("https:") && !lower.startsWith("about:") &&
          !lower.startsWith("data:") && !lower.startsWith("blob:")
        ) {
          // Links to apps (intent:, market:, mailto:): the fallback page
          // for intent: links, nothing for the others.
          if (lower.startsWith("intent:")) {
            Regex("S\\.browser_fallback_url=([^;]+)").find(url)?.groupValues?.get(1)?.let {
              view.loadUrl(Uri.decode(it))
            }
          }
          return true
        }
        if (httpsUpgrade && lower.startsWith("http://")) {
          val host = hostOf(url)
          if (!isLocalHost(host) && host !in tab.httpHosts) {
            view.loadUrl("https://" + url.substring(7))
            send(tab.id, "upgraded", mapOf("url" to url))
            return true
          }
        }
        // Tab-under: right after opening a pop-up, the page moves to another
        // site without a click.
        if (tab.popupAt != 0L && System.currentTimeMillis() - tab.popupAt < 10_000) {
          val from = view.url ?: ""
          val fromSite = siteOf(hostOf(from))
          val site = siteOf(hostOf(url))
          if (!request.hasGesture() && !request.isRedirect && fromSite !in popupSites && site.isNotEmpty() &&
            site != fromSite
          ) {
            send(tab.id, "popupBlocked", mapOf("url" to url, "site" to fromSite, "redirect" to true))
            return true
          }
        }
        preparePage(tab, url, runNow = false)
        return false
      }

      override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
        val url = request.url.toString()
        if (!url.startsWith("http")) return null
        val engine = adblock
        if (request.isForMainFrame) {
          tab.pageUrl = url
          if (engine == 0L || !adblockActive(url) || hostOf(url) in tab.allowedHosts) return null
          // Pages on a filter list are kept closed; the app shows a warning.
          if (AdblockEngine.check(engine, url, url, "main_frame") != null) {
            main.post {
              tab.webView?.stopLoading()
              send(tab.id, "pageBlocked", mapOf("url" to url))
            }
            return blockedResponse()
          }
          return null
        }
        val pageUrl = tab.pageUrl
        if (!adblockActive(pageUrl)) return null
        val started = System.nanoTime()
        val verdict = AdblockEngine.check(engine, url, pageUrl, requestType(request))
        tab.checkNanos += System.nanoTime() - started
        tab.checked.incrementAndGet()
        verdict ?: return null
        tab.blocked.incrementAndGet()
        val now = System.currentTimeMillis()
        if (now - tab.blockedReport >= 400) main.post { reportBlocked(tab, false) }
        return if (verdict.isEmpty()) blockedResponse() else dataResponse(verdict) ?: blockedResponse()
      }

      override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
        tab.error = null
        if (tab.audioFrames.isNotEmpty()) {
          tab.audioFrames.clear()
          send(tab.id, "audio", mapOf("value" to false))
        }
        if (pageFullscreenTab == tab.id) exitFullscreen()
        // Back, forward and reloads skip shouldOverrideUrlLoading.
        if (url.startsWith("http") && tab.preparedFor != siteOf(hostOf(url))) preparePage(tab, url, runNow = true)
        else tab.pageUrl = url
        reportBlocked(tab, true)
        send(tab.id, "loading", mapOf("url" to url))
        sendState(tab)
        if (tab.muted) applyMute(tab)
      }

      override fun onPageFinished(view: WebView, url: String) {
        reportBlocked(tab, true)
        val checked = tab.checked.get()
        if (checked > 0) {
          send(
            tab.id, "adblockStats",
            mapOf("checked" to checked, "blocked" to tab.blocked.get(), "ms" to tab.checkNanos / 1_000_000.0),
          )
        }
        val error = tab.error
        send(tab.id, "loaded", mapOf("ok" to (error == null), "error" to (error ?: 0)))
        sendState(tab)
        if (tab.muted) applyMute(tab)
        maybeAutoplayPlex(tab, url)
      }

      override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
        if (request.isForMainFrame) tab.error = error.errorCode
      }

      override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
        sendState(tab)
        maybeAutoplayPlex(tab, url)
      }

      override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
        // The WebView can't be used again: the tab gets a new one on reload.
        Log.w(TAG, "Tab ${tab.id}: render process gone (crash=${detail.didCrash()})")
        if (page != null && tabs[activeId] === tab) page?.show(null)
        (view.parent as? ViewGroup)?.removeView(view)
        view.destroy()
        if (tab.webView === view) tab.webView = null
        tab.crashed = true
        send(tab.id, "crashed", mapOf("kind" to 1, "reason" to (if (detail.didCrash()) 1 else 0), "exitCode" to 0))
        return true
      }
    }

    web.webChromeClient = object : WebChromeClient() {
      override fun onReceivedTitle(view: WebView, title: String?) = sendState(tab)

      override fun onReceivedIcon(view: WebView, icon: Bitmap?) {
        if (icon == null) return
        val out = ByteArrayOutputStream()
        icon.compress(Bitmap.CompressFormat.PNG, 100, out)
        send(tab.id, "favicon", mapOf("data" to out.toByteArray()))
      }

      override fun onCreateWindow(view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message): Boolean {
        // The address of the new window only shows once it starts loading:
        // a throwaway WebView catches it.
        val catcher = WebView(activity ?: appContext)
        if (tab.private && WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
          try {
            WebViewCompat.setProfile(catcher, PRIVATE_PROFILE)
          } catch (_: Exception) {
          }
        }
        var done = false
        val opener = view.url ?: ""
        fun take(url: String) {
          if (done) return
          done = true
          main.post { catcher.destroy() }
          onNewWindow(tab, url, opener, isUserGesture)
        }
        catcher.webViewClient = object : WebViewClient() {
          override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest): Boolean {
            take(request.url.toString())
            return true
          }

          override fun onPageStarted(v: WebView, url: String, favicon: Bitmap?) {
            if (url != "about:blank") take(url)
            v.stopLoading()
          }
        }
        val transport = resultMsg.obj as? WebView.WebViewTransport ?: return false
        transport.webView = catcher
        resultMsg.sendToTarget()
        return true
      }

      override fun onShowCustomView(view: View, callback: CustomViewCallback) {
        enterFullscreen(tab.id, view, callback)
      }

      override fun onHideCustomView() {
        exitFullscreen()
      }

      // No camera, microphone or location for websites in this app; copy
      // protected video (Widevine, e.g. Plex's free service) may play.
      override fun onShowFileChooser(
        view: WebView,
        callback: android.webkit.ValueCallback<Array<Uri>>,
        params: FileChooserParams,
      ): Boolean {
        val activity = activity ?: return false
        fileCallback?.onReceiveValue(null)
        fileCallback = callback
        return try {
          activity.startActivityForResult(params.createIntent(), fileRequest)
          true
        } catch (e: ActivityNotFoundException) {
          fileCallback = null
          Log.d(TAG, "no file picker: $e")
          false
        }
      }

      override fun onPermissionRequest(request: PermissionRequest) {
        val drm = request.resources.filter { it == PermissionRequest.RESOURCE_PROTECTED_MEDIA_ID }
        if (drm.isNotEmpty()) request.grant(drm.toTypedArray()) else request.deny()
      }

      override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) =
        callback.invoke(origin, false, false)
    }

    web.setDownloadListener { url, userAgent, contentDisposition, mime, length ->
      val request = nextRequest++
      val name = URLUtil.guessFileName(url, contentDisposition, mime)
      pendingDownloads[request] = PendingDownload(tab.id, url, userAgent, mime, name, web.url ?: "")
      send(tab.id, "download", mapOf("request" to request, "url" to url, "path" to name, "size" to length))
    }

    web.setOnFocusChangeListener { _, focused -> if (focused) send(0, "pageFocus") }
    tab.webView = web
    installPrivacyScript(tab)
    installDarkScript(tab)
    return web
  }

  /**
   * Free on plex.tv: a title's Plex Web page opened from the app starts
   * playing by itself. The Play button is pressed with a real tap (a script
   * click would not count as the user's, and the video would not start).
   */
  /**
   * Plex Web's consent dialog (personalised advertising, shown before the
   * first free title plays): answered with "I Do Not Agree", which Plex
   * remembers. The free titles still play, with ads that are not
   * personalised. Matched by the button's exact label only.
   */
  private val plexConsentScript = "(function(){var w=['i do not agree','do not agree','i don\u2019t agree'," +
    "'ich stimme nicht zu','nicht zustimmen','ablehnen','alle ablehnen','decline','reject all'];" +
    "var b=Array.from(document.querySelectorAll('button,[role=button]')).find(function(e){" +
    "var l=(e.textContent||e.getAttribute('aria-label')||'').replace(/\\s+/g,' ').trim().toLowerCase();" +
    "return w.indexOf(l)>=0&&e.offsetParent!==null;});if(!b)return false;b.click();return true;})()"

  /** Watches a Plex Web page for the consent dialog for a while. */
  private fun watchPlexConsent(tab: Tab, url: String) {
    val started = System.currentTimeMillis()
    fun check() {
      val web = tab.webView ?: return
      if (web.url?.startsWith("https://app.plex.tv/") != true || System.currentTimeMillis() - started > 120_000) return
      web.evaluateJavascript(plexConsentScript) { value ->
        if (value == "true") {
          Log.i(TAG, "Plex consent declined")
          // The dialog stopped playback from starting: press Play again.
          tab.autoplayFor = null
          main.postDelayed({ tab.webView?.url?.let { maybeAutoplayPlex(tab, it) } }, 1500)
        } else {
          main.postDelayed({ check() }, 800)
        }
      }
    }
    check()
  }

  private fun maybeAutoplayPlex(tab: Tab, url: String) {
    if (!url.startsWith("https://app.plex.tv/") || !url.contains("tv.plex.provider.vod") || !url.contains("details")) return
    if (tab.autoplayFor == url) return
    tab.autoplayFor = url
    watchPlexConsent(tab, url)
    val started = System.currentTimeMillis()
    val find = "(function(){var b=document.querySelector('[data-testid=\"preplay-play\"]')||" +
      "Array.from(document.querySelectorAll('button')).find(function(e){var l=(e.getAttribute('aria-label')||e.textContent||'').trim().toLowerCase();" +
      "return l==='play'||l==='abspielen'||l==='wiedergeben'||l==='ansehen';});" +
      "if(!b)return null;var r=b.getBoundingClientRect();if(!r.width)return null;" +
      "return [r.left+r.width/2,r.top+r.height/2,window.innerWidth];})()"
    fun attempt() {
      val web = tab.webView ?: return
      if (tab.autoplayFor != url || System.currentTimeMillis() - started > 30_000) return
      web.evaluateJavascript(find) { value ->
        val parts = value?.trim('[', ']')?.split(',')?.mapNotNull { it.trim().toFloatOrNull() }
        if (parts == null || parts.size < 3 || parts[2] <= 0f || web.width <= 0 || !web.isAttachedToWindow) {
          main.postDelayed({ attempt() }, 700)
          return@evaluateJavascript
        }
        val scale = web.width / parts[2]
        tap(web, parts[0] * scale, parts[1] * scale)
        Log.i(TAG, "Free on plex.tv: play pressed")
        // Plex's player fills the page: the browser's bars go away too.
        main.postDelayed({ enterPageFullscreen(tab) }, 2500)
      }
    }
    main.postDelayed({ attempt() }, 1200)
  }

  private fun tap(web: WebView, x: Float, y: Float) {
    val now = android.os.SystemClock.uptimeMillis()
    val down = android.view.MotionEvent.obtain(now, now, android.view.MotionEvent.ACTION_DOWN, x, y, 0)
    down.source = android.view.InputDevice.SOURCE_TOUCHSCREEN
    web.dispatchTouchEvent(down)
    down.recycle()
    val up = android.view.MotionEvent.obtain(now, now + 60, android.view.MotionEvent.ACTION_UP, x, y, 0)
    up.source = android.view.InputDevice.SOURCE_TOUCHSCREEN
    web.dispatchTouchEvent(up)
    up.recycle()
  }

  private fun onNewWindow(tab: Tab, url: String, opener: String, userGesture: Boolean) {
    val openerSite = siteOf(hostOf(opener))
    fun open() {
      tab.popupAt = System.currentTimeMillis()
      send(tab.id, "openTab", mapOf("url" to url))
    }
    if (openerSite in popupSites) return open()
    if (!userGesture) {
      send(tab.id, "popupBlocked", mapOf("url" to url, "site" to openerSite))
      return
    }
    val target = siteOf(hostOf(url))
    if (target.isNotEmpty() && target == openerSite) return open()
    val trim = { u: String -> u.trimEnd('/') }
    if (tab.lastLink.isNotEmpty() && System.currentTimeMillis() - tab.linkAt < 3000 && trim(tab.lastLink) == trim(url)) {
      tab.lastLink = ""
      open()
    } else {
      send(tab.id, "popupBlocked", mapOf("url" to url, "site" to openerSite))
    }
  }

  private fun enterFullscreen(tabId: Int, view: View, callback: WebChromeClient.CustomViewCallback) {
    val decor = activity?.window?.decorView as? FrameLayout
    if (decor == null) {
      callback.onCustomViewHidden()
      return
    }
    exitFullscreen()
    view.setBackgroundColor(Color.BLACK)
    decor.addView(view, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    fullscreenView = view
    fullscreenCallback = callback
    fullscreenTab = tabId
    send(tabId, "fullscreen", mapOf("value" to true))
  }

  private fun mediaKey(event: android.view.KeyEvent): Boolean? {
    val code = event.keyCode
    // The Plex player page is a player too: OK and Left/Right control it.
    val playerPage = fullscreenView == null && playerTab?.webView?.isAttachedToWindow == true
    val inFullscreen = fullscreenView != null || playerPage
    val command: Any = when (code) {
      android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, android.view.KeyEvent.KEYCODE_HEADSETHOOK -> "toggle"
      android.view.KeyEvent.KEYCODE_MEDIA_PLAY -> "play"
      android.view.KeyEvent.KEYCODE_MEDIA_PAUSE -> "pause"
      android.view.KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> 10
      android.view.KeyEvent.KEYCODE_MEDIA_REWIND -> -10
      android.view.KeyEvent.KEYCODE_DPAD_CENTER, android.view.KeyEvent.KEYCODE_ENTER -> if (inFullscreen) "toggle" else return null
      android.view.KeyEvent.KEYCODE_DPAD_RIGHT -> if (inFullscreen) 10 else return null
      android.view.KeyEvent.KEYCODE_DPAD_LEFT -> if (inFullscreen) -10 else return null
      android.view.KeyEvent.KEYCODE_DPAD_UP, android.view.KeyEvent.KEYCODE_DPAD_DOWN -> if (fullscreenView != null) "none" else return null
      else -> return null
    }
    val tab = when {
      playerPage -> playerTab
      inFullscreen -> if (fullscreenTab == playerTab?.id) playerTab else tabs[fullscreenTab]
      playerTab?.webView?.isAttachedToWindow == true -> playerTab
      shownPage?.hasFocus() == true -> tabs[activeId]
      else -> null
    } ?: return null
    val web = tab.webView ?: return null
    if (event.action != android.view.KeyEvent.ACTION_DOWN) return true
    Log.d(TAG, "media key $code: $command (player page: $playerPage, fullscreen: ${fullscreenView != null})")
    if (playerPage && command == "toggle" && code != android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE &&
      code != android.view.KeyEvent.KEYCODE_HEADSETHOOK) {
      // OK pauses once a video is there; before (Plex's dialogs and buttons)
      // it still clicks what is selected.
      val down = android.view.KeyEvent(event)
      web.evaluateJavascript("(()=>{const v=document.querySelector('video');return !!(v&&v.readyState>0);})()") { has ->
        Log.d(TAG, "Plex OK: video loaded $has")
        if (has == "true") {
          plexSpace(web)
        } else {
          if (!web.hasFocus()) web.requestFocus()
          web.dispatchKeyEvent(down)
          web.dispatchKeyEvent(android.view.KeyEvent.changeAction(down, android.view.KeyEvent.ACTION_UP))
        }
      }
      return true
    }
    // Plex Web keeps its own player state (it starts a paused video again):
    // its Space shortcut pauses and plays.
    if (command is String && command != "none" && (web.url ?: "").startsWith("https://app.plex.tv/")) {
      plexSpace(web)
      return true
    }
    val message = when (command) {
      is Int -> "{plezyMedia:'seek',by:$command}"
      "none" -> return true
      else -> "{plezyMedia:'$command'}"
    }
    web.evaluateJavascript("window.postMessage($message,'*');", null)
    return true
  }

  /**
   * Pause and play in Plex Web with real taps, as a finger would: its own
   * play/pause button (Plex keeps its own player state and ignores scripted
   * clicks). With its controls hidden, a first tap shows them. Falls back
   * to its Space shortcut.
   */
  private fun plexSpace(web: WebView, attempt: Int = 0) {
    web.evaluateJavascript(PLEX_BUTTON) { result ->
      Log.i(TAG, "Plex play/pause: $result")
      val parts = result.trim('"').split(',')
      val x = parts.getOrNull(0)?.toFloatOrNull()
      val y = parts.getOrNull(1)?.toFloatOrNull()
      when {
        x != null && y != null -> web.evaluateJavascript(PLEX_PAUSED) { before ->
          tapWeb(web, x, y)
          main.postDelayed({
            web.evaluateJavascript(PLEX_PAUSED) { after -> Log.i(TAG, "Plex button tap: paused $before -> $after") }
          }, 500)
        }
        result.contains("hidden") && attempt == 0 -> {
          // A mouse moving over the player shows its controls without
          // touching the video (a tap there pauses or plays by itself).
          hoverWeb(web, web.width / 2f, web.height / 2f)
          main.postDelayed({ plexSpace(web, 1) }, 350)
        }
        result.contains("hidden") && attempt == 1 -> {
          // The tap that shows them may already pause or play: done then.
          web.evaluateJavascript(PLEX_PAUSED) { before ->
            tapWeb(web, web.width / 2f, web.height / 2f)
            main.postDelayed({
              web.evaluateJavascript(PLEX_PAUSED) { after ->
                Log.i(TAG, "Plex tap in the middle: paused $before -> $after")
                if (before == after) plexSpace(web, 2)
              }
            }, 450)
          }
        }
        else -> plexSpaceKey(web)
      }
    }
  }

  private fun hoverWeb(web: WebView, x: Float, y: Float) {
    val now = android.os.SystemClock.uptimeMillis()
    for ((i, action) in listOf(android.view.MotionEvent.ACTION_HOVER_ENTER, android.view.MotionEvent.ACTION_HOVER_MOVE,
      android.view.MotionEvent.ACTION_HOVER_MOVE).withIndex()) {
      val e = android.view.MotionEvent.obtain(now, now + i * 30L, action, x + i * 12f, y + i * 8f, 0)
      e.source = android.view.InputDevice.SOURCE_MOUSE
      web.dispatchGenericMotionEvent(e)
      e.recycle()
    }
  }

  private fun tapWeb(web: WebView, x: Float, y: Float) {
    val now = android.os.SystemClock.uptimeMillis()
    for ((action, time) in listOf(android.view.MotionEvent.ACTION_DOWN to now, android.view.MotionEvent.ACTION_UP to now + 50)) {
      val e = android.view.MotionEvent.obtain(now, time, action, x, y, 0)
      e.source = android.view.InputDevice.SOURCE_TOUCHSCREEN
      web.dispatchTouchEvent(e)
      e.recycle()
    }
  }

  private fun plexSpaceKey(web: WebView) {
    if (!web.hasFocus()) web.requestFocus()
    val now = android.os.SystemClock.uptimeMillis()
    web.dispatchKeyEvent(android.view.KeyEvent(now, now, android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_SPACE, 0))
    web.dispatchKeyEvent(android.view.KeyEvent(now, now + 40, android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_SPACE, 0))
  }

  /** The tab whose page fills the screen without the browser's bars (Plex's player). */
  private var pageFullscreenTab = 0

  private fun enterPageFullscreen(tab: Tab) {
    if (tabs[tab.id] !== tab || fullscreenView != null || pageFullscreenTab == tab.id) return
    pageFullscreenTab = tab.id
    send(tab.id, "fullscreen", mapOf("value" to true))
  }

  /** Leaves a page's video fullscreen; true when there was one. */
  fun exitFullscreen(): Boolean {
    if (fullscreenView == null && pageFullscreenTab != 0) {
      val id = pageFullscreenTab
      pageFullscreenTab = 0
      send(id, "fullscreen", mapOf("value" to false))
      return true
    }
    val view = fullscreenView ?: return false
    (view.parent as? ViewGroup)?.removeView(view)
    fullscreenView = null
    val callback = fullscreenCallback
    fullscreenCallback = null
    callback?.onCustomViewHidden()
    send(fullscreenTab, "fullscreen", mapOf("value" to false))
    return true
  }

  // --------------------------------------------------------- phone remote

  private val insertTextScript = """(t=>{const e=document.activeElement;if(!e)return;
if(e.isContentEditable){document.execCommand('insertText',false,t);return;}
if('value' in e){try{const s=e.selectionStart??e.value.length,n=e.selectionEnd??s;e.setRangeText(t,s,n,'end');}
catch(_){e.value+=t;}e.dispatchEvent(new InputEvent('input',{bubbles:true,data:t,inputType:'insertText'}));
e.dispatchEvent(new Event('change',{bubbles:true}));}})"""

  /**
   * The phone's D-pad: the same key presses as the TV remote, through the
   * activity, so they move between the app's buttons and the page alike.
   */
  private fun remoteDpad(keyCode: Int) {
    val activity = activity ?: return
    val now = android.os.SystemClock.uptimeMillis()
    fun key(action: Int, time: Long) = android.view.KeyEvent(
      now, time, action, keyCode, 0, 0, android.view.KeyCharacterMap.VIRTUAL_KEYBOARD, 0,
      android.view.KeyEvent.FLAG_FROM_SYSTEM, android.view.InputDevice.SOURCE_DPAD,
    )
    activity.dispatchKeyEvent(key(android.view.KeyEvent.ACTION_DOWN, now))
    main.postDelayed({ activity.dispatchKeyEvent(key(android.view.KeyEvent.ACTION_UP, now + 60)) }, 60)
  }

  private fun onRemote(events: org.json.JSONArray) {
    val tab = tabs[activeId]
    for (i in 0 until events.length()) {
      val e = events.optJSONObject(i) ?: continue
      val web = tab?.webView
      when (e.optString("t")) {
        "move" -> remoteTouch.move(e.optDouble("dx").toFloat(), e.optDouble("dy").toFloat())
        "scroll" -> remoteTouch.scroll(e.optDouble("dx").toFloat(), e.optDouble("dy").toFloat())
        "tap" -> remoteTouch.tap()
        "bar" -> remoteTouch.scrollShape(e.optInt("v") == 1)
        "closeKeyboard" -> {
          // Leaves the page's text field and hides the TV's keyboard.
          web?.evaluateJavascript("(()=>{const a=document.activeElement;if(a&&a!==document.body)a.blur();})()", null)
          val act = activity
          val target = act?.currentFocus ?: web
          if (act != null && target != null) {
            (act.getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager)
              .hideSoftInputFromWindow(target.windowToken, 0)
          }
        }
        "dpad" -> {
          val code = when (e.optString("v")) {
            "up" -> android.view.KeyEvent.KEYCODE_DPAD_UP
            "down" -> android.view.KeyEvent.KEYCODE_DPAD_DOWN
            "left" -> android.view.KeyEvent.KEYCODE_DPAD_LEFT
            "right" -> android.view.KeyEvent.KEYCODE_DPAD_RIGHT
            else -> android.view.KeyEvent.KEYCODE_DPAD_CENTER
          }
          remoteDpad(code)
        }
        "back" -> if (web?.canGoBack() == true) web.goBack()
        "nav" -> when (e.optString("v")) {
          "back" -> if (web?.canGoBack() == true) web.goBack()
          "forward" -> if (web?.canGoForward() == true) web.goForward()
          "reload" -> if (web != null) web.reload() else tab?.let { revive(it) }
        }
        "key" -> {
          val code = when (e.optString("v")) {
            "Enter" -> android.view.KeyEvent.KEYCODE_ENTER
            "Backspace" -> android.view.KeyEvent.KEYCODE_DEL
            "Tab" -> android.view.KeyEvent.KEYCODE_TAB
            else -> null
          }
          if (web != null && code != null) {
            if (!web.hasFocus()) web.requestFocus()
            web.dispatchKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, code))
            web.dispatchKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, code))
          }
        }
        "text" -> if (web != null) {
          if (!web.hasFocus()) web.requestFocus()
          web.evaluateJavascript("$insertTextScript(${JSONObject.quote(e.optString("v"))});", null)
        }
        "url" -> {
          Log.i(TAG, "Phone remote: address received")
          send(0, "remoteUrl", mapOf("url" to e.optString("v")))
        }
      }
    }
  }

  // ------------------------------------------------------------ downloads

  private val downloadManager get() = appContext.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

  private fun startDownload(request: Int, pending: PendingDownload) {
    if (!pending.url.startsWith("http")) {
      send(pending.tab, "downloadState", mapOf("download" to request, "state" to "failed", "url" to pending.url, "path" to pending.name))
      return
    }
    try {
      val r = DownloadManager.Request(Uri.parse(pending.url))
        .setTitle(pending.name)
        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
        .addRequestHeader("User-Agent", pending.userAgent)
      CookieManager.getInstance().getCookie(pending.url)?.let { r.addRequestHeader("Cookie", it) }
      if (pending.referer.startsWith("http")) r.addRequestHeader("Referer", pending.referer)
      pending.mime?.let { r.setMimeType(it) }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        r.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, pending.name)
      } else {
        r.setDestinationInExternalFilesDir(appContext, Environment.DIRECTORY_DOWNLOADS, pending.name)
      }
      downloads[request] = pending.tab to downloadManager.enqueue(r)
      send(pending.tab, "downloadState", mapOf("download" to request, "state" to "running", "url" to pending.url, "path" to pending.name))
      poll()
    } catch (e: Exception) {
      Log.w(TAG, "download failed to start", e)
      send(pending.tab, "downloadState", mapOf("download" to request, "state" to "failed", "url" to pending.url, "path" to pending.name))
    }
  }

  private fun poll() {
    if (polling) return
    polling = true
    main.postDelayed(object : Runnable {
      override fun run() {
        for ((request, entry) in downloads.toMap()) {
          val (tab, id) = entry
          val cursor = downloadManager.query(DownloadManager.Query().setFilterById(id)) ?: continue
          cursor.use { c ->
            if (!c.moveToFirst()) {
              downloads.remove(request)
              send(tab, "downloadState", mapOf("download" to request, "state" to "failed"))
              return@use
            }
            val status = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val received = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            val local = c.getString(c.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)) ?: ""
            val uri = c.getString(c.getColumnIndexOrThrow(DownloadManager.COLUMN_URI)) ?: ""
            val state = when (status) {
              DownloadManager.STATUS_SUCCESSFUL -> "completed"
              DownloadManager.STATUS_FAILED -> "failed"
              else -> "running"
            }
            val path = Uri.parse(local).path ?: local
            send(
              tab, "downloadState",
              mapOf("download" to request, "state" to state, "received" to received, "total" to total.coerceAtLeast(0), "path" to path, "url" to uri),
            )
            if (state == "completed") finished[path] = id
            if (state != "running") downloads.remove(request)
          }
        }
        if (downloads.isEmpty()) {
          polling = false
        } else {
          main.postDelayed(this, 700)
        }
      }
    }, 300)
  }

  // ------------------------------------------------------------- methods

  private fun list(call: MethodCall, key: String): Set<String> =
    (call.argument<List<Any?>>(key) ?: emptyList()).filterIsInstance<String>().map { it.lowercase(Locale.ROOT) }.toSet()

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "initialize" -> {
        httpsUpgrade = call.argument<Boolean>("httpsUpgrade") ?: true
        tracking = call.argument<Int>("tracking") ?: 2
        result.success(true)
      }
      "capabilities" -> result.success(
        mapOf(
          "privateTabs" to WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE),
          "adblock" to AdblockEngine.available,
          "pauseDownloads" to false,
        ),
      )
      "dispose" -> {
        disposeAll()
        result.success(null)
      }
      "setRect", "setCutouts" -> result.success(null)
      "setPointer" -> {
        pointer = call.argument<Boolean>("value") ?: false
        page?.pointerMode = pointer
        result.success(null)
      }
      "setVisible" -> {
        visible = call.argument<Boolean>("visible") ?: false
        applyLayout()
        result.success(null)
      }
      "setActive" -> {
        activeId = call.argument<Int>("id") ?: 0
        applyLayout()
        result.success(null)
      }
      "setPopupSites" -> {
        popupSites = list(call, "sites")
        result.success(null)
      }
      "setHttpsUpgrade" -> {
        httpsUpgrade = call.argument<Boolean>("value") ?: true
        result.success(null)
      }
      "setTrackingPrevention" -> {
        tracking = call.argument<Int>("level") ?: 2
        for (tab in tabs.values) {
          tab.webView?.let { CookieManager.getInstance().setAcceptThirdPartyCookies(it, tracking < 2) }
          installPrivacyScript(tab)
        }
        result.success(null)
      }
      "setDarkScript" -> {
        darkScript = call.argument<String>("script") ?: ""
        for (tab in tabs.values) {
          installDarkScript(tab)
          val web = tab.webView ?: continue
          web.evaluateJavascript(
            darkScript.ifEmpty { "try{window.__plezyDark&&window.__plezyDark.disable();}catch(e){}" }, null,
          )
        }
        result.success(null)
      }
      "answerPermission" -> result.success(null)
      "answerDownload" -> {
        val request = call.argument<Int>("request") ?: 0
        val pending = pendingDownloads.remove(request)
        if (pending != null && call.argument<Boolean>("allow") == true) startDownload(request, pending)
        result.success(null)
      }
      "cancelDownload" -> {
        val request = call.argument<Int>("download") ?: 0
        downloads.remove(request)?.let { (tab, id) ->
          downloadManager.remove(id)
          send(tab, "downloadState", mapOf("download" to request, "state" to "failed"))
        }
        result.success(null)
      }
      "pauseDownload", "resumeDownload" -> result.success(null)
      "openDownload" -> {
        val path = call.argument<String>("path") ?: ""
        result.success(openDownload(path))
      }
      "showDownloads" -> {
        try {
          activity?.startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
          result.success(true)
        } catch (_: ActivityNotFoundException) {
          result.success(false)
        }
      }
      "adblockLoad" -> {
        val config = call.argument<String>("config") ?: "{}"
        val generation = ++adblockGeneration
        val started = System.currentTimeMillis()
        if (!AdblockEngine.available) {
          send(0, "adblockReady", mapOf("ok" to false, "ms" to 0))
          result.success(null)
          return
        }
        Thread {
          val engine = try {
            AdblockEngine.load(config)
          } catch (e: Throwable) {
            Log.w(TAG, "adblock load", e)
            0L
          }
          main.post {
            if (generation != adblockGeneration) {
              if (engine != 0L) AdblockEngine.free(engine)
              return@post
            }
            if (engine != 0L) {
              val old = adblock
              adblock = engine
              if (old == 0L) installServiceWorkerBlocking()
              // Request threads may still use the old one for a moment.
              if (old != 0L) main.postDelayed({ AdblockEngine.free(old) }, 10_000)
            }
            send(0, "adblockReady", mapOf("ok" to (engine != 0L), "ms" to (System.currentTimeMillis() - started)))
          }
        }.start()
        result.success(null)
      }
      "adblockSetEnabled" -> {
        adblockEnabled = call.argument<Boolean>("value") ?: true
        result.success(null)
      }
      "adblockSetOffSites" -> {
        adblockOffSites = list(call, "sites")
        result.success(null)
      }
      "clearCache" -> {
        WebView(appContext).apply {
          clearCache(true)
          destroy()
        }
        result.success(null)
      }
      "clearSiteData" -> {
        WebStorage.getInstance().deleteAllData()
        CookieManager.getInstance().removeAllCookies { CookieManager.getInstance().flush(); result.success(null) }
      }
      "cacheSize" -> Thread {
        val size = listOf(File(appContext.cacheDir, "WebView"), File(appContext.cacheDir, "org.chromium.android_webview"))
          .sumOf { dir -> dir.walkTopDown().filter { it.isFile }.sumOf { it.length() } }
        main.post { result.success(size) }
      }.start()
      "exitFullscreen" -> result.success(exitFullscreen())
      "remoteStart" -> {
        remote.onConnected = { main.post { send(0, "remoteConnected") } }
        val server = remote
        Thread {
          val url = server.start()
          main.post { result.success(url) }
        }.start()
      }
      "remoteStop" -> {
        if (remote.running) remote.stop()
        remoteTouch.dispose()
        result.success(null)
      }
      "createTab" -> createTab(call, result)
      "closeTab" -> {
        closeTab(call.argument<Int>("id") ?: 0)
        result.success(null)
      }
      else -> tabMethod(call, result)
    }
  }

  private fun createTab(call: MethodCall, result: MethodChannel.Result) {
    val id = call.argument<Int>("id") ?: 0
    if (tabs.containsKey(id)) {
      result.success(true)
      return
    }
    val private = call.argument<Boolean>("private") ?: false
    if (private && !WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
      result.error("CREATE_FAILED", "Private tabs need a newer Android System WebView", null)
      return
    }
    val tab = Tab(id, private)
    tabs[id] = tab
    try {
      createWebView(tab)
    } catch (e: Exception) {
      tabs.remove(id)
      result.error("CREATE_FAILED", e.toString(), null)
      return
    }
    val url = call.argument<String>("url") ?: ""
    applyLayout()
    if (url.isNotEmpty()) load(tab, url)
    result.success(true)
  }

  private fun load(tab: Tab, url: String) {
    val web = tab.webView ?: return
    tab.lastUrl = url
    if (url.startsWith("http")) preparePage(tab, url, runNow = false)
    web.loadUrl(url)
  }

  /** A tab whose page process died gets a new WebView, loading its last page. */
  private fun revive(tab: Tab): WebView? {
    tab.crashed = false
    tab.webView?.let { return it }
    createWebView(tab)
    applyLayout()
    if (tab.lastUrl.isNotEmpty()) load(tab, tab.lastUrl)
    if (tab.muted) applyMute(tab)
    return tab.webView
  }

  private fun tabMethod(call: MethodCall, result: MethodChannel.Result) {
    val tab = tabs[call.argument<Int>("id") ?: 0]
    if (tab == null) {
      result.error("NO_TAB", "No such browser tab", null)
      return
    }
    if (call.method == "reload" && tab.webView == null) {
      revive(tab)
      result.success(null)
      return
    }
    val web = tab.webView
    if (web == null) {
      result.error("NO_TAB", "The tab has no page", null)
      return
    }
    when (call.method) {
      "navigate" -> {
        val url = call.argument<String>("url") ?: ""
        if (call.argument<Boolean>("allowHttp") == true) {
          hostOf(url).takeIf { it.isNotEmpty() }?.let { tab.httpHosts.add(it) }
        }
        load(tab, url)
      }
      "back" -> if (web.canGoBack()) web.goBack()
      "forward" -> if (web.canGoForward()) web.goForward()
      "reload" -> web.reload()
      "stop" -> web.stopLoading()
      "focus" -> page?.focusPage() ?: run { focusPending = true }
      "blur" -> {
        focusPending = false
        page?.flutterFocused = false
      }
      "proceedBlocked" -> {
        val url = call.argument<String>("url") ?: ""
        hostOf(url).takeIf { it.isNotEmpty() }?.let { tab.allowedHosts.add(it) }
        load(tab, url)
      }
      "setMuted" -> {
        tab.muted = call.argument<Boolean>("value") ?: false
        applyMute(tab)
      }
      "suspend" -> {
        tab.suspended = true
        web.onPause()
        applyLayout()
      }
      "resume" -> {
        tab.suspended = false
        web.onResume()
        applyLayout()
      }
      else -> {
        result.notImplemented()
        return
      }
    }
    result.success(null)
  }

  private fun openDownload(path: String): Boolean {
    val activity = activity ?: return false
    return try {
      val id = finished[path] ?: return false
      val uri = downloadManager.getUriForDownloadedFile(id) ?: return false
      val mime = downloadManager.getMimeTypeForDownloadedFile(id) ?: "*/*"
      activity.startActivity(
        Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
      )
      true
    } catch (e: Exception) {
      Log.d(TAG, "open download: $e")
      false
    }
  }

  private fun closeTab(id: Int) {
    val tab = tabs.remove(id) ?: return
    if (fullscreenTab == id || pageFullscreenTab == id) exitFullscreen()
    tab.webView?.let { web ->
      (web.parent as? ViewGroup)?.removeView(web)
      web.stopLoading()
      web.destroy()
    }
    tab.webView = null
    applyLayout()
    // Nothing of private tabs stays once the last one closes.
    if (tab.private && tabs.values.none { it.private }) deletePrivateProfile()
  }

  private fun deletePrivateProfile() {
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) return
    main.postDelayed({
      if (tabs.values.any { it.private }) return@postDelayed
      try {
        ProfileStore.getInstance().deleteProfile(PRIVATE_PROFILE)
      } catch (e: Exception) {
        Log.d(TAG, "private profile: $e")
      }
    }, 1000)
  }

  private fun disposeAll() {
    exitFullscreen()
    if (remote.running) remote.stop()
    remoteTouch.dispose()
    for (id in tabs.keys.toList()) closeTab(id)
    page?.show(null)
  }
}
