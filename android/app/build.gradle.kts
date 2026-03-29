plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // আপনার অ্যাপের ইউনিক নেমস্পেস
    namespace = "com.shaon.linksyncro" 
    
    // এরর ফিক্স করার জন্য এখানে সরাসরি ৩৬ (36) লিখে দিন
    compileSdk = 36 
    
    // টার্মিনালের এরর অনুযায়ী লেটেস্ট NDK ভার্সন
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
        
        // এখানেও ৩৬ (36) করে দেওয়া হলো যাতে প্লাগইনটি ঠিকঠাক কাজ করে
        targetSdk = 36
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // রিলিজ বিল্ডের জন্য সাইনিং কনফিগ
            signingConfig = signingConfigs.getByName("debug")
            
            // কোড অপ্টিমাইজেশন
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}