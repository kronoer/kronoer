package app.kronoer

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.io.IOException

/**
 * Export's side on the device: the system's picker for where an Archive goes, the open file
 * the core writes it into, and deleting a file that did not finish. Kronoer never reads the
 * file back, and nothing here touches a key: the Archive is written by the core.
 *
 * A file counts as unfinished from the moment it is picked until Dart says it is whole or
 * deleted. Its address is saved meanwhile, so that if Android stops Kronoer halfway, the next
 * launch deletes what was written.
 */
class ArchiveExport(private val activity: Activity) : MethodChannel.MethodCallHandler {
    /** The answer Dart waits for while the picker is up. */
    private var picking: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    /**
     * Each picked file open now, by its address. The core writes into a copy of its descriptor
     * and closes that; closing this one tells the provider the file is done, so it updates the
     * file's size and lets go of it.
     */
    private val open = mutableMapOf<String, ParcelFileDescriptor>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createArchive" -> createArchive(call.arguments as String, result)
            "finishArchive" -> {
                val uri = call.arguments as String
                val file = open.remove(uri)
                Thread {
                    close(file)
                    forget(activity, Uri.parse(uri))
                    main.post { result.success(null) }
                }.start()
            }
            "deleteArchive" -> {
                val uri = call.arguments as String
                val file = open.remove(uri)
                Thread {
                    close(file)
                    delete(activity, Uri.parse(uri))
                    main.post { result.success(null) }
                }.start()
            }
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

    /** Opens the system's picker for a new ZIP file named [name]. */
    private fun createArchive(name: String, result: MethodChannel.Result) {
        if (picking != null) {
            result.success(null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(ZIP)
            .putExtra(Intent.EXTRA_TITLE, name)
        picking = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, CREATE_ARCHIVE)
        } catch (e: ActivityNotFoundException) {
            picking = null
            result.error("noPicker", e.message, null)
        }
    }

    /** The picker's answer; returns whether it was for this. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != CREATE_ARCHIVE) return false
        val result = picking ?: return true
        picking = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        Thread {
            try {
                remember(uri)
                val file = open(uri)
                val fd = try {
                    file.dup().detachFd()
                } catch (e: IOException) {
                    close(file)
                    throw e
                }
                val name = displayName(uri) ?: uri.lastPathSegment ?: ""
                main.post {
                    open[uri.toString()] = file
                    result.success(mapOf("uri" to uri.toString(), "name" to name, "fd" to fd))
                }
            } catch (e: Exception) {
                Log.w(TAG, "The picked file did not open", e)
                delete(activity, uri)
                main.post { result.error("openFailed", e.message, null) }
            }
        }.start()
        return true
    }

    /** Saves [uri] as unfinished, and keeps the right to delete it after a restart. */
    private fun remember(uri: Uri) {
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (e: SecurityException) {
            // A provider that grants no lasting access: the file can still be deleted now.
        }
        prefs(activity).edit().putString(UNFINISHED, uri.toString()).apply()
    }

    /** The picked file, empty and open for writing. */
    private fun open(uri: Uri): ParcelFileDescriptor {
        val resolver = activity.contentResolver
        val file = try {
            resolver.openFileDescriptor(uri, "wt")
        } catch (e: IllegalArgumentException) {
            // Some providers do not know "wt"; the file is new, so "w" is the same.
            resolver.openFileDescriptor(uri, "w")
        } catch (e: FileNotFoundException) {
            resolver.openFileDescriptor(uri, "w")
        } ?: throw IOException("The provider gave no file")
        return file
    }

    private fun close(file: ParcelFileDescriptor?) {
        try {
            file?.close()
        } catch (e: IOException) {
            Log.w(TAG, "A picked file did not close", e)
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

    companion object {
        private const val TAG = "ArchiveExport"
        private const val ZIP = "application/zip"
        private const val CREATE_ARCHIVE = 2
        private const val PREFS = "app.kronoer.export"
        private const val UNFINISHED = "unfinished"

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** Deletes an Archive an earlier run did not finish, if there is one. */
        fun deleteUnfinished(context: Context) {
            val uri = prefs(context).getString(UNFINISHED, null) ?: return
            Thread { delete(context, Uri.parse(uri)) }.start()
        }

        /** Deletes [uri], as far as its provider lets, and forgets it. */
        private fun delete(context: Context, uri: Uri) {
            val resolver = context.contentResolver
            val deleted = try {
                DocumentsContract.deleteDocument(resolver, uri)
            } catch (e: Exception) {
                false
            }
            if (!deleted) {
                try {
                    // A provider that cannot delete: at least nothing of the Archive stays.
                    resolver.openFileDescriptor(uri, "wt")?.close()
                } catch (e: Exception) {
                    Log.w(TAG, "An unfinished Archive was not deleted", e)
                }
            }
            forget(context, uri)
        }

        /** The file is no longer unfinished: done, or deleted. */
        private fun forget(context: Context, uri: Uri) {
            val prefs = prefs(context)
            if (prefs.getString(UNFINISHED, null) == uri.toString()) {
                prefs.edit().remove(UNFINISHED).apply()
            }
            try {
                context.contentResolver.releasePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (e: SecurityException) {
                // It was never kept.
            }
        }
    }
}
