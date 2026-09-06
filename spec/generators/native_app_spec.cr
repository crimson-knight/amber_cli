require "../amber_cli_spec"
require "../../src/amber_cli/generators/native_app"

describe AmberCLI::Generators::NativeApp do
  describe "#generate" do
    it "creates the full native app project structure" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "test_native_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "test_native_app")
        generator.generate

        # Verify top-level files exist
        File.exists?(File.join(project_path, "shard.yml")).should be_true
        File.exists?(File.join(project_path, ".amber.yml")).should be_true
        File.exists?(File.join(project_path, ".gitignore")).should be_true
        File.exists?(File.join(project_path, "Makefile")).should be_true
        File.exists?(File.join(project_path, "CLAUDE.md")).should be_true
        File.exists?(File.join(project_path, "config/native.yml")).should be_true
        File.exists?(File.join(project_path, "mobile/apple/generated/README.md")).should be_true
      end
    end

    it "creates shard.yml with correct dependencies" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        shard_content = File.read(File.join(project_path, "shard.yml"))

        # Must have amber (patterns only)
        shard_content.should contain("amber:")
        shard_content.should contain("crimson-knight/amber")

        # Must have asset_pipeline with cross-platform branch
        shard_content.should contain("asset_pipeline:")
        shard_content.should contain("feature/utility-first-css-asset-pipeline")

        # Must have crystal-audio
        shard_content.should contain("crystal-audio:")

        # Must have correct project name
        shard_content.should contain("name: my_app")
        shard_content.should contain("main: src/my_app.cr")
      end
    end

    it "creates amber.yml with type: native" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        amber_content = File.read(File.join(project_path, ".amber.yml"))
        amber_content.should contain("type: native")
        amber_content.should contain("app: my_app")
        amber_content.should contain("native_manifest: config/native.yml")
      end
    end

    it "creates main file WITHOUT HTTP server" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        main_content = File.read(File.join(project_path, "src/my_app.cr"))

        # MUST use Amber.settings directly
        main_content.should contain("Amber.settings.name")

        # MUST NOT start an HTTP server
        main_content.should_not contain("Amber::Server.start")

        # Comments warn about Server.configure but it must not appear as actual code.
        # Filter out comment lines and check no code line invokes it.
        code_lines = main_content.lines.reject { |l| l.strip.starts_with?("#") }
        code_lines.none? { |l| l.includes?("Amber::Server.configure") }.should be_true

        # MUST require asset_pipeline/ui (not just "ui")
        main_content.should contain("require \"asset_pipeline/ui\"")
      end
    end

    it "creates config without HTTP server" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        config_content = File.read(File.join(project_path, "config/application.cr"))
        config_content.should contain("Amber.settings.name")

        # Comments warn about Server.configure but it must not appear as actual code.
        code_lines = config_content.lines.reject { |l| l.strip.starts_with?("#") }
        code_lines.none? { |l| l.includes?("Amber::Server.configure") }.should be_true
      end
    end

    it "creates Makefile with correct platform flags" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        makefile_content = File.read(File.join(project_path, "Makefile"))

        # CRITICAL: -Dmacos flag must be present
        makefile_content.should contain("-Dmacos")

        # Must have crystal-alpha compiler
        makefile_content.should contain("crystal-alpha")

        # Must have -fno-objc-arc for ObjC bridge
        makefile_content.should contain("-fno-objc-arc")

        # Must have framework link flags
        makefile_content.should contain("-framework AppKit")
        makefile_content.should contain("-framework Foundation")
        makefile_content.should contain("-framework AVFoundation")
        makefile_content.should contain("-lobjc")

        # Must have crystal-audio symlink in setup
        makefile_content.should contain("ln -sf crystal-audio lib/crystal_audio")

        # Must have build targets
        makefile_content.should contain("macos:")
        makefile_content.should contain("macos-release:")
        makefile_content.should contain("setup:")
        makefile_content.should contain("spec:")
      end
    end

    it "creates FSDD process manager structure" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        # Process manager exists
        File.exists?(File.join(project_path, "src/process_managers/main_process_manager.cr")).should be_true

        pm_content = File.read(File.join(project_path, "src/process_managers/main_process_manager.cr"))
        pm_content.should contain("module ProcessManagers")
        pm_content.should contain("class MainProcessManager")

        # Controller delegates to process manager
        ctrl_content = File.read(File.join(project_path, "src/controllers/main_controller.cr"))
        ctrl_content.should contain("@process_manager")
        ctrl_content.should contain("ProcessManagers::MainProcessManager")
      end
    end

    it "creates event bus" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        File.exists?(File.join(project_path, "src/events/event_bus.cr")).should be_true
        content = File.read(File.join(project_path, "src/events/event_bus.cr"))
        content.should contain("module Events")
        content.should contain("class EventBus")
      end
    end

    it "creates ObjC platform bridge with GCD helpers" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        bridge_path = File.join(project_path, "src/platform/my_app_platform_bridge.m")
        File.exists?(bridge_path).should be_true

        bridge_content = File.read(bridge_path)
        # Must have GCD dispatch helpers (never use Crystal spawn in NSApp)
        bridge_content.should contain("dispatch_to_main")
        bridge_content.should contain("dispatch_to_background")
        bridge_content.should contain("dispatch_async")

        # Must document the alias vs type rule for C function pointers
        bridge_content.should contain("alias")
      end
    end

    it "creates L1 Crystal specs" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        # Desktop specs
        File.exists?(File.join(project_path, "spec/spec_helper.cr")).should be_true
        File.exists?(File.join(project_path, "spec/macos/process_manager_spec.cr")).should be_true

        # Mobile bridge specs
        File.exists?(File.join(project_path, "mobile/shared/spec/bridge_spec.cr")).should be_true

        spec_content = File.read(File.join(project_path, "spec/macos/process_manager_spec.cr"))
        spec_content.should contain("ProcessManagers::MainProcessManager")
      end
    end

    it "creates mobile shared bridge with state machine" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        bridge_path = File.join(project_path, "mobile/shared/bridge.cr")
        File.exists?(bridge_path).should be_true

        content = File.read(bridge_path)
        content.should contain("enum AppState")
        content.should contain("class Bridge")
        content.should contain("transition_to")
      end
    end

    it "creates iOS build script with _main fix and correct flags" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        script_path = File.join(project_path, "mobile/ios/build_crystal_lib.sh")
        File.exists?(script_path).should be_true

        content = File.read(script_path)
        # CRITICAL: Must fix _main symbol conflict for iOS
        content.should contain("unexported_symbol _main")
        content.should contain("-Dios")
        content.should contain("crystal-alpha")
        content.should contain("MIN_IOS_VER=\"16.1\"")
        content.should contain("GC_ARCHIVE_URL=")
        content.should contain("cmake --build")
        content.should contain("libgc.a")

        # Must be executable
        File.info(script_path).permissions.owner_execute?.should be_true
      end
    end

    it "creates iOS project.yml with correct exclusions" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        content = File.read(File.join(project_path, "mobile/ios/project.yml"))
        # CRITICAL: Crystal only compiles arm64 — must exclude x86_64
        content.should contain("EXCLUDED_ARCHS")
        content.should contain("x86_64")
        content.should contain("../apple/generated/AppIntents")
        content.should contain("../apple/generated/Notifications")
        content.should contain("../apple/generated/WidgetKit")
        content.should contain("../apple/generated/ActivityKit")
        content.should contain("MyAppAppleShellExtension")
        content.should contain("PRODUCT_BUNDLE_IDENTIFIER: com.example.my.app")
        content.should contain("GENERATE_INFOPLIST_FILE: YES")
      end
    end

    it "creates a native capability manifest and generator-owned Apple shell files" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        manifest = File.read(File.join(project_path, "config/native.yml"))
        manifest.should contain("schema_version: 2")
        manifest.should contain("bundle_identifier: com.example.my.app")
        manifest.should contain("minimum_ios_version: \"16.1\"")
        manifest.should contain("widgets:")
        manifest.should contain("live_activities:")
        manifest.should contain("shortcuts:")
        manifest.should contain("notifications:")
        manifest.should contain("quick_actions:")

        ownership = File.read(File.join(project_path, "mobile/apple/generated/README.md"))
        ownership.should contain("generator-owned")
        ownership.should contain("config/native.yml")
        ownership.should contain("mobile/ios/Sources")

        widget_scaffold = File.read(File.join(project_path, "mobile/apple/generated/WidgetKit/WidgetKitScaffold.swift"))
        widget_scaffold.should contain("Generated by amber_cli")
        widget_scaffold.should contain("import WidgetKit")
        widget_scaffold.should contain("enum MyAppWidgetKitScaffold")
        widget_scaffold.should contain("MyAppStatusWidget: Widget")

        widget_bundle = File.read(File.join(project_path, "mobile/apple/generated/WidgetKit/MyAppWidgetBundle.swift"))
        widget_bundle.should contain("@main")
        widget_bundle.should contain("struct MyAppWidgetBundle: WidgetBundle")
        widget_bundle.should contain("MyAppStatusWidget()")

        widget_info_plist = File.read(File.join(project_path, "mobile/apple/generated/WidgetKit/Info.plist"))
        widget_info_plist.should contain("CFBundleIdentifier")
        widget_info_plist.should contain("$(PRODUCT_BUNDLE_IDENTIFIER)")

        activity_scaffold = File.read(File.join(project_path, "mobile/apple/generated/ActivityKit/ActivityKitScaffold.swift"))
        activity_scaffold.should contain("import ActivityKit")
        activity_scaffold.should contain("public enum MyAppLiveActivities")
        activity_scaffold.should contain("public struct MyAppActivityAttributes: ActivityAttributes")

        intents_scaffold = File.read(File.join(project_path, "mobile/apple/generated/AppIntents/AppIntentsScaffold.swift"))
        intents_scaffold.should contain("import AppIntents")
        intents_scaffold.should contain("enum MyAppAppIntentsScaffold")
        intents_scaffold.should contain("struct OpenMyAppIntent: AppIntent")

        intents_provider = File.read(File.join(project_path, "mobile/apple/generated/AppIntents/MyAppAppShortcutsProvider.swift"))
        intents_provider.should contain("struct MyAppAppShortcutsProvider: AppShortcutsProvider")
        intents_provider.should contain("AppShortcut(")
        intents_provider.should contain("\\(.applicationName)")

        notifications_scaffold = File.read(File.join(project_path, "mobile/apple/generated/Notifications/NotificationsScaffold.swift"))
        notifications_scaffold.should contain("import UserNotifications")
        notifications_scaffold.should contain("public enum MyAppNotifications")

        quick_actions = File.read(File.join(project_path, "mobile/apple/generated/QuickActions/UIApplicationShortcutItems.plist.fragment"))
        quick_actions.should contain("UIApplicationShortcutItemType")
        quick_actions.should contain("com.example.my.app.open")

        host_app = File.read(File.join(project_path, "mobile/ios/Sources/MyAppApp.swift"))
        host_app.should contain("@main")
        host_app.should contain("struct MyAppApp: App")

        app_delegate = File.read(File.join(project_path, "mobile/ios/Sources/MyAppAppDelegate.swift"))
        app_delegate.should contain("MyAppNotificationsBootstrap.registerCategories()")
      end
    end

    it "builds Android through the canonical runtime with verified per-ABI dependencies" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        script_path = File.join(project_path, "mobile/android/build_crystal_lib.sh")
        File.exists?(script_path).should be_true

        content = File.read(script_path)
        content.should contain("scripts/cross_compile_deps.sh")
        content.should contain("scripts/build_android.sh")
        content.should contain("src/ui/native/android_host_jni.c")
        content.should contain("src/ui/native/android_private_files.c")
        content.should contain("src/platform/android/app.cr")
        content.should contain("android_each_abi")
        content.should_not contain("crystal-alpha")
        content.should_not contain("-laaudio")

        # Must be executable
        File.info(script_path).permissions.owner_execute?.should be_true
      end
    end

    it "creates a complete Android View Gradle project with the pinned shared toolchain" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        content = File.read(File.join(project_path, "mobile/android/app/build.gradle.kts"))
        content.should contain("ANDROID_JAVA_VERSION")
        content.should contain("ANDROID_NDK_VERSION")
        content.should_not contain("compose")
        content.should contain("android/runtime/src/main/java")
        File.exists?(File.join(project_path, "mobile/android/settings.gradle.kts")).should be_true
        File.exists?(File.join(project_path, "mobile/android/gradle/wrapper/gradle-wrapper.jar")).should be_true
      end
    end

    it "creates iOS UI test template with test_id convention" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        content = File.read(File.join(project_path, "mobile/ios/UITests/UITests.swift"))
        content.should contain("XCTestCase")
        content.should contain("accessibilityIdentifier")
        content.should contain("{epic}.{story}-{element-name}")
      end
    end

    it "creates an Android native View test that launches the app and finds renderer content" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        content = File.read(File.join(project_path, "mobile/android/app/src/androidTest/java/dev/amber/generated/NativeApplicationTest.kt"))
        content.should contain("ActivityScenario.launch(MainActivity::class.java)")
        content.should contain("persisted_count")
        content.should contain("debugPendingServices()")
        content.should contain("scenario.recreate()")
        content.should_not contain("assert(true)")
      end
    end

    it "coordinates composing text and external edits in the generated Android input test" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "composing_app")
        AmberCLI::Generators::NativeApp.new(project_path, "composing_app").generate
        content = File.read(File.join(project_path, "mobile/android/app/src/androidTest/java/dev/amber/generated/NativeApplicationTest.kt"))
        content.should contain(%(assertEquals("Android", editor.text.toString())))
        composing = content.index("connection.setComposingRegion(0, editor.text.length)").not_nil!
        finished = content.index("connection.finishComposingText()").not_nil!
        appended = content.index("connection.commitText(").not_nil!
        published = content.index("publishExternalEdit(editor)").not_nil!
        composing.should be < finished
        finished.should be < appended
        appended.should be < published
        content.should contain("assertEquals(-1, BaseInputConnection.getComposingSpanStart(editor.text))")
        content.should contain("Build.VERSION.SDK_INT >= 33")
        content.should contain("keyboard.invalidateInput(editor)")
        content.should contain("keyboard.restartInput(editor)")
        content.should_not contain("SHOW_FORCED")
      end
    end

    it "rejects missing or failed host reports and crashed instrumentation even when tools return zero" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "failed_device_app")
        AmberCLI::Generators::NativeApp.new(project_path, "failed_device_app").generate
        android_dir = File.join(project_path, "mobile/android")
        sdk = File.join(temp_dir, "sdk")
        Dir.mkdir_p(File.join(sdk, "platform-tools"))
        adb = File.join(sdk, "platform-tools/adb")
        File.write(adb, "#!/usr/bin/env bash\ncase \"$*\" in *get-state*) echo device;; *getprop*) echo 1;; *'am instrument'*) echo 'INSTRUMENTATION_RESULT: shortMsg=Process crashed'; echo 'INSTRUMENTATION_CODE: 0';; esac\nexit 0\n")
        File.chmod(adb, 0o755)
        env_dir = File.join(project_path, "lib/asset_pipeline/scripts")
        Dir.mkdir_p(env_dir)
        File.write(File.join(env_dir, "android_env.sh"), "ANDROID_RESOLVED_SDK_ROOT='#{sdk}'\nANDROID_RESOLVED_JAVA_HOME='#{temp_dir}'\nandroid_resolve_sdk_root() { :; }\nandroid_resolve_java_home() { :; }\n")
        gradle = File.join(android_dir, "gradlew")
        File.write(gradle, "#!/usr/bin/env bash\nexit 0\n")
        File.chmod(gradle, 0o755)
        output = IO::Memory.new
        result = Process.run("bash", [File.join(android_dir, "test_android.sh"), "fake-serial"], output: output, error: output)
        result.success?.should be_false
        output.to_s.should contain("Missing canonical host-session unit test report")
        File.exists?(File.join(project_path, "build/android-test-evidence/instrumentation.txt")).should be_false

        # This shell-protocol fixture stubs Gradle/ADB. Give the crash case a
        # passing prerequisite report so it actually reaches instrumentation;
        # the real generated-consumer lane executes the canonical JVM tests.
        report = File.join(android_dir, "app/build/test-results/testDebugUnitTest/TEST-dev.assetpipeline.androidhost.HostSessionTest.xml")
        Dir.mkdir_p(File.dirname(report))
        [{0, 0, 0}, {1, 1, 0}, {1, 0, 1}].each do |counts|
          File.write(report, %(<testsuite tests="#{counts[0]}" failures="#{counts[1]}" errors="#{counts[2]}"/>))
          output = IO::Memory.new
          result = Process.run("bash", [File.join(android_dir, "test_android.sh"), "fake-serial"], output: output, error: output)
          result.success?.should be_false
          output.to_s.should contain("Host-session unit tests were empty or failed")
          File.exists?(File.join(project_path, "build/android-test-evidence/instrumentation.txt")).should be_false
        end
        File.write(report, %(<testsuite tests="1" failures="0" errors="0"/>))
        # The same mandatory-report gate covers asynchronous-service unit tests.
        service_report = File.join(File.dirname(report), "TEST-dev.assetpipeline.androidhost.ServiceQueueTest.xml")
        output = IO::Memory.new
        result = Process.run("bash", [File.join(android_dir, "test_android.sh"), "fake-serial"], output: output, error: output)
        result.success?.should be_false
        output.to_s.should contain("Missing canonical service-queue unit test report")
        [{0, 0, 0}, {1, 1, 0}, {1, 0, 1}].each do |counts|
          File.write(service_report, %(<testsuite tests="#{counts[0]}" failures="#{counts[1]}" errors="#{counts[2]}"/>))
          output = IO::Memory.new
          result = Process.run("bash", [File.join(android_dir, "test_android.sh"), "fake-serial"], output: output, error: output)
          result.success?.should be_false
          output.to_s.should contain("Service-queue unit tests were empty or failed")
          File.exists?(File.join(project_path, "build/android-test-evidence/instrumentation.txt")).should be_false
        end
        File.write(service_report, %(<testsuite tests="1" failures="0" errors="0"/>))
        ["HttpWireTest", "PlatformHttpTest", "SecretVaultTest", "FilePolicyTest", "NotificationWireTest", "PermissionRequestsTest", "EditorActionsTest", "LayoutPolicyTest", "ViewStatePolicyTest", "SemanticsPolicyTest", "CompoundFocusPolicyTest", "DialogPolicyTest", "SheetPolicyTest"].each do |suite|
          http_report = File.join(File.dirname(report), "TEST-dev.assetpipeline.androidhost.#{suite}.xml")
          output = IO::Memory.new
          result = Process.run("bash", [File.join(android_dir, "test_android.sh"), "fake-serial"], output: output, error: output)
          result.success?.should be_false
          output.to_s.should contain("Missing canonical service unit test report: #{suite}")
          [{0, 0, 0}, {1, 1, 0}, {1, 0, 1}].each do |counts|
            File.write(http_report, %(<testsuite tests="#{counts[0]}" failures="#{counts[1]}" errors="#{counts[2]}"/>))
            output = IO::Memory.new
            result = Process.run("bash", [File.join(android_dir, "test_android.sh"), "fake-serial"], output: output, error: output)
            result.success?.should be_false
            output.to_s.should contain("Service unit tests were empty or failed: #{suite}")
            File.exists?(File.join(project_path, "build/android-test-evidence/instrumentation.txt")).should be_false
          end
          File.write(http_report, %(<testsuite tests="1" failures="0" errors="0"/>))
        end
        output = IO::Memory.new
        result = Process.run("bash", [File.join(android_dir, "test_android.sh"), "fake-serial"], output: output, error: output)
        result.success?.should be_false
        File.read(File.join(project_path, "build/android-test-evidence/instrumentation.txt")).should contain("Process crashed")
        output.to_s.should_not contain("[pass] Android tests pass")
        output.to_s.should_not contain("Skipped (no device)")
      end
    end

    it "creates L3 E2E test scripts" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        # iOS E2E
        ios_script = File.join(project_path, "mobile/ios/test_ios.sh")
        File.exists?(ios_script).should be_true
        File.info(ios_script).permissions.owner_execute?.should be_true

        # Android E2E
        android_script = File.join(project_path, "mobile/android/test_android.sh")
        File.exists?(android_script).should be_true
        File.info(android_script).permissions.owner_execute?.should be_true
        File.read(android_script).should_not contain("Skipped (no device)")
        File.read(android_script).should contain("android.sh\" test")
        File.exists?(File.join(project_path, "mobile/android/local.properties")).should be_false

        # macOS E2E
        macos_e2e = File.join(project_path, "test/macos/test_macos_e2e.sh")
        File.exists?(macos_e2e).should be_true
        File.info(macos_e2e).permissions.owner_execute?.should be_true

        # macOS UI tests
        macos_ui = File.join(project_path, "test/macos/test_macos_ui.sh")
        File.exists?(macos_ui).should be_true
        File.info(macos_ui).permissions.owner_execute?.should be_true
      end
    end

    it "creates CI orchestrator script" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        ci_script = File.join(project_path, "mobile/run_all_tests.sh")
        File.exists?(ci_script).should be_true
        File.info(ci_script).permissions.owner_execute?.should be_true

        content = File.read(ci_script)
        content.should contain("--e2e")
        content.should contain("L1")
        content.should contain("L2")
        content.should contain("L3")
        content.should contain("ANDROID_SERIAL")
        content.should_not contain("mobile/android/test_android.sh 2>/dev/null || true")
      end
    end

    it "propagates Android failure through the generated all-platform orchestrator" do
      SpecHelper.within_temp_directory do |temp_dir|
        project = File.join(temp_dir, "failed_android")
        AmberCLI::Generators::NativeApp.new(project, "failed_android").generate
        bin = File.join(temp_dir, "bin")
        Dir.mkdir_p(bin)
        File.write(File.join(bin, "crystal-alpha"), "#!/usr/bin/env bash\nexit 0\n")
        File.chmod(File.join(bin, "crystal-alpha"), 0o755)
        {"test/macos/test_macos_ui.sh", "test/macos/test_macos_e2e.sh", "mobile/ios/test_ios.sh"}.each do |path|
          File.write(File.join(project, path), "#!/usr/bin/env bash\nexit 0\n")
        end
        File.write(File.join(project, "mobile/android/test_android.sh"), "#!/usr/bin/env bash\n[[ \"$1\" == fake-serial ]] || exit 4\necho 'Android failure reached orchestrator'\nexit 9\n")
        output = IO::Memory.new
        result = Process.run("bash", [File.join(project, "mobile/run_all_tests.sh"), "--e2e"],
          env: {"PATH" => "#{bin}:#{ENV["PATH"]}", "ANDROID_SERIAL" => "fake-serial"},
          output: output, error: output)
        result.success?.should be_false
        output.to_s.should contain("Android failure reached orchestrator")
        output.to_s.should contain("1 FAILED")
        output.to_s.should_not match(/\[pass\].*Android E2E/)
      end
    end

    it "creates FSDD documentation structure" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        File.exists?(File.join(project_path, "docs/fsdd/_index.md")).should be_true
        File.exists?(File.join(project_path, "docs/fsdd/testing/TESTING_ARCHITECTURE.md")).should be_true

        testing_content = File.read(File.join(project_path, "docs/fsdd/testing/TESTING_ARCHITECTURE.md"))
        testing_content.should contain("Three-Layer Test Strategy")
        testing_content.should contain("L1: Crystal Specs")
        testing_content.should contain("L2: Platform UI Tests")
        testing_content.should contain("L3: E2E Scripts")
        testing_content.should contain("test_id")
      end
    end

    it "uses correct pascal case for project names with underscores" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_cool_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_cool_app")
        generator.generate

        main_content = File.read(File.join(project_path, "src/my_cool_app.cr"))
        main_content.should contain("MyCoolApp")
      end
    end

    it "uses correct pascal case for project names with hyphens" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my-cool-app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my-cool-app")
        generator.generate

        main_content = File.read(File.join(project_path, "src/my-cool-app.cr"))
        main_content.should contain("MyCoolApp")
      end
    end

    it "does not create web-specific directories" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        # Native apps should NOT have these web-specific directories
        Dir.exists?(File.join(project_path, "public")).should be_false
        Dir.exists?(File.join(project_path, "src/views")).should be_false
        Dir.exists?(File.join(project_path, "src/channels")).should be_false
        Dir.exists?(File.join(project_path, "src/sockets")).should be_false
        Dir.exists?(File.join(project_path, "src/mailers")).should be_false
        Dir.exists?(File.join(project_path, "src/jobs")).should be_false
        Dir.exists?(File.join(project_path, "db")).should be_false
      end
    end

    it "creates the correct directory structure" do
      SpecHelper.within_temp_directory do |temp_dir|
        project_path = File.join(temp_dir, "my_app")
        generator = AmberCLI::Generators::NativeApp.new(project_path, "my_app")
        generator.generate

        # Native app directories
        Dir.exists?(File.join(project_path, "src/controllers")).should be_true
        Dir.exists?(File.join(project_path, "src/models")).should be_true
        Dir.exists?(File.join(project_path, "src/process_managers")).should be_true
        Dir.exists?(File.join(project_path, "src/ui")).should be_true
        Dir.exists?(File.join(project_path, "src/platform")).should be_true
        Dir.exists?(File.join(project_path, "src/events")).should be_true
        Dir.exists?(File.join(project_path, "spec/macos")).should be_true
        Dir.exists?(File.join(project_path, "mobile/shared")).should be_true
        Dir.exists?(File.join(project_path, "mobile/ios")).should be_true
        Dir.exists?(File.join(project_path, "mobile/android")).should be_true
        Dir.exists?(File.join(project_path, "test/macos")).should be_true
        Dir.exists?(File.join(project_path, "docs/fsdd")).should be_true
      end
    end
  end
end
