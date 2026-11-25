package com.edde746.plezy

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Fork updater: hands a downloaded APK to Android's package installer, which
 * shows its own confirmation. If installing from this app is not yet allowed,
 * opens that setting instead and reports it, so the app can say what to do.
 */
internal class RetrowaveUpdateChannel(private val activity: Activity) {
  companion object {
    private const val CHANNEL = "com.thetwistedchi.plezyretrowave/update"
  }

  fun attach(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler(::onMethodCall)
  }

  private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      // Fork: asked before downloading, so a missing permission no longer
      // costs a whole download that then has to be started again.
      "canInstall" -> result.success(
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity.packageManager.canRequestPackageInstalls(),
      )
      "requestInstallPermission" -> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          activity.startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
              .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
          )
        }
        result.success(null)
      }
      "installApk" -> {
        val path = call.argument<String>("path")
        if (path == null) {
          result.error("ARG", "path missing", null)
          return
        }
        try {
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
          ) {
            activity.startActivity(
              Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            result.success("needsPermission")
            return
          }
          val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", File(path))
          val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
          }
          activity.startActivity(intent)
          result.success("started")
        } catch (e: Exception) {
          result.error("INSTALL", e.message, null)
        }
      }
      else -> result.notImplemented()
    }
  }
}
