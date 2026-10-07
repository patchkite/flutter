package io.github.patchkite.flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors

class PatchkitePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
  private lateinit var channel: MethodChannel
  private lateinit var progressChannel: EventChannel
  private lateinit var context: Context
  private var progressSink: EventChannel.EventSink? = null
  private val main = Handler(Looper.getMainLooper())
  private val executor = Executors.newSingleThreadExecutor()

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "patchkite")
    channel.setMethodCallHandler(this)
    progressChannel = EventChannel(binding.binaryMessenger, "patchkite/progress")
    progressChannel.setStreamHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    progressChannel.setStreamHandler(null)
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    progressSink = events
  }

  override fun onCancel(arguments: Any?) {
    progressSink = null
  }

  private fun JSONObject.toMap(): Map<String, Any?> = keys().asSequence().associateWith { k ->
    when (val v = get(k)) {
      JSONObject.NULL -> null
      else -> v
    }
  }

  private val core get() = PatchkiteCore.get(context)

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    executor.execute {
      try {
        val value: Any? = when (call.method) {
          "getConfiguration" -> mapOf(
            "appVersion" to core.appVersion,
            "deploymentKey" to core.deploymentKey,
            "serverUrl" to core.serverUrl,
            "clientUniqueId" to core.clientUniqueId,
            "publicKey" to core.publicKey,
            "engineRevision" to core.engineRevision,
          )
          "configure" -> {
            call.argument<String>("deploymentKey")?.let { core.deploymentKey = it }
            call.argument<String>("serverUrl")?.let { core.serverUrl = it }
            null
          }
          "getUpdateMetadata" -> core.getUpdateMetadata(call.argument<Int>("updateState") ?: 0)?.toMap()
          "downloadUpdate" -> {
            val pkg = JSONObject(call.arguments as Map<*, *>)
            core.downloadUpdate(pkg) { received, total ->
              main.post { progressSink?.success(mapOf("receivedBytes" to received, "totalBytes" to total)) }
            }.toMap()
          }
          "installUpdate" -> core.installUpdate(call.argument<String>("packageHash")!!).let { null }
          "isFailedUpdate" -> core.isFailedUpdate(call.argument<String>("packageHash")!!)
          "isFirstRun" -> core.isFirstRun(call.argument<String>("packageHash")!!)
          "notifyApplicationReady" -> core.notifyApplicationReady().let { null }
          "popRollbackReport" -> core.popRollbackReport()?.toMap()
          "getValue" -> core.getValue(call.argument<String>("key")!!)
          "setValue" -> core.setValue(call.argument<String>("key")!!, call.argument<String>("value")!!).let { null }
          "clearUpdates" -> core.clearUpdates().let { null }
          "restartApp" -> {
            main.post { Patchkite.restartProcess(context) }
            null
          }
          else -> {
            main.post { result.notImplemented() }
            return@execute
          }
        }
        main.post { result.success(value) }
      } catch (e: Exception) {
        PatchkiteUtils.log("Error: ${e.message}")
        main.post { result.error("PATCHKITE_ERROR", e.message, null) }
      }
    }
  }
}
