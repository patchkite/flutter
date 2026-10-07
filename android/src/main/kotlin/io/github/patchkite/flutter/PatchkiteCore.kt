package io.github.patchkite.flutter

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/**
 * Update state is stored in `filesDir/Patchkite`:
 *   status.json              → current/previous/pending/failed/kv
 *   <hash>/content/lib/<abi>/libapp.so → updated AOT Dart code
 *   <hash>/meta.json         → package metadata
 */
internal class PatchkiteCore private constructor(private val context: Context) {
  companion object {
    @Volatile private var instance: PatchkiteCore? = null
    fun get(context: Context): PatchkiteCore =
      instance ?: synchronized(this) { instance ?: PatchkiteCore(context.applicationContext).also { instance = it } }

    const val LIBAPP = "libapp.so"
    private const val MAX_FAILED = 20
  }

  private val root = File(context.filesDir, "Patchkite")
  private val statusFile = File(root, "status.json")
  private var status: JSONObject = loadStatus()

  /** Hash of the currently running package (null = binary). */
  @Volatile var runningHash: String? = null
    private set
  @Volatile private var firstRunHash: String? = null
  /** Engine revision of this binary (set when the plugin is built). */
  val engineRevision: String = BuildConfig.PATCHKITE_ENGINE_REVISION

  // ------------------------------------------------------------ configuration

  /** Configuration from strings.xml or `<meta-data>` in AndroidManifest. */
  private fun stringResource(name: String): String? {
    val id = context.resources.getIdentifier(name, "string", context.packageName)
    if (id != 0) context.getString(id).takeIf { it.isNotBlank() }?.let { return it }
    val appInfo = @Suppress("DEPRECATION") context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
    return appInfo.metaData?.getString(name)?.takeIf { it.isNotBlank() }
  }

  val appVersion: String by lazy {
    val info = if (Build.VERSION.SDK_INT >= 33) context.packageManager.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(0))
    else @Suppress("DEPRECATION") context.packageManager.getPackageInfo(context.packageName, 0)
    info.versionName ?: "1.0.0"
  }

  private val binaryId: String by lazy {
    val info = @Suppress("DEPRECATION") context.packageManager.getPackageInfo(context.packageName, 0)
    "${info.versionName}-${info.lastUpdateTime}"
  }

  var deploymentKey: String? = null
    get() = field ?: stringResource("PatchkiteDeploymentKey")
  var serverUrl: String? = null
    get() = field ?: stringResource("PatchkiteServerUrl") ?: stringResource("PatchkiteServerURL")
  val publicKey: String? get() = stringResource("PatchkitePublicKey")

  val clientUniqueId: String
    get() = synchronized(this) {
      status.optString("clientId").ifEmpty { UUID.randomUUID().toString().also { status.put("clientId", it); saveStatus() } }
    }

  // ------------------------------------------------------------ status

  private fun loadStatus(): JSONObject = try {
    if (statusFile.exists()) JSONObject(statusFile.readText()) else JSONObject()
  } catch (e: Exception) {
    PatchkiteUtils.log("status.json is corrupted, resetting: ${e.message}")
    JSONObject()
  }

  @Synchronized private fun saveStatus() {
    root.mkdirs()
    val tmp = File(root, "status.json.tmp")
    tmp.writeText(status.toString())
    tmp.renameTo(statusFile)
  }

  private fun packageDir(hash: String) = File(root, hash)
  private fun contentDir(hash: String) = File(packageDir(hash), "content")
  private fun metaOf(hash: String?): JSONObject? = hash?.let {
    val f = File(packageDir(it), "meta.json")
    if (f.exists()) JSONObject(f.readText()) else null
  }

  private fun currentHash() = status.optString("current").ifEmpty { null }
  private fun previousHash() = status.optString("previous").ifEmpty { null }
  private fun pending() = status.optJSONObject("pending")

  /**
   * Called on app start / reload to determine which bundle to run.
   * Handles auto-rollback when the previous update crashed before `notifyAppReady`.
   */
  @Synchronized fun resolveBundlePath(): String? {
    if (status.optString("binaryId") != binaryId) {
      if (status.has("binaryId")) PatchkiteUtils.log("New binary detected, removing old updates.")
      val clientId = status.optString("clientId")
      root.deleteRecursively()
      status = JSONObject().put("binaryId", binaryId)
      if (clientId.isNotEmpty()) status.put("clientId", clientId)
      saveStatus()
    }

    pending()?.let { p ->
      val hash = p.getString("hash")
      if (p.optBoolean("isLoading")) {
        PatchkiteUtils.log("Update $hash failed to run (notifyAppReady was not called). Rolling back.")
        rollback(hash)
      } else {
        p.put("isLoading", true)
        firstRunHash = hash
        saveStatus()
      }
    }

    val current = currentHash()
    if (current != null) {
      val meta = metaOf(current)
      val bundle = meta?.optString("bundlePath")?.let { File(contentDir(current), it) }
      if (bundle != null && bundle.isFile) {
        runningHash = current
        cleanup()
        return bundle.absolutePath
      }
      PatchkiteUtils.log("Update bundle $current not found, falling back to the binary.")
      status.remove("current")
      saveStatus()
    }
    runningHash = null
    cleanup()
    return null
  }

  private fun rollback(failedHash: String) {
    val failed = status.optJSONArray("failed") ?: JSONArray()
    failed.put(failedHash)
    while (failed.length() > MAX_FAILED) failed.remove(0)
    status.put("failed", failed)
    metaOf(failedHash)?.let { status.put("rollbackReport", it) }
    val previous = previousHash()
    if (previous != null && previous != failedHash) status.put("current", previous) else status.remove("current")
    status.remove("previous")
    status.remove("pending")
    saveStatus()
  }

  /** Deletes package folders that are no longer in use. */
  private fun cleanup() {
    val keep = setOfNotNull(currentHash(), previousHash(), runningHash, pending()?.optString("hash"))
    root.listFiles()?.filter { it.isDirectory && it.name !in keep && !it.name.startsWith("download") }?.forEach { it.deleteRecursively() }
  }

  @Synchronized fun notifyApplicationReady() {
    if (pending() != null && pending()!!.optBoolean("isLoading")) {
      status.remove("pending")
      saveStatus()
    }
  }

  @Synchronized fun isFailedUpdate(hash: String): Boolean {
    val failed = status.optJSONArray("failed") ?: return false
    return (0 until failed.length()).any { failed.getString(it) == hash }
  }

  fun isFirstRun(hash: String) = firstRunHash == hash && runningHash == hash

  @Synchronized fun popRollbackReport(): JSONObject? =
    status.optJSONObject("rollbackReport")?.also { status.remove("rollbackReport"); saveStatus() }

  @Synchronized fun getValue(key: String): String? = status.optJSONObject("kv")?.optString(key)?.ifEmpty { null }

  @Synchronized fun setValue(key: String, value: String) {
    val kv = status.optJSONObject("kv") ?: JSONObject().also { status.put("kv", it) }
    kv.put(key, value)
    saveStatus()
  }

  /** 0 = RUNNING, 1 = PENDING, 2 = LATEST */
  @Synchronized fun getUpdateMetadata(state: Int): JSONObject? {
    val p = pending()
    val pendingHash = if (p != null && !p.optBoolean("isLoading")) p.getString("hash") else null
    val hash = when (state) {
      0 -> runningHash
      1 -> pendingHash
      else -> pendingHash ?: runningHash
    } ?: return null
    return metaOf(hash)?.put("isPending", hash == pendingHash)
  }

  @Synchronized fun installUpdate(hash: String) {
    require(metaOf(hash) != null) { "Package $hash has not been downloaded" }
    val current = currentHash()
    if (current != hash) {
      // Keep the currently running package as the rollback target.
      val base = runningHash ?: current
      if (base != null) status.put("previous", base) else status.remove("previous")
      status.put("current", hash)
    }
    status.put("pending", JSONObject().put("hash", hash).put("isLoading", false))
    saveStatus()
  }

  @Synchronized fun clearUpdates() {
    status.remove("current")
    status.remove("previous")
    status.remove("pending")
    saveStatus()
  }

  // ------------------------------------------------------------ download

  fun downloadUpdate(pkg: JSONObject, onProgress: (Long, Long) -> Unit): JSONObject {
    val hash = pkg.getString("packageHash")
    val downloadDir = File(root, "download-${UUID.randomUUID()}")
    downloadDir.mkdirs()
    try {
      val zip = File(downloadDir, "package.zip")
      download(pkg.getString("downloadUrl"), zip, onProgress)
      if (!PatchkiteUtils.isZip(zip)) throw IllegalStateException("Downloaded file is not a zip")

      val unzipped = File(downloadDir, "unzipped")
      PatchkiteUtils.unzip(zip, unzipped)
      val target = contentDir(hash)
      packageDir(hash).deleteRecursively()
      target.parentFile!!.mkdirs()

      val diffManifest = File(unzipped, PatchkiteUtils.DIFF_MANIFEST_FILE)
      if (diffManifest.exists()) {
        // Diff update: copy the currently running package, then apply the changes.
        val base = runningHash ?: currentHash() ?: throw IllegalStateException("Diff update without a base package")
        contentDir(base).copyRecursively(target, overwrite = true)
        val diffInfo = JSONObject(diffManifest.readText())
        val deleted = diffInfo.optJSONArray("deletedFiles") ?: JSONArray()
        for (i in 0 until deleted.length()) PatchkiteUtils.childOf(target, deleted.getString(i))?.delete()
        File(target, PatchkiteUtils.SIGNATURE_FILE).delete()
        diffManifest.delete()
        // Binary patch: new file = bspatch(same file in the base package, patch from the server).
        val patched = diffInfo.optJSONArray("patchedFiles") ?: JSONArray()
        val patchDir = File(unzipped, PatchkiteUtils.PATCH_DIR)
        for (i in 0 until patched.length()) {
          val rel = patched.getString(i)
          val old = PatchkiteUtils.childOf(target, rel) ?: throw SecurityException("Invalid patch path: $rel")
          val patch = PatchkiteUtils.childOf(patchDir, rel) ?: throw SecurityException("Invalid patch path: $rel")
          val out = PatchkiteUtils.childOf(unzipped, rel) ?: throw SecurityException("Invalid patch path: $rel")
          out.parentFile?.mkdirs()
          PatchkiteUtils.bspatch(old, patch, out)
        }
        patchDir.deleteRecursively()
        unzipped.copyRecursively(target, overwrite = true)
      } else {
        if (!unzipped.renameTo(target)) unzipped.copyRecursively(target, overwrite = true)
      }

      PatchkiteUtils.pruneUnverified(target)
      val computed = PatchkiteUtils.computePackageHash(target)
      if (computed != hash) throw IllegalStateException("Package hash mismatch (expected $hash, got $computed)")

      val key = publicKey
      val signature = File(target, PatchkiteUtils.SIGNATURE_FILE)
      if (key != null) {
        if (!signature.exists()) throw SecurityException("Code signing is enabled but the package is not signed")
        val claimed = PatchkiteUtils.verifySignature(signature.readText(), key)
        if (claimed != computed) throw SecurityException("contentHash in the signature does not match")
        PatchkiteUtils.log("Package signature is valid.")
      } else if (signature.exists()) {
        PatchkiteUtils.log("Package is signed but PatchkitePublicKey is not set; skipping verification.")
      }

      val bundle = Build.SUPPORTED_ABIS.asSequence()
        .map { File(target, "lib/$it/$LIBAPP") }
        .firstOrNull { it.isFile }
        ?: throw IllegalStateException("$LIBAPP for ABI ${Build.SUPPORTED_ABIS.joinToString()} not found in package")
      // Android 14+: dynamically loaded code files must be read-only.
      bundle.setReadOnly()
      val meta = JSONObject()
        .put("label", pkg.optString("label"))
        .put("appVersion", pkg.optString("appVersion", appVersion))
        .put("description", pkg.optString("description"))
        .put("isMandatory", pkg.optBoolean("isMandatory"))
        .put("packageHash", hash)
        .put("packageSize", pkg.optLong("packageSize"))
        .put("deploymentKey", pkg.optString("deploymentKey"))
        .put("bundlePath", bundle.relativeTo(target).invariantSeparatorsPath)
        .put("engineRevision", engineRevision)
        .put("downloadTime", System.currentTimeMillis())
      File(packageDir(hash), "meta.json").writeText(meta.toString())
      return meta
    } catch (e: Exception) {
      packageDir(hash).takeIf { it.exists() && metaOf(hash) == null }?.deleteRecursively()
      throw e
    } finally {
      downloadDir.deleteRecursively()
    }
  }

  private fun download(url: String, dest: File, onProgress: (Long, Long) -> Unit) {
    var current = URL(url)
    var conn: HttpURLConnection
    var redirects = 0
    while (true) {
      conn = current.openConnection() as HttpURLConnection
      conn.instanceFollowRedirects = false
      conn.connectTimeout = 15_000
      conn.readTimeout = 60_000
      val code = conn.responseCode
      if (code in 300..399 && redirects < 5) {
        current = URL(current, conn.getHeaderField("Location"))
        conn.disconnect()
        redirects++
        continue
      }
      if (code !in 200..299) throw IllegalStateException("Download failed: HTTP $code")
      break
    }
    val total = conn.contentLengthLong
    var received = 0L
    var lastEmit = 0L
    conn.inputStream.use { input ->
      FileOutputStream(dest).use { out ->
        val buf = ByteArray(64 * 1024)
        while (true) {
          val n = input.read(buf)
          if (n < 0) break
          out.write(buf, 0, n)
          received += n
          val now = System.currentTimeMillis()
          if (now - lastEmit > 100) {
            onProgress(received, total)
            lastEmit = now
          }
        }
      }
    }
    onProgress(received, if (total > 0) total else received)
    conn.disconnect()
  }
}
