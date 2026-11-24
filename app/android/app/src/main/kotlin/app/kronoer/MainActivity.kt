package app.kronoer

import android.Manifest
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PersistableBundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** A fragment activity: the system prompt for App lock needs one. */
class MainActivity : FlutterFragmentActivity() {
    private var reminderChannel: MethodChannel? = null

    /** The answer Dart waits for while the device asks to notify. */
    private var askingToNotify: MethodChannel.Result? = null

    private val archiveExport = ArchiveExport(this)
    private val archiveImport = ArchiveImport(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        reminderChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.kronoer/reminder")
            .apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "notificationsAllowed" ->
                            result.success(WritingReminder.notificationsAllowed(this@MainActivity))
                        "requestPermission" -> askToNotify(result)
                        "schedule" -> {
                            WritingReminder.schedule(
                                this@MainActivity,
                                first = call.argument<Number>("first")!!.toLong(),
                                hour = call.argument<Int>("hour")!!,
                                minute = call.argument<Int>("minute")!!,
                                skipped = call.argument<String>("skipped"),
                                text = call.argument<String>("text")!!,
                            )
                            result.success(null)
                        }
                        "cancel" -> {
                            WritingReminder.cancel(this@MainActivity)
                            result.success(null)
                        }
                        "openNotificationSettings" -> {
                            startActivity(
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                            )
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.kronoer/app_lock")
            .setMethodCallHandler(AppLock(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.kronoer/export")
            .setMethodCallHandler(archiveExport)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.kronoer/import")
            .setMethodCallHandler(archiveImport)
        if (!unfinishedArchiveChecked) {
            // Once a run: an Export in this one may be writing its file right now.
            unfinishedArchiveChecked = true
            ArchiveExport.deleteUnfinished(this)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.kronoer/clipboard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copySensitive" -> result.success(copySensitive(call.arguments as String))
                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        reminderChannel?.setMethodCallHandler(null)
        reminderChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** A Writing reminder tapped while the app runs: Dart shows the Book tab. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(WritingReminder.EXTRA_OPENED, false)) {
            reminderChannel?.invokeMethod("opened", null)
        }
    }

    @Deprecated("The pickers for an Archive still answer here.")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!archiveExport.onActivityResult(requestCode, resultCode, data) &&
            !archiveImport.onActivityResult(requestCode, resultCode, data)
        ) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    /** Asks to notify where Android does (13 and higher), and answers whether Kronoer may. */
    private fun askToNotify(result: MethodChannel.Result) {
        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted || askingToNotify != null) {
            result.success(granted && WritingReminder.notificationsAllowed(this))
            return
        }
        askingToNotify = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), ASK_TO_NOTIFY)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != ASK_TO_NOTIFY) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        askingToNotify?.success(granted && WritingReminder.notificationsAllowed(this))
        askingToNotify = null
    }

    /**
     * Copies [text] as a clip marked sensitive, which Flutter's own clipboard cannot do: Android 13
     * and higher hide its content in their clipboard preview, and keyboards do not offer it.
     *
     * Returns "copiedWithPreview" where the system shows its own preview of the clip, "copied"
     * where it does not, and "tooLong" when the clip does not fit through to the system.
     */
    private fun copySensitive(text: String): String {
        val clip = ClipData.newPlainText("", text)
        clip.description.extras = PersistableBundle().apply {
            // Older versions ignore the extra; the key is the same string.
            putBoolean(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    ClipDescription.EXTRA_IS_SENSITIVE
                } else {
                    "android.content.extra.IS_SENSITIVE"
                },
                true,
            )
        }
        return try {
            getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) "copiedWithPreview" else "copied"
        } catch (e: RuntimeException) {
            // A clip larger than a binder transaction holds fails on its way to the system.
            "tooLong"
        }
    }

    private companion object {
        const val ASK_TO_NOTIFY = 1

        /** Whether this run has looked for an Archive an earlier one did not finish. */
        var unfinishedArchiveChecked = false
    }
}
