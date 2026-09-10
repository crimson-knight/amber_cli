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
    # The Crystal the generated lane installs before it can read the shard's pins;
    # matches CRYSTAL_ANDROID_VERSION in the pinned AssetPipeline.
    CRYSTAL_VERSION = "1.21.0"
    # The newest supported Android runtime at this CLI's release, the ceiling of
    # AssetPipeline's own pull-request gate: the generated lane exercises it beside
    # the app's floor and target, as a string, because Android names minor SDK
    # releases (36.1, 37.0). The newest released runtime is AssetPipeline's
    # android-next lane to prove first, not every generated app's.
    NEWEST_SUPPORTED_ANDROID_RUNTIME = "36"
    REPORTER = {{ read_file("#{__DIR__}/../templates/android/report_outcome.sh") }}
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
      outputs[".github/workflows/android-native.yml"] = ci_workflow
      outputs[".github/scripts/report_outcome.sh"] = REPORTER
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

    # The runtime API levels the generated lane exercises: the app's own floor
    # and target from config/native.yml, plus the newest released runtime.
    def ci_matrix : Array(String)
      [android.minimum_sdk.to_s, android.target_sdk.to_s, NEWEST_SUPPORTED_ANDROID_RUNTIME].uniq.sort_by(&.to_f)
    end

    # The generated application's continuous Android lane. It reads every
    # toolchain pin from the installed AssetPipeline shard, owns its emulator
    # through the shard's launcher, runs the app's own device suite, and
    # reports a failing scheduled, dispatched or push run as one issue that
    # tags the maintainers (the repository variable CI_MAINTAINERS, or the
    # repository owner). Pull requests carry their own checks.
    def ci_workflow : String
      matrix = ci_matrix.map { |api| "'#{api}'" }.join(", ")
      <<-YAML
      name: Android native validation

      'on':
        workflow_dispatch:
          inputs:
            report_selftest:
              description: 'Also open and close a self-test issue (lane:selftest) to prove the reporter tags the maintainers'
              type: boolean
              default: false
        schedule:
          # Nightly. GitHub runs scheduled workflows from the default branch only.
          - cron: '23 6 * * *'
        pull_request:
        push:
          branches: [main]

      permissions:
        contents: read

      concurrency:
        group: android-native-${{ github.ref }}
        cancel-in-progress: true

      jobs:
        native:
          name: Native Android API ${{ matrix.api }}
          runs-on: ubuntu-24.04
          timeout-minutes: 60
          strategy:
            fail-fast: false
            matrix:
              # The app's floor and target (config/native.yml) and the newest
              # supported runtime, as strings: Android names minor SDK releases.
              api: [#{matrix}]
          env:
            CRYSTAL_CACHE_DIR: ${{ github.workspace }}/build/crystal-cache/android-ci
            CRYSTAL_CROSS_DEPS: ${{ github.workspace }}/build/android-deps
            ANDROID_TEST_EVIDENCE: ${{ github.workspace }}/build/android-ci/evidence
            JOBS: '2'
          steps:
            - name: Checkout
              uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
              with:
                persist-credentials: false
            - name: Install Crystal
              uses: crystal-lang/install-crystal@d8ef131ecec0352ce0e39b81b0a6d95def58fe2f # v1 branch
              with:
                crystal: '#{CRYSTAL_VERSION}'
            - name: Shards install
              shell: bash
              run: shards install
            - name: Read the toolchain pins from the AssetPipeline shard
              id: pins
              shell: bash
              run: |
                source lib/asset_pipeline/config/android_toolchain.env
                printf 'java=%s\\n' "$ANDROID_JAVA_VERSION" >> "$GITHUB_OUTPUT"
            - name: Install Java
              uses: actions/setup-java@cf277c60eb25467037889841efdb72551f06f6c3 # v4
              with:
                distribution: temurin
                java-version: ${{ steps.pins.outputs.java }}
            - name: Install Android SDK tools
              uses: android-actions/setup-android@9fc6c4e9069bf8d3d10b2204b1fb8f6ef7065407 # v3
              with:
                packages: platform-tools
                log-accepted-android-sdk-licenses: false
            - name: Install native build prerequisites and the pinned SDK packages
              shell: bash
              run: |
                sudo apt-get update
                sudo apt-get install -y build-essential clang cmake autoconf automake libtool pkg-config libgc-dev libevent-dev libpcre2-dev libssl-dev libxml2-dev libyaml-dev zlib1g-dev
                source lib/asset_pipeline/config/android_toolchain.env
                sdkmanager "platforms;android-$ANDROID_COMPILE_SDK" "build-tools;$ANDROID_BUILD_TOOLS_VERSION" "ndk;$ANDROID_NDK_VERSION"
                bash lib/asset_pipeline/scripts/doctor_android.sh
            - name: Require hardware acceleration
              shell: bash
              run: |
                test -c /dev/kvm
                echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
                sudo udevadm control --reload-rules
                sudo udevadm trigger --name-match=kvm
                for _ in 1 2 3 4 5 6 7 8 9 10; do
                  if test -r /dev/kvm && test -w /dev/kvm; then exit 0; fi
                  sleep 1
                done
                sudo chmod 0666 /dev/kvm
                test -r /dev/kvm && test -w /dev/kvm
            - name: Shared specs
              shell: bash
              run: crystal spec --error-trace
            - name: Build, install and test on the emulator
              # The shard's launcher: the same image, cores, memory and options
              # AssetPipeline's own lane uses; it waits for the input service,
              # runs the app's device suite, and always tears the emulator down.
              shell: bash
              env:
                ANDROID_RUNTIME_API: ${{ matrix.api }}
                EMULATOR_TARGET: google_apis
                EMULATOR_ARCH: x86_64
                EMULATOR_PROFILE: pixel_6
                EMULATOR_CORES: '4'
                EMULATOR_RAM_MB: '4096'
                EMULATOR_HEAP_MB: '1024'
                EMULATOR_BOOT_TIMEOUT: '900'
                EMULATOR_LOG_DIR: build/android-ci/emulator
              run: bash lib/asset_pipeline/scripts/ci/android_emulator.sh run "$ANDROID_RUNTIME_API" 5554 -- bash mobile/android/android.sh test emulator-5554
            - name: Verify tracked sources were not rewritten
              run: git diff --exit-code
            - name: Retain evidence and packages, including failures
              if: always()
              uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4
              with:
                name: android-native-api-${{ matrix.api }}
                retention-days: 14
                if-no-files-found: error
                path: |
                  build/android-ci/
                  mobile/android/app/build/outputs/apk/
                  mobile/android/app/build/outputs/bundle/
        report:
          name: Report the outcome
          needs: native
          if: always() && github.event_name != 'pull_request'
          runs-on: ubuntu-24.04
          timeout-minutes: 10
          permissions:
            contents: read
            issues: write
          steps:
            - name: Checkout
              uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
              with:
                persist-credentials: false
            - name: Open, update or close the lane's issue
              shell: bash
              env:
                GH_TOKEN: ${{ github.token }}
                OUTCOME: ${{ needs.native.result }}
                LANE: android-native
                WORKFLOW_NAME: ${{ github.workflow }}
                RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
                REPOSITORY: ${{ github.repository }}
                MAINTAINERS: ${{ vars.CI_MAINTAINERS }}
                EVENT_NAME: ${{ github.event_name }}
                REF_NAME: ${{ github.ref_name }}
                SHA: ${{ github.sha }}
              run: bash .github/scripts/report_outcome.sh
            - name: Reporter self-test (dispatch input only)
              if: github.event_name == 'workflow_dispatch' && inputs.report_selftest
              shell: bash
              env:
                GH_TOKEN: ${{ github.token }}
                LANE: selftest
                WORKFLOW_NAME: ${{ github.workflow }} (reporter self-test)
                RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
                REPOSITORY: ${{ github.repository }}
                MAINTAINERS: ${{ vars.CI_MAINTAINERS }}
                EVENT_NAME: ${{ github.event_name }}
                REF_NAME: ${{ github.ref_name }}
                SHA: ${{ github.sha }}
              run: |
                OUTCOME=failure bash .github/scripts/report_outcome.sh
                OUTCOME=success bash .github/scripts/report_outcome.sh

      YAML
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

`.github/workflows/android-native.yml` is the app's continuous Android lane:
on every pull request, push to `main`, nightly, and on dispatch it installs
the pinned Crystal, reads every toolchain pin from the installed AssetPipeline
shard, boots its own emulator through the shard's launcher for the app's
floor, its target and the newest released runtime, and runs
`mobile/android/android.sh test`. A failing scheduled, dispatched or push run
opens one issue labeled `ci-failure` that tags the maintainers (set the
repository variable `CI_MAINTAINERS` to a list of handles; the repository
owner otherwise), comments while the failure persists, and closes on
recovery (`.github/scripts/report_outcome.sh`, copied from AssetPipeline).
GitHub runs the schedule from the default branch only.

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
