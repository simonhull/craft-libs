// The CraftUI Gallery for Android: every native panel primitive, live against a fake app. Builds
// craftkit from this checkout, so it always shows the kit as it is here.
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "CraftGallery"
include(":app")
include(":craftkit")
project(":craftkit").projectDir = file("../craftkit")
