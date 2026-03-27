plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // আপনার অ্যাপের ইউনিক নেমস্পেস
    namespace = "com.shaon.linksyncro" 
    compileSdk = flutter.compileSdkVersion
    
    // টার্মিনালের এরর অনুযায়ী লেটেস্ট NDK ভার্সন এখানে দেওয়া হলো
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // প্লে-স্টোরে আইডেন্টিফিকেশনের জন্য আপনার ইউনিক আইডি
        applicationId = "com.shaon.linksyncro"
        
        // ভিডিও ডাউনলোডার প্যাকেজের জন্য মিনিমাম ২৪ দেওয়া নিরাপদ
        minSdk = 24 
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // রিলিজ বিল্ডের জন্য সাইনিং কনফিগ
            signingConfig = signingConfigs.getByName("debug")
            
            // কোড অপ্টিমাইজেশন (বর্তমানে ফলস রাখা হয়েছে)
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}