package app.kronoer

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.util.Log
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * Import's side on the device: the system's picker for an Archive, and the open file the core
 * reads it from. Nothing here reads the Archive or touches a key: the core does both.
 *
 * The core reads a ZIP from its end, so it needs a file it can seek in. A provider that only
 * streams its file gets it copied into Kronoer's cache first; the copy is deleted at once and
 * stays readable through its open descriptor until the core closes it.
 */
class ArchiveImport(private val activity: Activity) : MethodChannel.MethodCallHandler {
    /** The answer Dart waits for while the picker is up. */
    private var picking: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openArchive" -> openArchive(result)
            "keepScreenOn" -> {
                if (call.arguments as Boolean) {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Opens the system's picker for a ZIP file. */
    private fun openArchive(result: MethodChannel.Result) {
        if (picking != null) {
            result.success(null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(ZIP)
            .putExtra(Intent.EXTRA_MIME_TYPES, ZIP_TYPES)
        picking = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, OPEN_ARCHIVE)
        } catch (e: ActivityNotFoundException) {
            picking = null
            result.error("noPicker", e.message, null)
        }
    }

    /** The picker's answer; returns whether it was for this. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != OPEN_ARCHIVE) return false
        val result = picking ?: return true
        picking = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        Thread {
            try {
                val fd = open(uri)
                val name = displayName(uri) ?: uri.lastPathSegment ?: ""
                main.post { result.success(mapOf("name" to name, "fd" to fd)) }
            } catch (e: Exception) {
                Log.w(TAG, "The picked file did not open", e)
                main.post { result.error("openFailed", e.message, null) }
            }
        }.start()
        return true
    }

    /** A descriptor of the picked file the core can seek in, for it to take over. */
    private fun open(uri: Uri): Int {
        val file = activity.contentResolver.openFileDescriptor(uri, "r")
            ?: throw IOException("The provider gave no file")
        file.use {
            // A file of its own has a size; a pipe has none.
            if (it.statSize >= 0) return it.dup().detachFd()
        }
        val copy = File.createTempFile("import", ".zip", activity.cacheDir)
        try {
            activity.contentResolver.openInputStream(uri)?.use { input ->
                copy.outputStream().use { output -> input.copyTo(output) }
            } ?: throw IOException("The provider gave no stream")
            return ParcelFileDescriptor.open(copy, ParcelFileDescriptor.MODE_READ_ONLY)
                .detachFd()
        } finally {
            copy.delete()
        }
    }

    /** The file's name as the user's storage shows it. */
    private fun displayName(uri: Uri): String? = try {
        activity.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
    } catch (e: RuntimeException) {
        null
    }

    private companion object {
        const val TAG = "ArchiveImport"
        const val ZIP = "application/zip"
        val ZIP_TYPES = arrayOf(ZIP, "application/x-zip-compressed", "application/x-zip")
        const val OPEN_ARCHIVE = 3
    }
}
