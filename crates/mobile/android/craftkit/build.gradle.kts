// craftkit: the Compose shell every Craft app shares on Android. The app's Rust library (built
// with craft-mobile) draws the canvas; this module owns the view, touches, files and the
// Material 3 chrome around it. Plugin versions come from the including app's root build.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "dev.craft.kit"
    compileSdk = 37
    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { compose = true }
    // The unit tests decode the generated catalogue's examples, so the kit and Rust agree.
    testOptions.unitTests.all { it.systemProperty("craft.catalogue", file("../../catalogue/ui.json").absolutePath) }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")
    implementation(composeBom)
    // Pinned over the BOM: 1.5 makes Material 3 Expressive public (MaterialExpressiveTheme, the
    // connected button group, wavy progress, floating toolbars).
    api("androidx.compose.material3:material3:1.5.0-rc01")
    api("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.12.0")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    testImplementation("junit:junit:4.13.2")
    // Compose UI tests on a device or emulator (`gradle :craftkit:connectedDebugAndroidTest`).
    androidTestImplementation(composeBom)
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    // Over ui-test's Espresso 3.5, which can't find API 37's InputManager.
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
