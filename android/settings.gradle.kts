val localProperties =
    java.util.Properties().apply {
        val localPropertiesFile = file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use(::load)
        }
    }

localProperties.stringPropertyNames()
    .filter { it.startsWith("systemProp.") }
    .forEach { key ->
        val systemPropertyKey = key.removePrefix("systemProp.")
        val value = localProperties.getProperty(key)
        if (!value.isNullOrBlank()) {
            System.setProperty(systemPropertyKey, value)
        }
    }

pluginManagement {
    // pluginManagement 在独立作用域中解析，不能引用脚本顶层的 localProperties
    val flutterSdkPath =
        java.util.Properties()
            .apply {
                val f = settings.rootDir.resolve("local.properties")
                if (f.exists()) f.inputStream().use(::load)
            }
            .getProperty("flutter.sdk")
            ?: error("flutter.sdk not set in local.properties")

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        maven("https://maven.aliyun.com/repository/gradle-plugin")
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
