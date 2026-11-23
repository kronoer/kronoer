package app.kronoer

import android.app.KeyguardManager
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * App lock's side on the device: the system prompt, whether the device has a screen lock, and
 * hiding Kronoer from Recents. Kronoer keeps no PIN or code of its own, and nothing here touches
 * a key: the lock only decides whether the app is shown.
 */
class AppLock(private val activity: FragmentActivity) : MethodChannel.MethodCallHandler {
    /** The answer Dart waits for while the prompt is up. */
    private var prompting: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "screenLockSet" -> result.success(screenLockSet())
            "blocksScreenshots" -> result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU)
            "hideRecents" -> {
                hideRecents(call.arguments as Boolean)
                result.success(null)
            }
            "authenticate" -> authenticate(call.argument<String>("title")!!, result)
            "openSecuritySettings" -> {
                activity.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Whether the device has a PIN, pattern, or password, without which nothing can be checked. */
    private fun screenLockSet(): Boolean =
        activity.getSystemService(KeyguardManager::class.java).isDeviceSecure

    /**
     * Keeps Kronoer's content out of Recents. Android 13 and higher can hide just the preview;
     * before that only FLAG_SECURE can, which also blocks screenshots.
     */
    private fun hideRecents(hide: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.setRecentsScreenshotEnabled(!hide)
        } else if (hide) {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    /**
     * Asks for the device's own lock: any biometric the device has, or its PIN, pattern, or
     * password. Answers "unlocked", "cancelled", "noScreenLock", or "failed".
     */
    private fun authenticate(title: String, result: MethodChannel.Result) {
        if (prompting != null) {
            result.success("cancelled")
            return
        }
        if (!screenLockSet()) {
            result.success("noScreenLock")
            return
        }
        prompting = result
        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authResult: BiometricPrompt.AuthenticationResult,
                ) = answer("unlocked")

                override fun onAuthenticationError(code: Int, message: CharSequence) =
                    answer(
                        when (code) {
                            BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL -> "noScreenLock"
                            BiometricPrompt.ERROR_USER_CANCELED,
                            BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                            BiometricPrompt.ERROR_CANCELED,
                            -> "cancelled"
                            else -> "failed"
                        },
                    )

                // A finger that does not match: the prompt stays up and says so itself.
                override fun onAuthenticationFailed() {}
            },
        )
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setAllowedAuthenticators(BIOMETRIC_WEAK or DEVICE_CREDENTIAL)
            .setConfirmationRequired(false)
            .build()
        try {
            prompt.authenticate(info)
        } catch (e: RuntimeException) {
            answer("failed")
        }
    }

    private fun answer(outcome: String) {
        prompting?.success(outcome)
        prompting = null
    }
}
