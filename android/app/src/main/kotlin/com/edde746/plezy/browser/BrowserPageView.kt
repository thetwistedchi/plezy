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
    val shown = current != null && (hasFocus() || remoteActive)
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
    if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
      android.util.Log.d("PlezyBrowser", "page key ${event.keyCode} (page shown: ${current != null})")
    }
    val web = current
    if (!tv || web == null) return super.dispatchKeyEvent(event)
    val step = { if (event.repeatCount > 0) (24f + repeat * 4f).coerceAtMost(72f) else 24f }
    when (event.keyCode) {
      KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN -> {
        if (event.action != KeyEvent.ACTION_DOWN) return true
        repeat = if (event.repeatCount > 0) repeat + 1 else 0
        move(event.keyCode, step() * resources.displayMetrics.density / 2f)
        return true
      }
      KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_BUTTON_A -> {
        if (event.action == KeyEvent.ACTION_UP) click(web)
        return true
      }
    }
    return super.dispatchKeyEvent(event)
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

  /** A mouse wheel turn at the pointer: scrolls whatever is under it. */
  private fun scroll(web: WebView, x: Float, y: Float) = wheel(web, x * 2f, -y * 2f)

  /** [h] and [v] in wheel steps; positive [v] scrolls up. */
  private fun wheel(web: WebView, h: Float, v: Float) {
    val now = SystemClock.uptimeMillis()
    val props = MotionEvent.PointerProperties().apply {
      id = 0
      toolType = MotionEvent.TOOL_TYPE_MOUSE
    }
    val coords = MotionEvent.PointerCoords().apply {
      this.x = cursorX
      this.y = cursorY
      setAxisValue(MotionEvent.AXIS_VSCROLL, v)
      setAxisValue(MotionEvent.AXIS_HSCROLL, h)
    }
    val event = MotionEvent.obtain(
      now, now, MotionEvent.ACTION_SCROLL, 1, arrayOf(props), arrayOf(coords), 0, 0, 1f, 1f, 0, 0,
      InputDevice.SOURCE_MOUSE, 0,
    )
    web.dispatchGenericMotionEvent(event)
    event.recycle()
  }

  // ---- Phone remote (PhoneRemoteServer) ----

  private var remoteActive = false

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
    wheel(web, -dx / 24f, dy / 24f)
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
