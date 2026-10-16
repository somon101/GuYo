// Imports must come first in a Gradle Kotlin script, and these two ARE needed
// qualified-free: inside `android { }` the name `java` refers to the Android
// extension, so `java.util.Properties` there is an unresolved reference.
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // Reads android/app/google-services.json (Firebase project guyo-1e112, push).
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

base {
    // Flutter's own tooling still names the copy it places under
    // build/app/outputs/flutter-apk/ as app-<buildType>.apk regardless of
    // this, but it does give the native Gradle-side APK under
    // android/app/build/outputs/apk/ a friendly name instead of app-*.apk.
    archivesName.set("GuYo")
}

android {
    namespace = "com.guyo.guyo_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (the "real system notification" style
        // chosen in Admin Web) uses java.time APIs, which must be desugared to
        // work on the older Android versions the app still supports. Its own
        // README requires this flag and the dependency at the bottom of this
        // file; compileSdk and Java 17 above are the versions it asks for.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.guyo.guyo_app"
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
        // The release key -- what Google Play identifies this app by, and the only
        // thing that lets a future update be published. The keystore and its
        // passwords live in android/key.properties and android/*.jks, which are
        // NEVER committed (see .gitignore): whoever holds them can publish as GuYo,
        // and losing them means the app can never be updated again.
        if (rootProject.file("key.properties").exists()) {
            create("release") {
                val props = Properties()
                props.load(FileInputStream(rootProject.file("key.properties")))
                keyAlias = props["keyAlias"] as String
                keyPassword = props["keyPassword"] as String
                storeFile = file(props["storeFile"] as String)
                storePassword = props["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Signed with the real key when it is present (always, on this machine);
            // the debug key only as a fallback so a checkout without the secrets can
            // still build a release.
            signingConfig = if (rootProject.file("key.properties").exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
    // Required by the desugaring enabled above (see the comment there).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
