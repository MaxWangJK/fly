import java.util.Properties
import java.security.KeyStore
import java.security.MessageDigest

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Keep the release identity outside Git and portable with the owner workspace.
val releaseSigningFile = providers.environmentVariable("FLY_ANDROID_SIGNING_PROPERTIES")
    .orNull?.let { rootProject.file(it) }
    ?: rootProject.file("../license_tools/private/android/signing.properties")
val releaseSigning = Properties().apply {
    if (releaseSigningFile.isFile) {
        releaseSigningFile.inputStream().use { load(it) }
    }
}
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true) || it.substringAfterLast(':') == "build"
}
if (releaseRequested && !releaseSigningFile.isFile) {
    throw GradleException("Release signing configuration is missing. Restore the original private Android signing files; do not generate a replacement key.")
}

android {
    namespace = "com.flyproduct.fly"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.flyproduct.fly"
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
    }

    signingConfigs {
        if (releaseSigningFile.isFile) {
            create("flyRelease") {
                fun required(name: String): String = releaseSigning.getProperty(name)
                    ?.takeIf { it.isNotBlank() }
                    ?: throw GradleException("Release signing property is missing: $name")
                storeFile = releaseSigningFile.parentFile.resolve(required("storeFile"))
                if (!storeFile!!.isFile) {
                    throw GradleException("Release keystore is missing. Restore the original Android release identity.")
                }
                storePassword = required("storePassword")
                keyAlias = required("keyAlias")
                keyPassword = required("keyPassword")
                storeType = releaseSigning.getProperty("storeType", "PKCS12")
                val expectedFingerprint = rootProject.file("release-certificate.sha256")
                    .readText().trim().uppercase()
                val identity = KeyStore.getInstance(storeType)
                storeFile!!.inputStream().use { identity.load(it, storePassword!!.toCharArray()) }
                val certificate = identity.getCertificate(keyAlias)
                    ?: throw GradleException("Release signing certificate is missing.")
                val actualFingerprint = MessageDigest.getInstance("SHA-256")
                    .digest(certificate.encoded)
                    .joinToString("") { "%02X".format(it.toInt() and 0xff) }
                if (actualFingerprint != expectedFingerprint) {
                    throw GradleException("Release certificate differs from the registered Fly identity. Restore the original key; do not silently replace it.")
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("flyRelease")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
