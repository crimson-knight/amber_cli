require "base64"
require "digest/sha256"
require "html"
require "./capability_manifest"

module AmberCLI::Native
  # A standalone Android View host around AssetPipeline's versioned runtime.
  # Templates are embedded in the CLI binary; no developer/sample path is used.
  class AndroidShellGenerator
    WRAPPER_SHA256      = "b3a875ddc1f044746e1b1a55f645584505f4a10438c1afea9f15e92a7c42ec13"
    DISTRIBUTION_SHA256 = "b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06"
    TEMPLATES           = {
      "mobile/android/settings.gradle.kts"                                                   => {{ read_file("#{__DIR__}/../templates/android/settings.gradle.kts") }},
      "mobile/android/build.gradle.kts"                                                      => {{ read_file("#{__DIR__}/../templates/android/build.gradle.kts") }},
      "mobile/android/app/build.gradle.kts"                                                  => {{ read_file("#{__DIR__}/../templates/android/app.gradle.kts") }},
      "mobile/android/build_crystal_lib.sh"                                                  => {{ read_file("#{__DIR__}/../templates/android/build_crystal_lib.sh") }},
      "mobile/android/android.sh"                                                            => {{ read_file("#{__DIR__}/../templates/android/android.sh") }},
      "mobile/android/inspect_artifacts.sh"                                                  => {{ read_file("#{__DIR__}/../templates/android/inspect_artifacts.sh") }},
      "mobile/android/gradlew"                                                               => {{ read_file("#{__DIR__}/../templates/android/gradlew") }},
      "mobile/android/gradlew.bat"                                                           => {{ read_file("#{__DIR__}/../templates/android/gradlew.bat") }},
      "mobile/android/app/src/main/java/dev/amber/generated/MainActivity.kt"                 => {{ read_file("#{__DIR__}/../templates/android/MainActivity.kt") }},
      "mobile/android/app/src/androidTest/java/dev/amber/generated/NativeApplicationTest.kt" => {{ read_file("#{__DIR__}/../templates/android/NativeApplicationTest.kt") }},
      "mobile/android/app/src/androidTest/java/dev/amber/generated/NativeRestorationTest.kt" => {{ read_file("#{__DIR__}/../templates/android/NativeRestorationTest.kt") }},
      "src/app/counter.cr"                                                                   => {{ read_file("#{__DIR__}/../templates/android/counter.cr") }},
      "src/platform/android/app.cr"                                                          => {{ read_file("#{__DIR__}/../templates/android/app.cr") }},
      "spec/counter_spec.cr"                                                                 => {{ read_file("#{__DIR__}/../templates/android/counter_spec.cr") }},
    }
    WRAPPER_BASE64 = {{ read_file("#{__DIR__}/../templates/android/gradle-wrapper.jar.base64") }}

    getter manifest : CapabilityManifest
    getter name : String

    def initialize(@manifest : CapabilityManifest, @name : String)
      @manifest.validate!
      raise ArgumentError.new("Android generation requires a v2 manifest targeting android") unless @manifest.schema_version == 2 && app.targets.includes?("android")
    end

    def write(project_path : String) : Nil
      outputs = files
      outputs.each_key do |relative|
        raise ArgumentError.new("Refusing to overwrite #{relative}") if File.exists?(File.join(project_path, relative))
      end
      outputs.each do |relative, content|
        destination = File.join(project_path, relative)
        Dir.mkdir_p(File.dirname(destination))
        File.write(destination, content)
        File.chmod(destination, 0o755) if relative.ends_with?(".sh") || relative.ends_with?("/gradlew")
      end
    end

    def files : Hash(String, String)
      outputs = TEMPLATES.dup
      jar = Base64.decode(WRAPPER_BASE64)
      raise "Embedded Gradle wrapper checksum mismatch" unless Digest::SHA256.hexdigest(jar) == WRAPPER_SHA256
      outputs["mobile/android/gradle/wrapper/gradle-wrapper.jar"] = String.new(jar)
      outputs["mobile/android/gradle/wrapper/gradle-wrapper.properties"] = <<-PROPERTIES
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-9.3.1-bin.zip
distributionSha256Sum=#{DISTRIBUTION_SHA256}
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
PROPERTIES
      outputs["mobile/android/gradle.properties"] = "android.useAndroidX=true\norg.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8\nkotlin.code.style=official\n"
      outputs["mobile/android/android-app.properties"] = <<-PROPERTIES
# Generated from config/native.yml. Regenerate when changing native metadata.
applicationId=#{android.application_id}
minSdk=#{android.minimum_sdk}
targetSdk=#{android.target_sdk}
compileSdk=#{android.compile_sdk}
abis=#{android.abis.join(',')}
versionCode=#{app.build_number}
versionName=#{properties_value(app.version)}
internetPermission=#{android.declared_permissions.includes?("android.permission.INTERNET")}
notificationPermission=#{android.declared_permissions.includes?("android.permission.POST_NOTIFICATIONS")}
bundledAssets=#{android.bundled_assets || ""}
PROPERTIES
      outputs["mobile/android/app/src/main/AndroidManifest.xml"] = android_manifest
      outputs["mobile/android/app/src/main/res/values/strings.xml"] = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources><string name=\"app_name\" formatted=\"false\">#{android_string(app.display_name)}</string></resources>\n"
      outputs["mobile/android/app/src/main/res/values/host_settings.xml"] = host_settings
      outputs["mobile/android/app/src/main/res/values/styles.xml"] = styles
      outputs["mobile/android/app/src/main/res/values/colors.xml"] = colors(false)
      outputs["mobile/android/app/src/main/res/values-night/colors.xml"] = colors(true)
      outputs["mobile/android/app/src/main/res/drawable/ic_launcher_foreground.xml"] = launcher_foreground
      outputs["config/android_assets.yml"] = "schema_version: 1\nimages:\n  app_mark:\n    source: src/assets/app_mark.android.xml\n"
      outputs["src/assets/app_mark.android.xml"] = launcher_foreground
      if android.capabilities.notifications
        outputs["mobile/android/app/src/main/res/drawable/ap_notification_small.xml"] = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
  <path android:fillColor="#FFFFFFFF" android:pathData="M12,2C8.7,2 6,4.7 6,8L6,15L4,17L4,19L20,19L20,17L18,15L18,8C18,4.7 15.3,2 12,2M10,21L14,21C14,22.1 13.1,23 12,23C10.9,23 10,22.1 10,21" />
</vector>
XML
        outputs["mobile/android/app/src/main/res/xml/ap_notification_channels.xml"] = notification_channels
        outputs["mobile/android/app/src/main/res/values/notification_channels.xml"] = String.build do |io|
          io << "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n"
          android.notification_channels.each_with_index do |channel, index|
            io << "  <string name=\"ap_notification_channel_#{index}_name\" formatted=\"false\">#{android_string(channel.name)}</string>\n"
            io << "  <string name=\"ap_notification_channel_#{index}_description\" formatted=\"false\">#{android_string(channel.description)}</string>\n"
          end
          io << "</resources>\n"
        end
      end
      {"ic_launcher", "ic_launcher_round"}.each do |icon|
        outputs["mobile/android/app/src/main/res/mipmap-anydpi-v26/#{icon}.xml"] = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/launcher_background" />
  <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
XML
      end
      outputs["src/platform/android/configuration.cr"] = <<-CRYSTAL
# Generated public configuration. Never put server secrets in a mobile binary.
module App::Android
  DISPLAY_NAME = #{app.display_name.inspect}
  CONFIGURATION = Amber::Native::Configuration.new(#{android.application_id.inspect}, Amber::Native::Environment::Development)
end
CRYSTAL
      outputs["mobile/android/test_android.sh"] = "#!/usr/bin/env bash\nset -euo pipefail\nexec bash \"$(dirname \"$0\")/android.sh\" test \"$@\"\n"
      outputs["mobile/android/.gitignore"] = "/.gradle/\n/build/\n/app/build/\n/app/src/main/jniLibs/\n/local.properties\n"
      outputs["mobile/android/README.md"] = readme
      outputs
    end

    def android_manifest : String
      String.build do |io|
        io << "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\" xmlns:tools=\"http://schemas.android.com/tools\">\n"
        android.declared_permissions.each { |permission| io << "  <uses-permission android:name=\"#{xml(permission)}\" />\n" }
        {"android.permission.INTERNET", "android.permission.POST_NOTIFICATIONS"}.each do |permission|
          unless android.declared_permissions.includes?(permission)
            io << "  <uses-permission android:name=\"#{permission}\" tools:node=\"remove\" />\n"
          end
        end
        android.features.each { |feature| io << "  <uses-feature android:name=\"#{xml(feature.name)}\" android:required=\"#{feature.required}\" />\n" }
        io << "  <application android:label=\"@string/app_name\" android:icon=\"#{xml(android.appearance.icon)}\" android:roundIcon=\"#{xml(android.appearance.round_icon)}\" android:theme=\"#{xml(android.appearance.theme)}\" android:supportsRtl=\"true\" android:enableOnBackInvokedCallback=\"true\" android:allowBackup=\"#{android.allow_backup}\" android:usesCleartextTraffic=\"#{android.allow_cleartext_traffic}\">\n"
        if android.capabilities.notifications
          io << "    <meta-data android:name=\"dev.assetpipeline.notification_channels\" android:resource=\"@xml/ap_notification_channels\" />\n"
        end
        # The runtime's photo picker captures with the system camera app into a
        # file under the application's cache directory through this provider
        # (asset_pipeline docs/android-photos.md); the paths resource ships with
        # the runtime. Unexported and scoped to that directory, it is declared
        # for every application, and needs no camera permission: the capability
        # below is for an application that uses the camera hardware itself.
        io << "    <provider android:name=\"androidx.core.content.FileProvider\" android:authorities=\"${applicationId}.assetpipeline.photos\" android:exported=\"false\" android:grantUriPermissions=\"true\">\n"
        io << "      <meta-data android:name=\"android.support.FILE_PROVIDER_PATHS\" android:resource=\"@xml/ap_photo_paths\" />\n"
        io << "    </provider>\n"
        io << "    <activity android:name=\"dev.amber.generated.MainActivity\" android:exported=\"true\" android:windowSoftInputMode=\"adjustResize\">\n"
        io << "      <intent-filter><action android:name=\"android.intent.action.MAIN\" /><category android:name=\"android.intent.category.LAUNCHER\" /></intent-filter>\n"
        android.deep_links.each do |link|
          io << "      <intent-filter android:autoVerify=\"#{link.auto_verify}\">\n"
          io << "        <action android:name=\"android.intent.action.VIEW\" /><category android:name=\"android.intent.category.DEFAULT\" /><category android:name=\"android.intent.category.BROWSABLE\" />\n"
          schemes = link.auto_verify ? ["http", "https"] : [link.scheme]
          schemes.each do |scheme|
            io << "        <data android:scheme=\"#{xml(scheme)}\""
            if host = link.host
              io << " android:host=\"#{xml(host)}\""
            end
            if prefix = link.path_prefix
              io << " android:pathPrefix=\"#{xml(prefix)}\""
            end
            io << " />\n"
          end
          io << "      </intent-filter>\n"
        end
        io << "    </activity>\n  </application>\n</manifest>\n"
      end
    end

    private def app : CapabilityManifest::ApplicationMetadata
      @manifest.app || raise ArgumentError.new("Missing app metadata")
    end

    private def notification_channels : String
      String.build do |io|
        io << "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<notification-channels smallIcon=\"@drawable/ap_notification_small\">\n"
        android.notification_channels.each_with_index do |channel, index|
          io << "  <channel id=\"#{xml(channel.id)}\" name=\"@string/ap_notification_channel_#{index}_name\" description=\"@string/ap_notification_channel_#{index}_description\" importance=\"#{channel.importance_value}\" />\n"
        end
        io << "</notification-channels>\n"
      end
    end

    private def android : CapabilityManifest::AndroidCapabilities
      @manifest.android || raise ArgumentError.new("Missing android metadata")
    end

    private def xml(value : String) : String
      HTML.escape(value)
    end

    # Android interprets escapes after XML parsing. Quote the entire value to
    # preserve whitespace, then escape literal quotes/backslashes before XML.
    private def android_string(value : String) : String
      escaped = value.gsub('\\', "\\\\").gsub('"', "\\\"")
        .gsub('\n', "\\n").gsub('\r', "\\r").gsub('\t', "\\t")
        .gsub('@', "\\@").gsub('?', "\\?")
      xml("\"#{escaped}\"")
    end

    private def properties_value(value : String) : String
      value.gsub('\\', "\\\\").gsub('\n', "\\n").gsub('\r', "\\r").gsub('\t', "\\t")
    end

    # The host settings the application reads at startup through
    # `UI::Android::Application.setting` (lib/asset_pipeline/docs/android-settings.md):
    # one KEY=value per line inside one string resource, empty in a fresh
    # project. A release step writes the customer's values here, the way an
    # iOS archive bakes them into Info.plist, and the generated activity
    # registers the text with the runtime before Crystal starts.
    private def host_settings : String
      <<-XML
      <?xml version="1.0" encoding="utf-8"?>
      <resources><string name="ap_host_settings" formatted="false" translatable="false"></string></resources>
      XML
    end

    private def styles : String
      <<-XML
<?xml version="1.0" encoding="utf-8"?>
<resources>
  <style name="#{xml(android.appearance.theme.sub("@style/", ""))}" parent="Theme.Material3.DayNight.NoActionBar">
    <item name="android:windowBackground">@color/app_background</item>
    <item name="android:windowSplashScreenBackground">#{xml(android.appearance.splash_background)}</item>
    <item name="android:windowSplashScreenAnimatedIcon">@drawable/ic_launcher_foreground</item>
    <item name="android:windowLightStatusBar">@bool/light_system_bars</item>
    <item name="android:windowLightNavigationBar">@bool/light_system_bars</item>
    <item name="android:statusBarColor">@android:color/transparent</item>
  </style>
</resources>
XML
    end

    private def colors(dark : Bool) : String
      <<-XML
<?xml version="1.0" encoding="utf-8"?>
<resources>
  <color name="app_background">#{dark ? "#141218" : "#FFFBFE"}</color>
  <color name="splash_background">#{dark ? "#141218" : "#FFFBFE"}</color>
  <color name="launcher_background">#3457D5</color>
  <bool name="light_system_bars">#{!dark}</bool>
</resources>
XML
    end

    private def launcher_foreground : String
      <<-XML
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
  <path android:fillColor="#FFFFFFFF" android:pathData="M30,30h48v48h-48z" />
  <path android:fillColor="#FF3457D5" android:pathData="M38,38h32v8h-32zM38,54h20v16h-20zM64,54h6v16h-6z" />
</vector>
XML
    end

    private def readme : String
      <<-MARKDOWN
# Android application

This is a native Android View application, not a WebView wrapper. Its Crystal
entrypoint is `src/platform/android/app.cr`; shared rules live in `src/app`.
The Activity and project belong to this app. JNI/runtime/listener implementations
come from the installed AssetPipeline shard, not from a showcase checkout.

From the project root, after installing Android-capable Amber and AssetPipeline:

```sh
shards install
bash mobile/android/android.sh doctor
bash mobile/android/android.sh build
bash mobile/android/android.sh run emulator-5554
bash mobile/android/android.sh test emulator-5554
```

The first build compiles GC/PCRE2 dependencies for all selected ABIs. Set
`CRYSTAL_CROSS_DEPS` to share a verified cache. SDK/NDK/JDK resolution uses
AssetPipeline's pinned contract. No `local.properties` with a developer SDK path
is generated. The Gradle distribution and embedded wrapper have verified hashes.

`config/native.yml` is the source for generated app properties, manifest,
configuration and resources. Regenerate deliberately when changing it; preserve
handwritten screen/domain code. Custom icon/color resource references must exist
before building. Verified links still need website association and runtime tests.

`config/android_assets.yml` maps logical `UI::Image` names to project-local PNG,
JPEG, WebP or Android VectorDrawable XML files. Gradle compiles this catalog into
native resources on every build. The counter uses its bundled `app_mark`; no
network request or WebView is involved. Optional `dark_source` selects an Android
night-mode variant and `density` defaults to `nodpi`. SVG needs an explicit
Android export. See AssetPipeline's `docs/android-images.md` for bounds and
unsupported formats. Edit catalog/source files, never generated build resources.

The counter saves a versioned snapshot to app-private SQLite through Amber's
Storage interface. It restores validated state before enabling its controls and
refuses to overwrite an invalid stored snapshot. This is not secret storage.
Save/load results return asynchronously on the main thread; the app explicitly
requests a deferred refresh after a state change.

For HTTP APIs, explicitly enable the network capability in the manifest and use
`require "amber/native/android_http"` with `Amber::Native::Android::HTTPClient`.
The shared Android host uses platform TLS/trust, bounded binary payloads, explicit
redirects and cancellable worker requests. It does not include Crystal OpenSSL.
See the Amber shard's `docs/android-http.md` for limits and error semantics.
The counter itself does not make network requests; its test is not a TLS proof.
Both hosts use AssetPipeline's pinned `android/runtime/dependencies.gradle.kts`.

Tests launch this Activity and verify native state, validation and recreation.
Missing devices and crashed/empty instrumentation are failures, never passes.
Host-session, service-queue, HTTP wire and HTTP worker test reports are required;
missing, empty or failed reports stop the proof before device instrumentation.
The test mutates the application's counter/name without clearing its database;
use a dedicated development app ID, not an app containing important user data.
It then forces a new process and requires the saved counter/name to be restored.
Saved app data survives process restart; transient View state is not persisted.
Only one mounted native root per process is supported. Service capability
declarations do not grant runtime permissions. Other platform adapters remain open.

Release-mode bundles retain native debug symbols. Release signing comes from the
environment, never from source control: set `AMBER_ANDROID_KEYSTORE`,
`AMBER_ANDROID_KEYSTORE_PASSWORD`, `AMBER_ANDROID_KEY_ALIAS` and
`AMBER_ANDROID_KEY_PASSWORD` to your upload key before `android.sh build`, and
the release APK and App Bundle are signed with it and verified by
`inspect_artifacts.sh` (`release-signing.txt` in the evidence records the signer
certificate, or `unsigned`). A partial set fails the build. Complete the
runtime/device/store-policy checks before release.
The wider Android target is still in development; released-dependency consumer
proof remains required before this generator can be advertised as supported.
MARKDOWN
    end
  end
end
