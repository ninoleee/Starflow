import java.util.Calendar

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val starflowMinSdk = 23

fun computeStarflowVersionCode(versionName: String): Int {
    val sanitizedVersionName = versionName.substringBefore("+")
    val match = Regex("""^(\d+)\.(\d+)\.(\d+)$""").matchEntire(sanitizedVersionName)
        ?: return 1
    val major = match.groupValues[1].toInt()
    val month = match.groupValues[2].toInt()
    val sequence = match.groupValues[3].toInt()
    val yearOffset = Calendar.getInstance().get(Calendar.YEAR) - 2000
    return (yearOffset * 1_000_000) + (major * 10_000) + (month * 100) + sequence
}

android {
    namespace = "com.example.starflow"
    compileSdk = maxOf(flutter.compileSdkVersion, 31)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        getByName("debug") {
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.starflow"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = starflowMinSdk
        targetSdk = flutter.targetSdkVersion
        versionCode = computeStarflowVersionCode(flutter.versionName)
        versionName = flutter.versionName.substringBefore("+")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.media3:media3-exoplayer:1.4.1")
    implementation("androidx.media3:media3-ui:1.4.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
}
