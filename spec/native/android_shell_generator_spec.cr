require "../amber_cli_spec"
require "xml"
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
    files["mobile/android/app/src/main/java/dev/amber/generated/MainActivity.kt"].should contain("NativeNavigation(this)")
    files["mobile/android/app/src/main/AndroidManifest.xml"].should contain("android:enableOnBackInvokedCallback=\"true\"")
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
    files["mobile/android/app/build.gradle.kts"].should contain("dependsOn(buildCrystal, compileImages)")
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
end
