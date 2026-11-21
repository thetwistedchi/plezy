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
    const val UNCHANGED = "(()=>{const p=window.__plezyKeySnap;if(!p)return false;const s=[];" +
      "const d=document.scrollingElement||document.documentElement;s.push(d.scrollTop);" +
      "const m=window.__plezyScroller;if(m&&m.isConnected)s.push(m.scrollTop);" +
      "return p.a===document.activeElement&&p.s===s.join(',');})()"
  }
  private var lastUpAtTop = 0L
  private var okLong = false

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

  fun focusPage() {
    val ok = requestFocus()
    android.util.Log.d("PlezyBrowser", "page focus requested: $ok")
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
    if (ok && event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) okLong = false
    if (ok && event.action == KeyEvent.ACTION_DOWN && event.repeatCount > 0) {
      if (!okLong && event.eventTime - event.downTime >= 700) {
        okLong = true
        plugin.onTogglePointer()
      }
      return true
    }
    if (ok && event.action == KeyEvent.ACTION_UP && okLong) {
      okLong = false
      if (!pointerMode) web.dispatchKeyEvent(KeyEvent.changeFlags(event, event.flags or KeyEvent.FLAG_CANCELED))
      return true
    }
    if (!pointerMode) return selectKey(web, event)
    when (event.keyCode) {
      KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN -> {
        if (event.action != KeyEvent.ACTION_DOWN) return true
        // A press moves a small step (about 1/80 of the screen) for detail;
        // holding the key speeds it up to about 1/12.
        repeat = if (event.repeatCount > 0) (repeat + 1).coerceAtMost(20) else 0
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
    if (vertical && event.action == KeyEvent.ACTION_DOWN) {
      web.evaluateJavascript(SNAPSHOT, null)
    }
    val handled = web.dispatchKeyEvent(event)
    if (vertical && event.action == KeyEvent.ACTION_DOWN) {
      // Pages that scroll inside an element: when the key neither moved
      // the selection nor scrolled anything, the page is scrolled here.
      val down = event.keyCode == KeyEvent.KEYCODE_DPAD_DOWN
      postDelayed({
        web.evaluateJavascript(UNCHANGED) { value ->
          if (value == "true") touchScroll(web, 0f, (if (down) 1 else -1) * height * 0.3f)
        }
      }, 150)
    }
    if (event.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_DPAD_UP) {
      val now = SystemClock.uptimeMillis()
      // The page itself at the top (fields and inner scroll areas may still
      // take Up): a second quick Up goes back to the toolbar.
      val atTop = web.scrollY <= 0 || !web.canScrollVertically(-1)
      if (!handled || (atTop && lastUpAtTop != 0L && now - lastUpAtTop < 700)) {
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
    touchScroll(web, x * step, y * step)
  }

  /**
   * Scrolls like a finger: a short drag at the pointer (or the middle),
   * held still before lifting so it does not fling. Works wherever touch
   * scrolling works, inner scroll areas included. [dx], [dy] in view
   * pixels; positive [dy] shows more of the page below.
   */
  private fun touchScroll(web: WebView, dx: Float, dy: Float) {
    val startX = if (cursorX >= 0) cursorX else width / 2f
    val startY = if (cursorY >= 0) cursorY else height / 2f
    // Keep the drag on screen: start where there is room for it.
    val fromY = (startY + dy / 2f).coerceIn(height * 0.1f, height * 0.9f)
    val fromX = (startX + dx / 2f).coerceIn(width * 0.1f, width * 0.9f)
    val t0 = SystemClock.uptimeMillis()
    fun send(action: Int, time: Long, x: Float, y: Float) {
      val event = MotionEvent.obtain(t0, time, action, x, y, 0)
      event.source = InputDevice.SOURCE_TOUCHSCREEN
      web.dispatchTouchEvent(event)
      event.recycle()
    }
    send(MotionEvent.ACTION_DOWN, t0, fromX, fromY)
    val steps = 6
    for (i in 1..steps) {
      send(MotionEvent.ACTION_MOVE, t0 + i * 16L, fromX - dx * i / steps, fromY - dy * i / steps)
    }
    send(MotionEvent.ACTION_MOVE, t0 + steps * 16L + 200, fromX - dx, fromY - dy)
    send(MotionEvent.ACTION_UP, t0 + steps * 16L + 220, fromX - dx, fromY - dy)
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
