import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.chaquo.python")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = project.file("../key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    throw GradleException("key.properties not found at ${keystorePropertiesFile.absolutePath}")
}

android {
    namespace = "com.vladislavdelon.blackboxmobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vladislavdelon.blackboxmobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.clear()
            abiFilters.addAll(setOf("arm64-v8a"))
        }
    }

    chaquopy {
        defaultConfig {
            version = "3.13"
            pip {
                install("requests")
            }
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

// -----------------------------------------------------------------
// Android Gradle Plugin 9.x не сбрасывает debug-символы libflutter.so
// в некоторых конфигурациях. Принудительно вычищаем .debug_* секции
// после встроенной strip-задачи, чтобы APK не вздувался до 180+ МБ.
// -----------------------------------------------------------------
tasks.configureEach {
    if (name == "stripReleaseDebugSymbols") {
        doLast {
            val ndkDir = project.android.ndkDirectory
            val llvmStrip = ndkDir.resolve(
                "toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe"
            )
            if (llvmStrip.exists()) {
                outputs.files.asFileTree.matching {
                    include("**/*.so")
                }.forEach { soFile ->
                    val p = ProcessBuilder(
                        llvmStrip.absolutePath,
                        "--strip-debug",
                        soFile.absolutePath,
                    ).start()
                    p.waitFor()
                }
            }
        }
    }
}
