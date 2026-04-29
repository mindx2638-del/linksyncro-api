import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// key.properties ফাইল থেকে ডেটা লোড করার জন্য
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.shaon.linksyncro"
    compileSdk = 36 // এখানে ৩৬ করা হয়েছে (প্লাগিনের রিকোয়েস্ট অনুযায়ী)
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.shaon.linksyncro"
        minSdk = 24
        targetSdk = 36 // এখানেও ৩৬ করা হয়েছে
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // ডিবাগ কনফিগ - 'storeFile' লাইনটি সরানো হয়েছে যাতে ফাইল খুঁজে না পাওয়ার এরর না দেয়
        getByName("debug") {
            // ডিফল্ট ডিবাগ কি ব্যবহার হবে
        }
        // রিলিজ কনফিগ
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
            }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation("androidx.work:work-runtime:2.9.1")
}

flutter {
    source = "../.."
}