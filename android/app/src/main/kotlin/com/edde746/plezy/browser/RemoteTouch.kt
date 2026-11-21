package com.edde746.plezy.browser

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout

/**
 * The phone remote's touchpad for the whole screen: a pointer drawn over
 * the app, and touches (taps, drags for scrolling) sent to the activity at
 * its position. So it works on websites and on the app's own screens alike.
 */
internal class RemoteTouch(private val activity: () -> Activity?) {
  private val main = Handler(Looper.getMainLooper())
  private var cursor: CursorView? = null
  private var x = -1f
  private var y = -1f

  // A two-finger swipe on the phone is a one-finger drag on the TV.
  private var dragDown = 0L
  private var dragX = 0f
  private var dragY = 0f
  private val endDrag = Runnable { finishDrag() }
  private val hide = Runnable { cursor?.visibility = View.GONE }

  private fun ready(): Pair<Activity, CursorView>? {
    val activity = activity() ?: return null
    val decor = activity.window?.decorView as? ViewGroup ?: return null
    var view = cursor
    if (view == null || view.parent !== decor) {
      (view?.parent as? ViewGroup)?.removeView(view)
      view = CursorView(activity)
      decor.addView(view, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
      cursor = view
    }
    if (x < 0 || x > decor.width || y > decor.height) {
      x = decor.width / 2f
      y = decor.height / 2f
    }
    view.visibility = View.VISIBLE
    view.bringToFront()
    main.removeCallbacks(hide)
    main.postDelayed(hide, 6000)
    return activity to view
  }

  /** Moves the pointer by the phone's finger movement (CSS pixels). */
  fun move(dx: Float, dy: Float) {
    val (activity, view) = ready() ?: return
    val decor = activity.window.decorView
    val scale = activity.resources.displayMetrics.density * 0.75f
    x = (x + dx * scale).coerceIn(0f, (decor.width - 1).toFloat().coerceAtLeast(0f))
    y = (y + dy * scale).coerceIn(0f, (decor.height - 1).toFloat().coerceAtLeast(0f))
    view.place(x, y)
  }

  fun tap() {
    val (activity, view) = ready() ?: return
    finishDrag()
    val now = SystemClock.uptimeMillis()
    send(activity, now, now, MotionEvent.ACTION_DOWN, x, y)
    send(activity, now, now + 60, MotionEvent.ACTION_UP, x, y)
    view.pulse()
  }

  /** The content follows the fingers, like a touch screen. */
  fun scroll(dx: Float, dy: Float) {
    val (activity, view) = ready() ?: return
    view.place(x, y)
    val scale = activity.resources.displayMetrics.density * 1.2f
    val now = SystemClock.uptimeMillis()
    if (dragDown == 0L) {
      dragDown = now
      dragX = x
      dragY = y
      send(activity, now, now, MotionEvent.ACTION_DOWN, dragX, dragY)
    }
    dragX += dx * scale
    dragY += dy * scale
    send(activity, dragDown, now, MotionEvent.ACTION_MOVE, dragX, dragY)
    main.removeCallbacks(endDrag)
    main.postDelayed(endDrag, 180)
  }

  private fun finishDrag() {
    main.removeCallbacks(endDrag)
    if (dragDown == 0L) return
    val activity = activity()
    if (activity != null) send(activity, dragDown, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP, dragX, dragY)
    dragDown = 0L
  }

  fun dispose() {
    finishDrag()
    main.removeCallbacks(hide)
    (cursor?.parent as? ViewGroup)?.removeView(cursor)
    cursor = null
  }

  private fun send(activity: Activity, down: Long, time: Long, action: Int, x: Float, y: Float) {
    val event = MotionEvent.obtain(down, time, action, x, y, 0)
    event.source = InputDevice.SOURCE_TOUCHSCREEN
    activity.dispatchTouchEvent(event)
    event.recycle()
  }

  @SuppressLint("ViewConstructor")
  private class CursorView(context: Context) : View(context) {
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(210, 236, 72, 153) }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.WHITE
      style = Paint.Style.STROKE
      strokeWidth = 2f * context.resources.displayMetrics.density
    }
    private val radius = 9f * context.resources.displayMetrics.density
    private var cx = 0f
    private var cy = 0f
    private var pressed = 0L

    init {
      isClickable = false
      isFocusable = false
      importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    // Never takes the touches it points at.
    override fun onTouchEvent(event: MotionEvent?) = false

    fun place(x: Float, y: Float) {
      cx = x
      cy = y
      invalidate()
    }

    fun pulse() {
      pressed = SystemClock.uptimeMillis()
      invalidate()
      postDelayed({ invalidate() }, 160)
    }

    override fun onDraw(canvas: Canvas) {
      val r = if (SystemClock.uptimeMillis() - pressed < 150) radius * 0.7f else radius
      canvas.drawCircle(cx, cy, r, fill)
      canvas.drawCircle(cx, cy, r, ring)
    }
  }
}
