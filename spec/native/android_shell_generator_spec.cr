require "../amber_cli_spec"
require "xml"
require "yaml"
require "../../src/amber_cli/native/android_shell_generator"
require "../../src/amber_cli/generators/hybrid_app"

describe AmberCLI::Native::AndroidShellGenerator do
  it "emits opt-in notification metadata, escaped channel labels and a monochrome icon" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("counter")
    default = AmberCLI::Native::AndroidShellGenerator.new(manifest, "counter")
    default.android_manifest.should contain(%(android:name="android.permission.POST_NOTIFICATIONS" tools:node="remove"))
    default.files.has_key?("mobile/android/app/src/main/res/xml/ap_notification_channels.xml").should be_false
    android = manifest.android.not_nil!
    android.capabilities.notifications = true
    android.notification_channels << AmberCLI::Native::CapabilityManifest::AndroidNotificationChannel.new("updates", "@Updates & 雪")
    files = AmberCLI::Native::AndroidShellGenerator.new(manifest, "counter").files
    files["mobile/android/app/src/main/AndroidManifest.xml"].should contain(%(android:name="dev.assetpipeline.notification_channels" android:resource="@xml/ap_notification_channels"))
    files["mobile/android/app/src/main/AndroidManifest.xml"].should_not contain(%(android:name="android.permission.POST_NOTIFICATIONS" tools:node="remove"))
    files["mobile/android/android-app.properties"].should contain("notificationPermission=true")
    channels = XML.parse(files["mobile/android/app/src/main/res/xml/ap_notification_channels.xml"])
    channels.xpath_string("string(//channel/@importance)").should eq("2")
    XML.parse(files["mobile/android/app/src/main/res/values/notification_channels.xml"]).xpath_string("string(//string[1])").should eq(%("\\@Updates & 雪"))
    files["mobile/android/app/src/main/res/drawable/ap_notification_small.xml"].should contain(%(android:fillColor="#FFFFFFFF"))
  end
  it "prevents dependencies from granting internet without explicit application metadata" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("counter")
    generator = AmberCLI::Native::AndroidShellGenerator.new(manifest, "counter")
    generator.android_manifest.should contain(%(android:name="android.permission.INTERNET" tools:node="remove"))
    generator.files["mobile/android/android-app.properties"].should contain("internetPermission=false")
    manifest.android.not_nil!.permissions << "android.permission.INTERNET"
    explicit = AmberCLI::Native::AndroidShellGenerator.new(manifest, "counter")
    explicit.android_manifest.should_not contain(%(android:name="android.permission.INTERNET" tools:node="remove"))
    explicit.files["mobile/android/android-app.properties"].should contain("internetPermission=true")
  end
  it "embeds a complete standalone host and the official wrapper bytes" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("counter")
    generator = AmberCLI::Native::AndroidShellGenerator.new(manifest, "counter")
    files = generator.files
    Digest::SHA256.hexdigest(files["mobile/android/gradle/wrapper/gradle-wrapper.jar"]).should eq(AmberCLI::Native::AndroidShellGenerator::WRAPPER_SHA256)
    files["mobile/android/gradle/wrapper/gradle-wrapper.properties"].should contain(AmberCLI::Native::AndroidShellGenerator::DISTRIBUTION_SHA256)
    files["mobile/android/app/src/main/java/dev/amber/generated/MainActivity.kt"].should contain("NativeScreenHost(this, mount, scroll, savedInstanceState)")
    files["mobile/android/app/src/main/java/dev/amber/generated/MainActivity.kt"].should contain("screenHost.saveState(outState)")
    files["mobile/android/app/build.gradle.kts"].should contain("android/runtime/src/main/res")
    # The device suite streams logcat from its start; a dump taken afterward loses the
    # runtime's load line once a slow emulator wraps its buffer.
    files["mobile/android/android.sh"].should contain("logcat-live.txt")
    files["mobile/android/android.sh"].should contain("trap stop_live_logcat EXIT")
    files["mobile/android/app/src/main/java/dev/amber/generated/MainActivity.kt"].should contain("NativeNavigation(this)")
    files["mobile/android/app/src/main/AndroidManifest.xml"].should contain("android:enableOnBackInvokedCallback=\"true\"")
    files["mobile/android/app/src/main/AndroidManifest.xml"].should contain(%(android:authorities="${applicationId}.assetpipeline.photos"))
    files["mobile/android/app/src/main/AndroidManifest.xml"].should contain(%(android:resource="@xml/ap_photo_paths"))
    files["src/platform/android/app.cr"].should contain("UI::NavigationStack.new(CounterScreen.new")
    files["src/platform/android/app.cr"].should contain("@@navigation : UI::NavigationStack =")
    files["src/platform/android/app.cr"].should contain("UI::NavigationLink.new(\"Open details\"")
    files["src/platform/android/app.cr"].should contain("asset_pipeline/ui/android/application")
    files["src/platform/android/app.cr"].should contain("Application.on_lifecycle")
    files["src/platform/android/app.cr"].should contain("input.maximum_width = 280.5")
    files["src/platform/android/app.cr"].should contain("input.grow!")
    files["config/android_assets.yml"].should contain("source: src/assets/app_mark.android.xml")
    XML.parse(files["src/assets/app_mark.android.xml"]).root.not_nil!.name.should eq("vector")
    files["src/platform/android/app.cr"].should contain(%(UI::Image.new("app_mark")))
    files["mobile/android/app/build.gradle.kts"].should contain("compile_android_assets.cr")
    files["mobile/android/app/build.gradle.kts"].should contain("dependsOn(buildCrystal, compileImages, stageBundle)")
    files["mobile/android/app/src/main/java/dev/amber/generated/MainActivity.kt"].should contain("CrystalBridge.detachHost(this)")
    files["mobile/android/android.sh"].should contain(":app:testDebugUnitTest")
    files["mobile/android/android.sh"].should contain("LayoutPolicyTest")
    files["mobile/android/android.sh"].should contain("ViewStatePolicyTest")
    files["mobile/android/android.sh"].should contain("SemanticsPolicyTest")
    files["mobile/android/android.sh"].should contain("CompoundFocusPolicyTest")
    files["mobile/android/android.sh"].should contain("DialogPolicyTest")
    files["mobile/android/android.sh"].should contain("SheetPolicyTest")
    files["mobile/android/inspect_artifacts.sh"].should contain("android_dialog_configure")
    files["mobile/android/inspect_artifacts.sh"].should contain("android_sheet_configure")
    files["mobile/android/inspect_artifacts.sh"].should contain("android_sheet_request_dismiss")
    files["mobile/android/app/src/main/java/dev/amber/generated/MainActivity.kt"].should contain("NativeSemantics.dispatchShortcut")
    files["mobile/android/app/src/main/java/dev/amber/generated/MainActivity.kt"].should contain("unmodifiedOnly = true")
    files["mobile/android/inspect_artifacts.sh"].should contain("android_view_semantics")
    files["mobile/android/inspect_artifacts.sh"].should contain("android_view_state_metadata")
    files["src/platform/android/app.cr"].should contain("input.state_key = \"counter-name\"")
    files["src/platform/android/app.cr"].should contain("actions.fill_equally = true")
    files["src/platform/android/app.cr"].should contain("actions.grow!")
    files["mobile/android/app/src/androidTest/java/dev/amber/generated/NativeApplicationTest.kt"].should contain("counter-actions")
    %w(android_layout_prepare android_layout_wrap android_stack_set_alignment android_stack_set_equal_width android_layout_add_spacer android_scrollview_configure).each do |symbol|
      files["mobile/android/inspect_artifacts.sh"].should contain(symbol)
    end
    files.values.none? { |value| value.includes?("samples/cross_platform/android_host") }.should be_true
    files.has_key?("mobile/android/local.properties").should be_false
    files["mobile/android/inspect_artifacts.sh"].should contain("asset_pipeline_app.dependencies.manifest")
    files["mobile/android/inspect_artifacts.sh"].should contain("enableOnBackInvokedCallback")
    files["mobile/android/inspect_artifacts.sh"].should contain("format=asset-pipeline-android-deps-v2")
    %w(void string bool float int).each do |kind|
      files["mobile/android/inspect_artifacts.sh"].should contain("crystal_android_host_callback_#{kind}")
    end
    files["mobile/android/android.sh"].should contain("Crystal .*callback failed")
    files["mobile/android/inspect_artifacts.sh"].should contain("android_exception_pending")
  end

  it "exports permissions and independent, verified web-link filters as valid XML" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("counter")
    android = manifest.android.not_nil!
    android.capabilities.network = true
    android.features << AmberCLI::Native::CapabilityManifest::AndroidFeature.new("android.hardware.camera.any", false)
    android.deep_links << AmberCLI::Native::CapabilityManifest::AndroidDeepLink.new("https", "example.com", "/items&a", true)
    android.deep_links << AmberCLI::Native::CapabilityManifest::AndroidDeepLink.new("counter", "open", "/items")
    source = AmberCLI::Native::AndroidShellGenerator.new(manifest, "counter").android_manifest
    doc = XML.parse(source)
    doc.xpath_nodes("//uses-permission").size.should eq(2) # One declaration, one notification removal policy.
    doc.xpath_nodes("//uses-feature").size.should eq(1)
    doc.xpath_nodes("//activity/intent-filter").size.should eq(3)
    doc.xpath_nodes("//activity/intent-filter/data").size.should eq(3)
    source.should contain("android:scheme=\"http\"")
    source.should contain("/items&amp;a")
    source.should_not contain("<manifest package=")
  end

  it "refuses to overwrite handwritten files before writing any output" do
    SpecHelper.within_temp_directory do |temp_dir|
      Dir.mkdir_p(File.join(temp_dir, "src/app"))
      File.write(File.join(temp_dir, "src/app/counter.cr"), "user-owned")
      manifest = AmberCLI::Native::CapabilityManifest.default_for("counter")
      expect_raises(ArgumentError, /Refusing to overwrite/) do
        AmberCLI::Native::AndroidShellGenerator.new(manifest, "counter").write(temp_dir)
      end
      File.read(File.join(temp_dir, "src/app/counter.cr")).should eq("user-owned")
      File.exists?(File.join(temp_dir, "mobile/android/gradlew")).should be_false
    end
  end

  it "escapes Android string syntax after XML parsing without treating labels as formats" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("counter")
    manifest.app.not_nil!.display_name = "@Seth's \"Counter\" &  100% \\ path"
    source = AmberCLI::Native::AndroidShellGenerator.new(manifest, "counter").files["mobile/android/app/src/main/res/values/strings.xml"]
    doc = XML.parse(source)
    doc.xpath_string("string(//string)").should eq("\"\\@Seth's \\\"Counter\\\" &  100% \\\\ path\"")
    doc.xpath_string("string(//string/@formatted)").should eq("false")
  end

  it "emits only the requested Android presentation for native-only projects" do
    SpecHelper.within_temp_directory do |temp_dir|
      project = File.join(temp_dir, "counter")
      AmberCLI::Generators::HybridApp.new(project, "counter", ["android"]).generate
      File.exists?(File.join(project, "src/platform/android/app.cr")).should be_true
      File.exists?(File.join(project, "src/counter_web.cr")).should be_false
      File.read(File.join(project, "src/app/counter.cr")).should contain("amber/native")
      File.read(File.join(project, "shard.yml")).should_not contain("grant:")
    end
  end
  it "stages a bundled assets directory into the APK and refuses paths that leave the project" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("counter")
    AmberCLI::Native::AndroidShellGenerator.new(manifest, "counter").files["mobile/android/android-app.properties"].should match(/\nbundledAssets=\z/)
    manifest.android.not_nil!.bundled_assets = "mobile/ios/HappyCoachAssets/assets"
    generator = AmberCLI::Native::AndroidShellGenerator.new(manifest, "counter")
    generator.files["mobile/android/android-app.properties"].should match(/\nbundledAssets=mobile\/ios\/HappyCoachAssets\/assets\z/)
    generator.files["mobile/android/app/build.gradle.kts"].should contain(%(assets.srcDir(stagedBundle)))
    generator.files["mobile/android/app/build.gradle.kts"].should contain(%(it.dir("ap_bundle")))
    generator.files["mobile/android/app/build.gradle.kts"].should contain(%(providers.gradleProperty("amberDebugTrustedCa")))
    generator.files["mobile/android/app/build.gradle.kts"].should contain(%(dependsOn(prepareDebugTrust)))
    manifest.android.not_nil!.bundled_assets = "../outside"
    expect_raises(ArgumentError, /bundled_assets/) { manifest.android.not_nil!.validate! }
    manifest.android.not_nil!.bundled_assets = "/absolute"
    expect_raises(ArgumentError, /bundled_assets/) { manifest.android.not_nil!.validate! }
  end
  it "emits an empty host settings resource and registers it with the runtime before Crystal starts" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("counter")
    files = AmberCLI::Native::AndroidShellGenerator.new(manifest, "counter").files
    settings = files["mobile/android/app/src/main/res/values/host_settings.xml"]
    XML.parse(settings).xpath_string("string(//string[@name='ap_host_settings'])").should eq("")
    settings.should contain(%(translatable="false"))
    activity = files["mobile/android/app/src/main/java/dev/amber/generated/MainActivity.kt"]
    activity.should contain("import dev.assetpipeline.androidhost.HostSettings")
    activity.index("HostSettings.registerSerialized(getString(R.string.ap_host_settings))").not_nil!.should be < activity.index("CrystalBridge.initialize(").not_nil!
  end
  it "emits a continuous Android lane that reads the shard's pins, owns its emulator and reports failures as an issue" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("counter")
    generator = AmberCLI::Native::AndroidShellGenerator.new(manifest, "counter")
    files = generator.files
    android = manifest.android.not_nil!
    generator.ci_matrix.should eq([android.minimum_sdk.to_s, android.target_sdk.to_s, AmberCLI::Native::AndroidShellGenerator::NEWEST_SUPPORTED_ANDROID_RUNTIME].uniq.sort_by(&.to_f))
    workflow = YAML.parse(files[".github/workflows/android-native.yml"])
    native = workflow["jobs"]["native"]
    native["strategy"]["matrix"]["api"].as_a.map(&.as_s).should eq(generator.ci_matrix)
    native["strategy"]["fail-fast"].as_bool.should be_false
    workflow["on"].as_h.keys.map(&.as_s).sort.should eq(["pull_request", "push", "schedule", "workflow_dispatch"])
    workflow["on"]["schedule"].as_a.first["cron"].as_s.should match(/\A\d{1,2} \d{1,2} \* \* \*\z/)
    workflow["permissions"].as_h.size.should eq(1)
    workflow["permissions"]["contents"].as_s.should eq("read")
    steps = native["steps"].as_a
    steps.each { |step| step["continue-on-error"]?.should be_nil }
    workflow["jobs"].as_h.each_value do |job|
      job["steps"].as_a.each do |step|
        if action = step["uses"]?.try(&.as_s)
          action.should match(/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+@[0-9a-f]{40}\z/)
        end
      end
    end
    steps.find { |step| step["name"].as_s == "Install Crystal" }.not_nil!["with"]["crystal"].as_s.should eq(AmberCLI::Native::AndroidShellGenerator::CRYSTAL_VERSION)
    runs = steps.compact_map { |step| step["run"]?.try(&.as_s) }.join("\n")
    runs.should contain("source lib/asset_pipeline/config/android_toolchain.env")
    runs.should contain("bash lib/asset_pipeline/scripts/doctor_android.sh")
    runs.should contain(%(bash lib/asset_pipeline/scripts/ci/android_emulator.sh run "$ANDROID_RUNTIME_API" 5554 -- bash mobile/android/android.sh test emulator-5554))
    runs.should contain("crystal spec --error-trace")
    runs.should contain("git diff --exit-code")
    runs.should_not contain("|| true")
    gate = steps.find { |step| step["name"].as_s == "Build, install and test on the emulator" }.not_nil!
    gate["env"]["ANDROID_RUNTIME_API"].as_s.should eq("${{ matrix.api }}")
    gate["env"]["ANDROID_API"]?.should be_nil
    gate["env"]["EMULATOR_ARCH"].as_s.should eq("x86_64")
    report = workflow["jobs"]["report"]
    report["needs"].as_s.should eq("native")
    report["if"].as_s.should eq("always() && github.event_name != 'pull_request'")
    report["permissions"]["issues"].as_s.should eq("write")
    reporter = report["steps"].as_a.find { |step| step["run"]?.try(&.as_s) == "bash .github/scripts/report_outcome.sh" }.not_nil!
    reporter["env"]["LANE"].as_s.should eq("android-native")
    reporter["env"]["MAINTAINERS"].as_s.should eq("${{ vars.CI_MAINTAINERS }}")
    reporter["env"]["OUTCOME"].as_s.should eq("${{ needs.native.result }}")
    files[".github/scripts/report_outcome.sh"].should start_with("#!/usr/bin/env bash")
    files[".github/scripts/report_outcome.sh"].should contain(%(lane_label="lane:${lane}"))
    files["mobile/android/README.md"].should contain(".github/workflows/android-native.yml")
  end
end
