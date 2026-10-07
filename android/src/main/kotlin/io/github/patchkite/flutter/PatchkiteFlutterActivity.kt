package io.github.patchkite.flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterFragmentActivity
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs

/**
 * Replace `FlutterActivity` in your MainActivity with this class:
 *
 * ```kotlin
 * class MainActivity : PatchkiteFlutterActivity()
 * ```
 */
open class PatchkiteFlutterActivity : FlutterActivity() {
  override fun getFlutterShellArgs(): FlutterShellArgs {
    val args = super.getFlutterShellArgs()
    Patchkite.shellArgs(applicationContext).forEach { args.add(it) }
    return args
  }
}

/**
 * Variant for apps that use `FlutterFragmentActivity`. The engine is created once per
 * process with the Patchkite shell args and then reused by the activity.
 */
open class PatchkiteFlutterFragmentActivity : FlutterFragmentActivity() {
  companion object {
    private var engine: FlutterEngine? = null
  }

  override fun provideFlutterEngine(context: Context): FlutterEngine =
    engine ?: FlutterEngine(context.applicationContext, Patchkite.shellArgs(context).toTypedArray()).also { engine = it }
}
