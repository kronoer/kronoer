package app.kronoer

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.os.Build
import android.os.PersistableBundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.kronoer/clipboard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copySensitive" -> result.success(copySensitive(call.arguments as String))
                    else -> result.notImplemented()
                }
            }
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
}
