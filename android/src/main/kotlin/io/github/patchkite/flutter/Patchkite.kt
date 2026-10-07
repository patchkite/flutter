package io.github.patchkite.flutter

import android.content.Context
import android.content.Intent
import kotlin.system.exitProcess

/** Public native Android API. */
object Patchkite {
  /**
   * Path to the updated `libapp.so`, or null to use the Dart code bundled in the APK.
   * Called once per process before the Flutter engine is created.
   */
  @JvmStatic
  fun getLibAppPath(context: Context): String? {
    val core = PatchkiteCore.get(context)
    val path = core.resolveBundlePath()
    PatchkiteUtils.log(if (path != null) "Running update: $path" else "Running the Dart code bundled in the binary.")
    return path
  }

  /** Shell args for the Flutter engine (used by [PatchkiteFlutterActivity]). */
  @JvmStatic
  fun shellArgs(context: Context): List<String> =
    getLibAppPath(context)?.let { listOf("--aot-shared-library-name=$it") } ?: emptyList()

  /** AOT Dart code cannot be replaced in-process → restart the process. */
  internal fun restartProcess(context: Context) {
    val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
    val intent = Intent.makeRestartActivityTask(launch.component)
    context.startActivity(intent)
    exitProcess(0)
  }
}
