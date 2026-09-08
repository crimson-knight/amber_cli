import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
val assetPipeline = rootProject.file("../../lib/asset_pipeline")
val nativeAssetRoot = rootProject.file("../..")
val generatedImages = layout.buildDirectory.dir("generated/assetPipelineImages")
val compileImages by tasks.registering(Exec::class) {
    group = "build"
    description = "Compile the explicit application image catalog into Android resources."
    commandLine("crystal", "run", assetPipeline.resolve("scripts/compile_android_assets.cr").absolutePath,
        "--", nativeAssetRoot.absolutePath, "config/android_assets.yml", generatedImages.get().asFile.absolutePath)
    outputs.dir(generatedImages)
    outputs.upToDateWhen { false }
}
val toolchain = Properties().apply {
    assetPipeline.resolve("config/android_toolchain.env").inputStream().use { load(it) }
}
val app = Properties().apply {
    rootProject.file("android-app.properties").inputStream().use { load(it) }
}
// Bundled files (art, fonts, documents) the application loads by path.
// android.bundled_assets in config/native.yml names a project directory that
// is staged into the APK as assets/ap_bundle and extracted once per install
// by the runtime (lib/asset_pipeline/docs/android-assets.md). Without it the
// staged directory is empty and the APK carries no bundle.
val bundledAssets = app.getProperty("bundledAssets")?.takeIf { it.isNotBlank() }
val stagedBundle = layout.buildDirectory.dir("generated/assetPipelineBundle")
val stageBundle by tasks.registering(Sync::class) {
    group = "build"
    description = "Stage the application's bundled files into the APK's assets."
    if (bundledAssets != null) from(nativeAssetRoot.resolve(bundledAssets))
    into(stagedBundle.map { it.dir("ap_bundle") })
}
val buildCrystal by tasks.registering(Exec::class) {
    group = "build"
    description = "Build the application's Crystal runtime for every selected Android ABI."
    workingDir = rootProject.projectDir
    commandLine("bash", rootProject.file("build_crystal_lib.sh").absolutePath)
}
// Release signing comes from the environment, never from source control.
// AMBER_ANDROID_KEYSTORE (path), AMBER_ANDROID_KEYSTORE_PASSWORD,
// AMBER_ANDROID_KEY_ALIAS and AMBER_ANDROID_KEY_PASSWORD together sign the
// release APK and App Bundle with that upload key; with none of them set the
// release artifacts stay unsigned. A partial set fails the build instead of
// quietly producing an unsigned release.
val releaseSigningNames = listOf("AMBER_ANDROID_KEYSTORE", "AMBER_ANDROID_KEYSTORE_PASSWORD", "AMBER_ANDROID_KEY_ALIAS", "AMBER_ANDROID_KEY_PASSWORD")
val releaseSigning = releaseSigningNames.associateWith { name -> System.getenv(name)?.takeIf { it.isNotEmpty() } }
val releaseSigningPresent = releaseSigning.values.count { it != null }
require(releaseSigningPresent == 0 || releaseSigningPresent == releaseSigningNames.size) {
    "Release signing needs all of ${releaseSigningNames.joinToString()}; missing: ${releaseSigning.filterValues { it == null }.keys.joinToString()}"
}
val releaseKeystore = releaseSigning["AMBER_ANDROID_KEYSTORE"]?.let { file(it) }
require(releaseKeystore == null || releaseKeystore.isFile) { "AMBER_ANDROID_KEYSTORE is not a readable file: $releaseKeystore" }
android {
    namespace = "dev.amber.generated"
    compileSdk = app.getProperty("compileSdk").toInt()
    buildToolsVersion = toolchain.getProperty("ANDROID_BUILD_TOOLS_VERSION")
    ndkVersion = toolchain.getProperty("ANDROID_NDK_VERSION")
    defaultConfig {
        applicationId = app.getProperty("applicationId")
        minSdk = app.getProperty("minSdk").toInt()
        targetSdk = app.getProperty("targetSdk").toInt()
        versionCode = app.getProperty("versionCode").toInt()
        versionName = app.getProperty("versionName")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk { abiFilters += app.getProperty("abis").split(',') }
    }
    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = releaseSigning.getValue("AMBER_ANDROID_KEYSTORE_PASSWORD")
                keyAlias = releaseSigning.getValue("AMBER_ANDROID_KEY_ALIAS")
                keyPassword = releaseSigning.getValue("AMBER_ANDROID_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            ndk.debugSymbolLevel = "FULL"
            // Signed only when the environment supplies the upload key above.
            if (releaseKeystore != null) signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.toVersion(toolchain.getProperty("ANDROID_JAVA_VERSION"))
        targetCompatibility = JavaVersion.toVersion(toolchain.getProperty("ANDROID_JAVA_VERSION"))
    }
    kotlinOptions { jvmTarget = toolchain.getProperty("ANDROID_JAVA_VERSION") }
    sourceSets.getByName("main").java.srcDir(assetPipeline.resolve("android/runtime/src/main/java"))
    sourceSets.getByName("main").res.srcDir(assetPipeline.resolve("android/runtime/src/main/res"))
    sourceSets.getByName("main").res.srcDir(generatedImages.map { it.dir("res") })
    sourceSets.getByName("main").assets.srcDir(stagedBundle)
    sourceSets.getByName("test").java.srcDir(assetPipeline.resolve("android/runtime/src/test/java"))
    sourceSets.getByName("androidTest").java.srcDir(assetPipeline.resolve("android/runtime/src/androidTest/java"))
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(buildCrystal, compileImages, stageBundle) }
dependencies {
    testImplementation("junit:junit:4.13.2")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
}
apply(from = assetPipeline.resolve("android/runtime/dependencies.gradle.kts"))
