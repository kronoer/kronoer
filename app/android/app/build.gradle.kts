plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The ABIs this build compiles Flutter and the Rust core for, from Flutter's
// `target-platform` (all three when Gradle runs on its own). A plugin's library
// alone in another ABI's folder would make Android pick that ABI and crash.
// Flutter's own filtering is off in gradle.properties, so these stand.
// With `--split-per-abi` Flutter makes one APK per target ABI instead, and
// Android does not allow ABI filters next to ABI splits.
fun splitPerAbi(): Boolean = project.findProperty("split-per-abi") == "true"

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

        if (!splitPerAbi()) {
            ndk {
                abiFilters += targetAbis()
            }
        }
    }

    // Preview is its own app beside the stable one, with its own package and,
    // once releases are signed, its own key (KRO-ADR-17). Dart reads the flavor
    // from `appFlavor`. pubspec.yaml makes `stable` the default.
    flavorDimensions += "channel"
    productFlavors {
        create("stable") {
            dimension = "channel"
        }
        create("preview") {
            dimension = "channel"
            applicationIdSuffix = ".preview"
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
