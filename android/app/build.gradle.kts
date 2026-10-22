plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.cursor.android"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.cursor.android"
        // You can update the following values to match your application needs.
        // For more information, see: [https://flutter.dev/to/review-gradle-config](https://flutter.dev/to/review-gradle-config).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        compose = true
    }

    // Release CI exports ANDROID_KEYSTORE_PATH and the passwords; local builds keep debug keys.
    val signingPath = System.getenv("ANDROID_KEYSTORE_PATH")
    if (!signingPath.isNullOrBlank()) {
        signingConfigs.create("distribution") {
            storeFile = file(signingPath)
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            // Without the release keystore, sign with the debug keys so `flutter run --release`
            // keeps working.
            signingConfig =
                if (signingPath.isNullOrBlank()) {
                    signingConfigs.getByName("debug")
                } else {
                    signingConfigs.getByName("distribution")
                }
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
    implementation("androidx.glance:glance-appwidget:1.2.0")
}
