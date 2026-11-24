plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The ABIs this build compiles Flutter and the Rust core for, from Flutter's
// `target-platform` (all three when Gradle runs on its own). A plugin's library
// alone in another ABI's folder would make Android pick that ABI and crash.
// Flutter's own filtering is off in gradle.properties, so these stand.
fun targetAbis(): List<String> {
    val abis = mapOf(
        "android-arm64" to "arm64-v8a",
        "android-arm" to "armeabi-v7a",
        "android-x64" to "x86_64",
    )
    val requested = (project.findProperty("target-platform") as String?)
        ?.split(",")
        ?.mapNotNull { abis[it.trim()] }
    return if (requested.isNullOrEmpty()) abis.values.toList() else requested
}

android {
    namespace = "app.kronoer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.kronoer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += targetAbis()
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // App lock's system prompt: biometrics or the device's PIN, pattern, or password.
    implementation("androidx.biometric:biometric:1.1.0")
}
