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
val generatedLicenseAssets = layout.buildDirectory.dir("generated/licenseAssets")
val syncLicenseAsset by tasks.registering(Sync::class) {
    from(
        rootProject.file("../../LICENSE"),
        rootProject.file("../../THIRD_PARTY_LICENSES.html"),
        rootProject.file("../../THIRD_PARTY_NOTICES.md"),
    )
    into(generatedLicenseAssets)
}

android {
    namespace = "com.nemoyu.wheretostudy.nativeapp"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.nemoyu.wheretostudy.nativeapp"
        minSdk = 24
        targetSdk = 36
        versionCode = 22
        versionName = "0.1.6"

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
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
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
        getByName("main").assets.srcDir(generatedLicenseAssets)
        getByName("test").resources.srcDir(rootProject.file("../../contracts/v1/fixtures"))
    }
}

tasks.named("preBuild").configure {
    dependsOn(syncLicenseAsset)
}

dependencies {
    implementation("androidx.core:core:1.16.0")
    implementation("androidx.window:window:1.5.1")
    implementation("androidx.window:window-java:1.5.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260719")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
}
