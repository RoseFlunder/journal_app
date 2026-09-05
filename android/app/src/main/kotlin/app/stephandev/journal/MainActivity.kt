package app.stephandev.journal

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        // Keep staging and the current subscriber alive across Activity recreation.
        private var incomingSink: EventChannel.EventSink? = null
        private val worker = Executors.newSingleThreadExecutor()
        private val errors = linkedMapOf<String, Map<String, String>>()
    }
    private var consumedLaunch = false
    private val incomingDirectory: File get() = File(cacheDir, "cozy-incoming")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "app.stephandev.journal/incoming")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    incomingSink = events
                    incomingDirectory.listFiles()
                        ?.filter { it.extension == "cozyjournal" }
                        ?.sortedBy { it.lastModified() }
                        ?.forEach { events.success(delivery(it)) }
                    errors.values.forEach { events.success(it) }
                }
                override fun onCancel(arguments: Any?) { incomingSink = null }
            })
        MethodChannel(messenger, "app.stephandev.journal/files")
            .setMethodCallHandler { call, result ->
                if (call.method == "isAvailable") {
                    result.success(true)
                } else if (call.method != "acknowledge") {
                    result.notImplemented()
                } else {
                    val id = call.arguments as? String
                    if (id == null || !id.matches(Regex("[a-f0-9-]{36}"))) {
                        result.error("invalid_id", "Invalid delivery", null)
                    } else {
                        errors.remove(id)
                        val file = File(incomingDirectory, "$id.cozyjournal")
                        if (file.exists() && !file.delete()) {
                            result.error("cleanup_failed", "Could not remove delivery", null)
                        } else {
                            result.success(null)
                        }
                    }
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        consumedLaunch = savedInstanceState?.getBoolean("cozyLaunchConsumed") ?: false
        if (!consumedLaunch) {
            consumedLaunch = true
            stageIntent(intent)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("cozyLaunchConsumed", consumedLaunch)
        super.onSaveInstanceState(outState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumedLaunch = true
        stageIntent(intent)
    }

    @Suppress("DEPRECATION")
    private fun stageIntent(intent: Intent?) {
        val uri: Uri? = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
                ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
            else -> return
        }
        val id = UUID.randomUUID().toString()
        worker.execute {
            val folder = incomingDirectory
            folder.mkdirs()
            val partial = File(folder, "$id.partial")
            try {
                require(uri != null && (uri.scheme == "content" || uri.scheme == "file"))
                require((folder.listFiles()?.count { it.extension == "cozyjournal" } ?: 0) < 8)
                contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input)
                    partial.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var total = 0L
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            total += count
                            require(total <= 544L * 1024 * 1024)
                            output.write(buffer, 0, count)
                        }
                    }
                }
                val file = File(folder, "$id.cozyjournal")
                check(partial.renameTo(file))
                runOnUiThread { incomingSink?.success(delivery(file)) }
            } catch (_: Exception) {
                partial.delete()
                runOnUiThread {
                    val error = mapOf("id" to id, "error" to "Could not read shared page")
                    errors[id] = error
                    incomingSink?.success(error)
                }
            }
        }
    }

    private fun delivery(file: File): Map<String, String> =
        mapOf("id" to file.nameWithoutExtension, "path" to file.absolutePath)

    override fun onDestroy() {
        incomingSink = null
        super.onDestroy()
    }
}
