plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.shaon.linksyncro"
    
    // SDK 36 লেটেস্ট, তবে স্ট্যাবিলিটির জন্য ৩৫ নিরাপদ। আমি ৩৬-ই রেখেছি আপনার পছন্দ অনুযায়ী।
    compileSdk = 36 
    
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.shaon.linksyncro"
        minSdk = 24 
        targetSdk = 36
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // FFmpeg এর জন্য এটি মাস্ট (আবশ্যক)
        multiDexEnabled = true 

        // FFmpeg প্রসেসিং দ্রুত করার জন্য আর্কিটেকচার সেটআপ
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
    }

    // লাইব্রেরি কনফ্লিক্ট এড়ানোর জন্য এটি প্রফেশনাল স্ট্যান্ডার্ড
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "META-INF/DEPENDENCIES"
            excludes += "META-INF/LICENSE"
            excludes += "META-INF/LICENSE.txt"
            excludes += "META-INF/license.txt"
            excludes += "META-INF/NOTICE"
            excludes += "META-INF/NOTICE.txt"
            excludes += "META-INF/notice.txt"
        }
    }

    buildTypes {
        release {
            // সতর্কবার্তা: রিলিজ বিল্ডে debug signing ব্যবহার করবেন না, 
            // প্লে-স্টোরে আপলোড করার আগে প্রোডাকশন কি (Production Key) ব্যবহার করবেন।
            signingConfig = signingConfigs.getByName("debug")
            
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}