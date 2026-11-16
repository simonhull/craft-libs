// The Gallery app: craftkit's native panels with no Rust behind them. It reads the catalogue that
// craft-mobile generates (`crates/mobile/catalogue/ui.json`), copied into its assets at build time.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "dev.craft.gallery"
    compileSdk = 37
    defaultConfig {
        applicationId = "dev.craft.gallery"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "0.1"
    }
    buildFeatures { compose = true }
}

/** Copies the generated catalogue into the app's assets, as `ui.json`. */
abstract class CopyCatalogue : DefaultTask() {
    @get:InputFile abstract val catalogue: RegularFileProperty

    @get:OutputDirectory abstract val assets: DirectoryProperty

    @TaskAction
    fun copy() {
        catalogue.get().asFile.copyTo(assets.get().file("ui.json").asFile, overwrite = true)
    }
}

val catalogue = tasks.register<CopyCatalogue>("copyCatalogue") {
    catalogue.set(rootProject.layout.projectDirectory.file("../../catalogue/ui.json"))
}

androidComponents {
    onVariants { variant -> variant.sources.assets?.addGeneratedSourceDirectory(catalogue, CopyCatalogue::assets) }
}

dependencies {
    implementation(project(":craftkit"))
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    // The same material3 as craftkit, over the BOM's.
    implementation("androidx.compose.material3:material3:1.5.0-rc01")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.12.0")
    implementation("androidx.compose.material:material-icons-extended:1.7.8")
}
