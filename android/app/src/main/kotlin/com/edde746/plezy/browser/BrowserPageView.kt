package com.edde746.plezy.browser

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.platform.PlatformView

/**
 * Where the browser's active tab shows: the one platform view of the browser
 * page (Dart: _PageSlot). Tabs keep their WebView while hidden; the plugin
 * moves the active one in here.
 *
 * On a TV the remote drives an on-screen pointer: the arrows move it (and
 * scroll at the edges), OK clicks, and Up at the top of a page returns to the
 * app's toolbar.
 */
@SuppressLint("ViewConstructor")
internal class BrowserPageView(
  context: Context,
  private val plugin: BrowserPlugin,
  private val tv: Boolean,
) : FrameLayout(context), PlatformView {

  private var current: WebView? = null
  private val cursor: CursorView? = if (tv) CursorView(context) else null
  private var cursorX = -1f
  private var cursorY = -1f
  private var repeat = 0

  private companion object {
    // What the selection and the scroll positions were before a key.
    const val SNAPSHOT = "(()=>{const s=[];const d=document.scrollingElement||document.documentElement;s.push(d.scrollTop);" +
      "const m=window.__plezyScroller;if(m&&m.isConnected)s.push(m.scrollTop);" +
      "window.__plezyKeySnap={a:document.activeElement,s:s.join(',')};})()"
    const val BLUR_HIDDEN = "(()=>{const a=document.activeElement;if(!a||a===document.body)return;" +
      "const r=a.getBoundingClientRect();if(r.bottom<0||r.top>innerHeight)a.blur();})()"
    const val UNCHANGED = "(()=>{const p=window.__plezyKeySnap;if(!p)return false;const s=[];" +
      "const d=document.scrollingElement||document.documentElement;s.push(d.scrollTop);" +
      "const m=window.__plezyScroller;if(m&&m.isConnected)s.push(m.scrollTop);" +
      "return p.a===document.activeElement&&p.s===s.join(',');})()"
  }
  private var lastUpAtTop = 0L
  private var okLong = false
  private var dragging = false
  private val upPresses = ArrayDeque<Long>()
  private var lastCountedUp = -1L
  // Until then, Up/Down scroll the page directly (the key found nothing to
  // select or scroll by itself, so held keys don't go back to the page).
  private var keyScrollUntil = 0L

  /** The remote moves a pointer (on) or selects the page's elements (off). */
  var pointerMode = false
    set(value) {
      field = value
      updateCursor()
    }

  init {
    setBackgroundColor(Color.TRANSPARENT)
    isFocusable = true
    isFocusableInTouchMode = true
    descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
    cursor?.let {
      it.visibility = View.GONE
      addView(it, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }
    plugin.attachPage(this)
  }

  override fun getView(): View = this

  override fun dispose() {
    show(null)
    plugin.detachPage(this)
  }

  /** Shows [webView] (or nothing), taking it out of wherever it was. */
  fun show(webView: WebView?) {
    if (current === webView) return
    current?.let { removeView(it) }
    current = webView
    if (webView != null) {
      (webView.parent as? ViewGroup)?.removeView(webView)
      addView(webView, 0, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }
    updateCursor()
    cursor?.bringToFront()
  }

  /** Flutter's focus is on the page (set by Dart, cleared when it leaves). */
  @Volatile var flutterFocused = false

  fun focusPage() {
    flutterFocused = true
    val had = current?.hasFocus() == true
    val ok = requestFocus()
    android.util.Log.d("PlezyBrowser", "page focus requested: $ok (had it: $had)")
    if (!tv) current?.requestFocus()
  }

  private val focusListener = android.view.ViewTreeObserver.OnGlobalFocusChangeListener { _, _ -> updateCursor() }

  override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    viewTreeObserver.addOnGlobalFocusChangeListener(focusListener)
  }

  override fun onDetachedFromWindow() {
    viewTreeObserver.removeOnGlobalFocusChangeListener(focusListener)
    super.onDetachedFromWindow()
  }

  /** The pointer shows while the page (or the WebView in it) has the focus. */
  private fun updateCursor() {
    val c = cursor ?: return
    val shown = current != null && ((pointerMode && hasFocus()) || remoteActive)
    c.visibility = if (shown) View.VISIBLE else View.GONE
    if (shown && cursorX < 0 && width > 0) {
      cursorX = width / 2f
      cursorY = height / 3f
    }
    placeCursor()
  }

  override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
    if (event.actionMasked == MotionEvent.ACTION_DOWN) plugin.onPageTouched()
    return false
  }

  override fun dispatchKeyEvent(event: KeyEvent): Boolean {
    if (tv && current != null && handleRemoteKey(event)) return true
    return super.dispatchKeyEvent(event)
  }

  /** The remote's arrows and OK on a TV: the pointer. False when not handled. */
  /**
   * Up three times within about a second, starting on the page: focus goes
   * to the address bar. True when this press completed it.
   */
  fun tripleUp(event: KeyEvent, onPage: Boolean): Boolean {
    if (event.keyCode != KeyEvent.KEYCODE_DPAD_UP || event.action != KeyEvent.ACTION_DOWN || event.repeatCount != 0) return false
    if (!tv || current == null || event.downTime == lastCountedUp) return false
    val now = SystemClock.uptimeMillis()
    while (upPresses.isNotEmpty() && now - upPresses.first() > 1100) upPresses.removeFirst()
    // The first press must be on the page; the others may follow it out.
    if (!onPage && upPresses.isEmpty()) return false
    lastCountedUp = event.downTime
    upPresses.addLast(now)
    if (upPresses.size < 3) return false
    upPresses.clear()
    android.util.Log.d("PlezyBrowser", "up three times: address bar")
    plugin.onFocusAddress(this)
    return true
  }

  private var lastMoveKey = 0
  private var lastMoveAt = 0L
  private var okHoldStart = 0L
  private var okLastUp = 0L
  private var okChained = false
  private var okPending: Runnable? = null
  private var okDownEvent: KeyEvent? = null
  /** Remotes seen resending OK while held: their clicks wait a moment. */
  private val resendingDevices = HashSet<Int>()

  /**
   * Holding OK switches between pointer and selection for this site (as TV
   * browsers do with a long press); the press itself then clicks nothing.
   * Works with real key repeats and with remotes that resend presses.
   * True when the event was dealt with here.
   */
  private fun okKey(web: WebView, event: KeyEvent): Boolean {
    val now = event.eventTime
    if (event.action == KeyEvent.ACTION_DOWN) {
      if (event.repeatCount > 0) {
        if (!okLong && now - event.downTime >= 700) toggleByOk()
        return true
      }
      if (now - okLastUp < 350) {
        // Another press right after the last: the button is being held.
        if (okChained) resendingDevices.add(event.deviceId)
        okChained = true
        okPending?.let { removeCallbacks(it) }
        okPending = null
        okDownEvent = null
        if (!okLong && now - okHoldStart >= 700) toggleByOk()
        return true
      }
      okHoldStart = now
      okLong = false
      okChained = false
      okDownEvent = null
      if (event.deviceId in resendingDevices) {
        // Held back until it is clear this is a click, not a hold.
        okDownEvent = KeyEvent(event)
        return true
      }
      return false
    }
    if (event.action != KeyEvent.ACTION_UP) return false
    okLastUp = now
    if (okLong) {
      if (!pointerMode && !okChained && okDownEvent == null) {
        web.dispatchKeyEvent(KeyEvent.changeFlags(event, event.flags or KeyEvent.FLAG_CANCELED))
      }
      return true
    }
    if (okChained) return true
    val down = okDownEvent ?: return false
    okDownEvent = null
    val up = KeyEvent(event)
    val run = Runnable {
      okPending = null
      if (current !== web) return@Runnable
      if (pointerMode) {
        click(web)
      } else {
        web.dispatchKeyEvent(down)
        web.dispatchKeyEvent(up)
      }
    }
    okPending = run
    postDelayed(run, 360)
    return true
  }

  private fun toggleByOk() {
    okLong = true
    okPending?.let { removeCallbacks(it) }
    okPending = null
    okDownEvent = null
    plugin.onTogglePointer()
  }

  fun handleRemoteKey(event: KeyEvent): Boolean {
    if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
      android.util.Log.d("PlezyBrowser", "page key ${event.keyCode} (page shown: ${current != null})")
    }
    val web = current
    if (!tv || web == null) return false
    // Holding OK switches between pointer and selection for this site (as
    // TV browsers do with a long press); the press itself then clicks nothing.
    val ok = event.keyCode == KeyEvent.KEYCODE_DPAD_CENTER || event.keyCode == KeyEvent.KEYCODE_ENTER ||
      event.keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER || event.keyCode == KeyEvent.KEYCODE_BUTTON_A
    if (ok && okKey(web, event)) return true
    if (tripleUp(event, true)) return true
    if (!pointerMode) return selectKey(web, event)
    when (event.keyCode) {
      KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN -> {
        if (event.action != KeyEvent.ACTION_DOWN) return true
        // A press moves a small step (about 1/80 of the screen) for detail;
        // holding the key speeds it up to about 1/12.
        // Some remotes (LG Magic Remote) resend single presses while held
        // instead of repeats: quick presses of the same key count as held.
        val now = SystemClock.uptimeMillis()
        val held = event.repeatCount > 0 || (event.keyCode == lastMoveKey && now - lastMoveAt < 350)
        lastMoveKey = event.keyCode
        lastMoveAt = now
        repeat = if (held) (repeat + 1).coerceAtMost(20) else 0
        val base = (width.coerceAtLeast(height) / 80f).coerceAtLeast(10f)
        move(event.keyCode, base * (1f + repeat * 0.27f))
        return true
      }
      KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_BUTTON_A -> {
        if (event.action == KeyEvent.ACTION_UP) click(web)
        return true
      }
    }
    return false
  }

  /**
   * Without the pointer: the WebView's own D-pad navigation moves between
   * the page's links, buttons and fields. Up with nothing further up (or
   * twice quickly at the top of the page) goes back to the toolbar.
   */
  private fun selectKey(web: WebView, event: KeyEvent): Boolean {
    if (!web.hasFocus()) web.requestFocus()
    val vertical = event.keyCode == KeyEvent.KEYCODE_DPAD_UP || event.keyCode == KeyEvent.KEYCODE_DPAD_DOWN
    val down = event.keyCode == KeyEvent.KEYCODE_DPAD_DOWN
    val now = SystemClock.uptimeMillis()
    // Scrolling by touch already: further presses (and held keys) keep
    // scrolling instead of going back to the page's own navigation.
    if (vertical && now < keyScrollUntil) {
      if (event.action == KeyEvent.ACTION_DOWN) {
        keyScrollUntil = now + 900
        touchScroll(web, 0f, (if (down) 1 else -1) * height * 0.3f)
      }
      return true
    }
    // Held keys repeat too fast for the check below: only presses are checked.
    val check = vertical && event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0
    if (check) web.evaluateJavascript(SNAPSHOT, null)
    val handled = web.dispatchKeyEvent(event)
    if (check) {
      // Pages that scroll inside an element: when the key neither moved
      // the selection nor scrolled anything, the page is scrolled here.
      postDelayed({
        web.evaluateJavascript(UNCHANGED) { value ->
          if (value == "true") {
            keyScrollUntil = SystemClock.uptimeMillis() + 900
            touchScroll(web, 0f, (if (down) 1 else -1) * height * 0.3f)
          }
        }
      }, 150)
    }
    if (event.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_DPAD_UP) {
      val now = SystemClock.uptimeMillis()
      // The page itself at the top (fields and inner scroll areas may still
      // take Up): a second quick Up goes back to the toolbar.
      val atTop = web.scrollY <= 0 || !web.canScrollVertically(-1)
      if (!handled && atTop) {
        lastUpAtTop = 0
        plugin.onLeavePage(this)
        return true
      }
      lastUpAtTop = if (atTop) now else 0
    }
    return true
  }

  private fun move(key: Int, distance: Float) {
    val web = current ?: return
    val margin = 4f * resources.displayMetrics.density
    var dx = 0f
    var dy = 0f
    when (key) {
      KeyEvent.KEYCODE_DPAD_LEFT -> dx = -distance
      KeyEvent.KEYCODE_DPAD_RIGHT -> dx = distance
      KeyEvent.KEYCODE_DPAD_UP -> dy = -distance
      KeyEvent.KEYCODE_DPAD_DOWN -> dy = distance
    }
    val nx = cursorX + dx
    val ny = cursorY + dy
    // At an edge the page scrolls under the pointer instead.
    if (ny < margin && dy < 0) {
      if (!web.canScrollVertically(-1)) {
        android.util.Log.d("PlezyBrowser", "pointer left the page at the top")
        plugin.onLeavePage(this)
        return
      }
      scroll(web, 0f, -1f)
    } else if (ny > height - margin && dy > 0) {
      scroll(web, 0f, 1f)
    } else if (nx < margin && dx < 0) {
      scroll(web, -1f, 0f)
    } else if (nx > width - margin && dx > 0) {
      scroll(web, 1f, 0f)
    }
    cursorX = nx.coerceIn(margin, (width - margin).coerceAtLeast(margin))
    cursorY = ny.coerceIn(margin, (height - margin).coerceAtLeast(margin))
    placeCursor()
    hover(web)
  }

  private fun placeCursor() {
    cursor?.place(cursorX, cursorY)
  }

  /** At the pointer's edge: scrolls whatever is under it by a step. */
  private fun scroll(web: WebView, x: Float, y: Float) {
    val step = height * 0.18f
    // From the middle of the page: at the edge the drag would start on a
    // fixed bar or footer that does not scroll.
    touchScroll(web, x * step, y * step, fromMiddle = true)
  }

  /**
   * Scrolls like a finger: a short drag at the pointer (or the middle),
   * held still before lifting so it does not fling. Works wherever touch
   * scrolling works, inner scroll areas included. [dx], [dy] in view
   * pixels; positive [dy] shows more of the page below.
   */
  private fun touchScroll(web: WebView, dx: Float, dy: Float, fromMiddle: Boolean = false) {
    if (dragging) return
    val startX = if (cursorX >= 0 && !(fromMiddle && dx != 0f)) cursorX else width / 2f
    val startY = if (cursorY >= 0 && !(fromMiddle && dy != 0f)) cursorY else height / 2f
    // Keep the drag on screen: start where there is room for it.
    val fromY = (startY + dy / 2f).coerceIn(height * 0.1f, height * 0.9f)
    val fromX = (startX + dx / 2f).coerceIn(width * 0.1f, width * 0.9f)
    // Sent in real time: Chromium measures the speed itself, and events
    // all at once looked like a fast flick that flung to the page's end.
    val down = SystemClock.uptimeMillis()
    fun send(action: Int, x: Float, y: Float) {
      val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, x, y, 0)
      event.source = InputDevice.SOURCE_TOUCHSCREEN
      web.dispatchTouchEvent(event)
      event.recycle()
    }
    dragging = true
    send(MotionEvent.ACTION_DOWN, fromX, fromY)
    val steps = 8
    for (i in 1..steps) {
      postDelayed({ send(MotionEvent.ACTION_MOVE, fromX - dx * i / steps, fromY - dy * i / steps) }, i * 16L)
    }
    // Held still, then lifted: no fling.
    postDelayed({ send(MotionEvent.ACTION_MOVE, fromX - dx, fromY - dy) }, steps * 16L + 120)
    postDelayed({
      send(MotionEvent.ACTION_UP, fromX - dx, fromY - dy)
      dragging = false
      // A selected element now out of view would pull the page back to it
      // on the next key: let go of it, so navigation starts from the view.
      web.evaluateJavascript(BLUR_HIDDEN, null)
    }, steps * 16L + 160)
  }


  /**
   * Scrolls the scrollable element under the pointer (else the page) by
   * [dx], [dy] CSS pixels, in the page itself: WebView ignores synthetic
   * wheel events.
   */
  private fun scrollBy(web: WebView, dx: Float, dy: Float) {
    val density = resources.displayMetrics.density
    val x = (cursorX.coerceAtLeast(0f) / density).toInt()
    val y = (cursorY.coerceAtLeast(0f) / density).toInt()
    web.evaluateJavascript(
      "(function(x,y,dx,dy){" +
        "function sc(e){var s=getComputedStyle(e);return (/(auto|scroll|overlay)/.test(s.overflowY)&&e.scrollHeight>e.clientHeight+2)||" +
        "(/(auto|scroll|overlay)/.test(s.overflowX)&&e.scrollWidth>e.clientWidth+2);}" +
        "var e=document.elementFromPoint(x,y);" +
        "while(e&&e!==document.body&&e!==document.documentElement){if(sc(e)){e.scrollBy({left:dx,top:dy,behavior:'instant'});return 'element under the pointer';}e=e.parentElement;}" +
        "var d=document.scrollingElement||document.documentElement;" +
        "if(d.scrollHeight>window.innerHeight+2||d.scrollWidth>window.innerWidth+2){var t=d.scrollTop,l=d.scrollLeft;" +
        "window.scrollBy({left:dx,top:dy,behavior:'instant'});if(d.scrollTop!==t||d.scrollLeft!==l||!dy)return 'page';}" +
        // Pages that scroll inside an element (the window itself doesn't):
        // the largest scrollable element, remembered for the next steps.
        "var m=window.__plezyScroller;if(!m||!m.isConnected||!sc(m)){m=null;var best=0;" +
        "for(var n of document.querySelectorAll('body *')){if(n.clientHeight<200)continue;if(!sc(n))continue;" +
        "var a=n.clientWidth*n.clientHeight;if(a>best){best=a;m=n;}}window.__plezyScroller=m;}" +
        "if(m){m.scrollBy({left:dx,top:dy,behavior:'instant'});return 'largest scroll area';}return 'nothing scrollable';})($x,$y,$dx,$dy)",
    ) { result ->
      val now = SystemClock.uptimeMillis()
      if (now - lastScrollLog > 2000) {
        lastScrollLog = now
        android.util.Log.d("PlezyBrowser", "scroll: $result")
      }
    }
  }

  // ---- Phone remote (PhoneRemoteServer) ----

  private var remoteActive = false
  private var lastScrollLog = 0L

  private fun remoteReady(): WebView? {
    val web = current ?: return null
    if (cursor == null) return null
    remoteActive = true
    if (cursorX < 0) {
      cursorX = width / 2f
      cursorY = height / 3f
    }
    updateCursor()
    return web
  }

  /** Moves the pointer by the phone's finger movement (CSS pixels). */
  fun remoteMove(dx: Float, dy: Float) {
    val web = remoteReady() ?: return
    val scale = resources.displayMetrics.density * 0.75f
    val margin = 2f
    cursorX = (cursorX + dx * scale).coerceIn(margin, (width - margin).coerceAtLeast(margin))
    cursorY = (cursorY + dy * scale).coerceIn(margin, (height - margin).coerceAtLeast(margin))
    placeCursor()
    hover(web)
  }

  /** Two-finger swipe on the phone: the page follows the fingers. */
  fun remoteScroll(dx: Float, dy: Float) {
    val web = remoteReady() ?: return
    // The page follows the fingers, like a touch screen.
    scrollBy(web, -dx * 1.5f, -dy * 1.5f)
  }

  /** The phone's D-pad buttons: like the remote's keys. */
  fun remoteKey(keyCode: Int) {
    val web = current ?: return
    val now = SystemClock.uptimeMillis()
    val down = KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0)
    val up = KeyEvent(now, now + 50, KeyEvent.ACTION_UP, keyCode, 0)
    // Straight to the page: the TV's own focus (toolbar or page) stays as it
    // is, and Up at the top doesn't jump to the toolbar.
    if (pointerMode) {
      handleRemoteKey(down)
      handleRemoteKey(up)
    } else {
      web.dispatchKeyEvent(down)
      web.dispatchKeyEvent(up)
    }
  }

  fun remoteTap() {
    val web = remoteReady() ?: return
    click(web)
  }

  private fun hover(web: WebView) {
    val now = SystemClock.uptimeMillis()
    val event = MotionEvent.obtain(now, now, MotionEvent.ACTION_HOVER_MOVE, cursorX, cursorY, 0)
    event.source = InputDevice.SOURCE_MOUSE
    web.dispatchGenericMotionEvent(event)
    event.recycle()
  }

  private fun click(web: WebView) {
    plugin.onPageTouched()
    // The WebView needs the focus for text fields to take typing.
    if (!web.hasFocus()) web.requestFocus()
    val now = SystemClock.uptimeMillis()
    val down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, cursorX, cursorY, 0)
    down.source = InputDevice.SOURCE_TOUCHSCREEN
    web.dispatchTouchEvent(down)
    down.recycle()
    val up = MotionEvent.obtain(now, now + 60, MotionEvent.ACTION_UP, cursorX, cursorY, 0)
    up.source = InputDevice.SOURCE_TOUCHSCREEN
    web.dispatchTouchEvent(up)
    up.recycle()
    cursor?.pulse()
  }

  /** Hands the keyboard focus back to the Flutter UI. */
  fun returnFocusToFlutter() {
    var parent = this.parent
    while (parent != null && parent !is FlutterView) parent = parent.parent
    findFocus()?.clearFocus()
    clearFocus()
    (parent as? View)?.requestFocus()
  }

  private class CursorView(context: Context) : View(context) {
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(200, 236, 72, 153) }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.WHITE
      style = Paint.Style.STROKE
      strokeWidth = 2f * context.resources.displayMetrics.density
    }
    private var x = 0f
    private var y = 0f
    private var pressed = 0L
    private val radius = 9f * context.resources.displayMetrics.density

    fun place(x: Float, y: Float) {
      this.x = x
      this.y = y
      invalidate()
    }

    fun pulse() {
      pressed = SystemClock.uptimeMillis()
      invalidate()
      postDelayed({ invalidate() }, 160)
    }

    override fun onDraw(canvas: Canvas) {
      val r = if (SystemClock.uptimeMillis() - pressed < 150) radius * 0.7f else radius
      canvas.drawCircle(x, y, r, fill)
      canvas.drawCircle(x, y, r, ring)
    }
  }
}
