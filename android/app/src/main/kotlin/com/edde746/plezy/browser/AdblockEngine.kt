package com.edde746.plezy.browser

import android.util.Log

/**
 * Brave's adblock-rust engine (windows/runner/adblock, src/jni.rs), the same
 * code as the Windows browser uses. [available] is false when the library is
 * missing from this build (an ABI it was not built for).
 */
internal object AdblockEngine {
  val available: Boolean = try {
    System.loadLibrary("plezy_adblock")
    true
  } catch (e: Throwable) {
    Log.w("PlezyBrowser", "Ad block engine not available: $e")
    false
  }

  /** Builds an engine from the app's config JSON; 0 on failure. Slow: off the main thread. */
  @JvmStatic external fun load(config: String): Long

  @JvmStatic external fun free(engine: Long)

  /** null = allow, "" = block, else a data: URL to answer with. Thread-safe. */
  @JvmStatic external fun check(engine: Long, url: String, source: String, type: String): String?

  /** `{"script":..,"exceptions":"[..]","generichide":bool}` for the page at [url]. */
  @JvmStatic external fun pageScript(engine: Long, url: String): String?

  /** Generic hiding rules for the classes and ids a page reported, as a script. */
  @JvmStatic external fun genericScript(engine: Long, query: String, exceptions: String): String?
}
