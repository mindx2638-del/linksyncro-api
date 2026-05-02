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
    compileSdk = 36 
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
        targetSdk = 36 
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // FFmpeg এবং বড় অ্যাপের জন্য এটি অত্যন্ত জরুরি
        multiDexEnabled = true 
    }

    signingConfigs {
        getByName("debug") {
            // ডিফল্ট ডিবাগ কি ব্যবহার হবে
        }
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

    // বিভিন্ন লাইব্রেরির মধ্যে কনফ্লিক্ট এড়ানোর জন্য
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation("androidx.work:work-runtime:2.9.1")
    // মাল্টিডেক্স সাপোর্ট নিশ্চিত করার জন্য
    implementation("androidx.multidex:multidex:2.0.1")
}

flutter {
    source = "../.."
}