package com.edde746.plezy.browser

import android.content.Context
import android.util.Log
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.security.SecureRandom
import org.json.JSONArray
import org.json.JSONObject

/**
 * The browser's phone remote: a small web server in the local network. The
 * QR code on the TV holds its address with a random key; the first phone
 * that opens it is the only one accepted until the remote is stopped.
 * Events from the phone's page (assets/browser_remote.html) go to
 * [onEvents] on a server thread.
 */
internal class PhoneRemoteServer(
  private val context: Context,
  private val onEvents: (JSONArray) -> Unit,
  private val state: () -> JSONObject,
) {
  companion object {
    private const val TAG = "PlezyBrowser"
    private val PORTS = 8790..8799
    private const val IDLE_MS = 30 * 60 * 1000L
  }

  private var server: ServerSocket? = null
  private var key = ""
  @Volatile private var client: String? = null
  @Volatile private var lastUse = 0L
  @Volatile var onConnected: (() -> Unit)? = null

  val running get() = server != null

  /** Starts the server (or keeps it) and returns the address for the QR code; null without a network. */
  @Synchronized
  fun start(): String? {
    val ip = localAddress() ?: return null
    server?.let { return url(ip, it.localPort) }
    val bytes = ByteArray(12).also { SecureRandom().nextBytes(it) }
    key = bytes.joinToString("") { "%02x".format(it) }
    client = null
    lastUse = System.currentTimeMillis()
    var socket: ServerSocket? = null
    for (port in PORTS) {
      try {
        socket = ServerSocket().apply {
          reuseAddress = true
          bind(InetSocketAddress(port))
        }
        break
      } catch (_: Exception) {
      }
    }
    val bound = socket ?: return null
    server = bound
    Thread({ accept(bound) }, "plezy-remote").apply { isDaemon = true }.start()
    // Stops by itself after [IDLE_MS] without use, checked every minute.
    idleTimer?.cancel()
    idleTimer = java.util.Timer("plezy-remote-idle", true).apply {
      schedule(object : java.util.TimerTask() {
        override fun run() {
          if (System.currentTimeMillis() - lastUse > IDLE_MS) {
            Log.i(TAG, "Phone remote: idle, stopping")
            stop()
          }
        }
      }, 60_000, 60_000)
    }
    Log.i(TAG, "Phone remote listening on port ${bound.localPort}")
    return url(ip, bound.localPort)
  }

  private var idleTimer: java.util.Timer? = null

  @Synchronized
  fun stop() {
    idleTimer?.cancel()
    idleTimer = null
    try {
      server?.close()
    } catch (_: Exception) {
    }
    if (server != null) Log.i(TAG, "Phone remote stopped")
    server = null
    client = null
  }

  private fun url(ip: String, port: Int) = "http://$ip:$port/?k=$key"

  /** The device's IPv4 address in the local network (Ethernet or Wi-Fi). */
  private fun localAddress(): String? = try {
    NetworkInterface.getNetworkInterfaces().toList()
      .filter { it.isUp && !it.isLoopback && !it.isVirtual }
      .sortedBy { if (it.name.startsWith("eth")) 0 else if (it.name.startsWith("wlan")) 1 else 2 }
      .flatMap { it.inetAddresses.toList() }
      .firstOrNull { it is Inet4Address && it.isSiteLocalAddress }
      ?.hostAddress
  } catch (_: Exception) {
    null
  }

  private fun accept(socket: ServerSocket) {
    while (!socket.isClosed) {
      val connection = try {
        socket.accept()
      } catch (_: Exception) {
        break
      }
      if (System.currentTimeMillis() - lastUse > IDLE_MS) {
        connection.close()
        stop()
        break
      }
      Thread({ serve(connection) }, "plezy-remote-conn").apply { isDaemon = true }.start()
    }
  }

  private fun serve(connection: Socket) {
    connection.use { s ->
      s.soTimeout = 60_000
      s.tcpNoDelay = true
      val input = BufferedInputStream(s.getInputStream())
      val output = s.getOutputStream()
      val remote = s.inetAddress.hostAddress ?: ""
      try {
        while (true) {
          val request = readRequest(input) ?: break
          handle(request, remote, output)
          if (request.headers["connection"]?.lowercase() == "close") break
        }
      } catch (_: SocketTimeoutException) {
      } catch (e: Exception) {
        Log.d(TAG, "remote connection: $e")
      }
    }
  }

  private class Request(val method: String, val path: String, val query: Map<String, String>, val headers: Map<String, String>, val body: ByteArray)

  private fun readLine(input: InputStream): String? {
    val out = ByteArrayOutputStream()
    while (true) {
      val b = input.read()
      if (b < 0) return if (out.size() == 0) null else out.toString("UTF-8")
      if (b == '\n'.code) return out.toString("UTF-8").trimEnd('\r')
      out.write(b)
      if (out.size() > 8192) return null
    }
  }

  private fun readRequest(input: InputStream): Request? {
    val line = readLine(input) ?: return null
    val parts = line.split(' ')
    if (parts.size < 2) return null
    val headers = HashMap<String, String>()
    while (true) {
      val header = readLine(input) ?: return null
      if (header.isEmpty()) break
      val colon = header.indexOf(':')
      if (colon > 0) headers[header.substring(0, colon).trim().lowercase()] = header.substring(colon + 1).trim()
    }
    val length = headers["content-length"]?.toIntOrNull()?.coerceIn(0, 256 * 1024) ?: 0
    val body = ByteArray(length)
    var read = 0
    while (read < length) {
      val n = input.read(body, read, length - read)
      if (n < 0) return null
      read += n
    }
    val target = parts[1]
    val q = target.indexOf('?')
    val path = if (q >= 0) target.substring(0, q) else target
    val query = HashMap<String, String>()
    if (q >= 0) {
      for (pair in target.substring(q + 1).split('&')) {
        val eq = pair.indexOf('=')
        if (eq > 0) query[pair.substring(0, eq)] = java.net.URLDecoder.decode(pair.substring(eq + 1), "UTF-8")
      }
    }
    return Request(parts[0], path, query, headers, body)
  }

  private fun respond(output: OutputStream, status: Int, type: String, body: ByteArray) {
    val reason = when (status) {
      200 -> "OK"
      204 -> "No Content"
      403 -> "Forbidden"
      else -> "Not Found"
    }
    val head = "HTTP/1.1 $status $reason\r\nContent-Type: $type\r\nContent-Length: ${body.size}\r\n" +
      "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n" +
      "Connection: keep-alive\r\n\r\n"
    output.write(head.toByteArray())
    output.write(body)
    output.flush()
  }

  /** The right key, from the one phone that connected first. */
  private fun allowed(request: Request, remote: String): Boolean {
    if (key.isEmpty() || request.query["k"] != key) return false
    val bound = client
    if (bound == null) {
      synchronized(this) {
        if (client == null) {
          client = remote
          Log.i(TAG, "Phone remote connected")
          onConnected?.invoke()
        }
      }
    }
    return client == remote
  }

  private fun handle(request: Request, remote: String, output: OutputStream) {
    if (!allowed(request, remote)) {
      respond(output, 403, "text/plain; charset=utf-8", "Forbidden".toByteArray())
      return
    }
    lastUse = System.currentTimeMillis()
    when {
      request.method == "GET" && request.path == "/" -> {
        val html = context.assets.open("browser_remote.html").use { it.readBytes() }
        respond(output, 200, "text/html; charset=utf-8", html)
      }
      request.method == "POST" && request.path == "/e" -> {
        try {
          onEvents(JSONArray(String(request.body, Charsets.UTF_8)))
        } catch (e: Exception) {
          Log.d(TAG, "remote events: $e")
        }
        respond(output, 204, "text/plain", ByteArray(0))
      }
      request.method == "GET" && request.path == "/s" -> {
        respond(output, 200, "application/json", state().toString().toByteArray())
      }
      else -> respond(output, 404, "text/plain", "Not found".toByteArray())
    }
  }
}
