plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.nemoyu.wheretostudy.nativeapp"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.nemoyu.wheretostudy.nativeapp"
        minSdk = 24
        targetSdk = 36
        versionCode = 2
        versionName = "0.1.1"

        testInstrumentationRunner = "android.test.InstrumentationTestRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        buildConfig = false
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
