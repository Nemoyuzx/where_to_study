plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val releaseSigningValues = mapOf(
    "storeFile" to providers.environmentVariable("ANDROID_SIGNING_STORE_FILE").orNull,
    "storePassword" to providers.environmentVariable("ANDROID_SIGNING_STORE_PASSWORD").orNull,
    "keyAlias" to providers.environmentVariable("ANDROID_SIGNING_KEY_ALIAS").orNull,
    "keyPassword" to providers.environmentVariable("ANDROID_SIGNING_KEY_PASSWORD").orNull,
)
val releaseSigningReady = releaseSigningValues.values.all { !it.isNullOrBlank() }

android {
    namespace = "com.nemoyu.wheretostudy.nativeapp"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.nemoyu.wheretostudy.nativeapp"
        minSdk = 24
        targetSdk = 36
        versionCode = 11
        versionName = "0.1.1"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        testInstrumentationRunnerArguments["disableAnalytics"] = "true"
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = file(checkNotNull(releaseSigningValues["storeFile"]))
                storePassword = releaseSigningValues["storePassword"]
                keyAlias = releaseSigningValues["keyAlias"]
                keyPassword = releaseSigningValues["keyPassword"]
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            if (releaseSigningReady) {
                signingConfig = signingConfigs.getByName("release")
            }
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
        buildConfig = true
    }

    sourceSets {
        getByName("test").resources.srcDir(rootProject.file("../../contracts/v1/fixtures"))
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260719")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
}
