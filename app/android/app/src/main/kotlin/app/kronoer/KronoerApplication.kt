package app.kronoer

import android.app.Application

/** Starts the Rust core when the process starts, before any Dart code runs. */
class KronoerApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        System.loadLibrary("kronoer_bridge")
        KronoerCore.init(filesDir.absolutePath, noBackupFilesDir.absolutePath)
    }
}

/** The Rust core's entry point. Dart later opens the same library, which keeps what it got here. */
object KronoerCore {
    /** Gives the core the JVM and where to keep the store and the wrapped master key. */
    @JvmStatic
    external fun init(filesDir: String, noBackupDir: String)
}
