require "../amber_cli_spec"
require "../../src/amber_cli/native/android_target_installer"
require "../../src/amber_cli/commands/android_target"

module AndroidTargetSpec
  class FailingInstaller < AmberCLI::Native::AndroidTargetInstaller
    property preserve_edit = false
    @writes = 0
    @first : String? = nil

    protected def publish_file(source : String, destination : String) : Nil
      if @writes == 1
        File.write(@first.not_nil!, "concurrent owner edit") if @preserve_edit
        raise IO::Error.new("injected publication failure")
      end
      super
      @first = destination
      @writes += 1
    end
  end

  def self.project(root : String)
    File.write(File.join(root, ".amber.yml"), "type: app\n# Keep my web settings\nwatch:\n  run: existing_web_command\n")
    File.write(File.join(root, "shard.yml"), "name: existing_app\nversion: 0.1.0\ndependencies:\n  amber:\n    path: ../amber\n  asset_pipeline:\n    path: ../asset_pipeline\n")
    File.write(File.join(root, "shard.lock"), "existing dependency lock\n")
    Dir.mkdir_p(File.join(root, "src"))
    File.write(File.join(root, "src/existing_app.cr"), "# Existing web entrypoint remains unchanged\n")
  end

  def self.command(action : String, args : Array(String))
    command = AmberCLI::Commands::AndroidCommand.new(action)
    command.option_parser.unknown_args { |values, _| command.remaining_arguments.concat(values) }
    command.option_parser.parse(args)
    command
  end
end

describe AmberCLI::Native::AndroidTargetInstaller do
  it "plans without writing, then adds a complete native target while preserving web and dependency bytes" do
    SpecHelper.within_temp_directory do |root|
      AndroidTargetSpec.project(root)
      preserved = {".amber.yml", "shard.yml", "shard.lock", "src/existing_app.cr"}.to_h { |path| {path, File.read(path)} }
      installer = AmberCLI::Native::AndroidTargetInstaller.new(root)
      File.exists?("mobile").should be_false
      File.exists?("config").should be_false
      installer.outputs.has_key?("config/native.yml").should be_true
      installer.install
      preserved.each { |path, value| File.read(path).should eq(value) }
      manifest = AmberCLI::Native::CapabilityManifest.load("config/native.yml")
      manifest.app.not_nil!.targets.should eq(["web", "android"])
      manifest.android.not_nil!.application_id.should eq("com.example.existing.app")
      installer.outputs.each { |path, value| File.read(path).should eq(value) }
      File::Info.executable?("mobile/android/android.sh").should be_true
      File::Info.executable?("mobile/android/gradlew").should be_true
      Dir.children(root).any?(&.starts_with?(".amber-android-target")).should be_false
    end
  end

  it "preserves an existing explicit v2 native manifest and its public configuration" do
    SpecHelper.within_temp_directory do |root|
      AndroidTargetSpec.project(root)
      Dir.mkdir("config")
      manifest = AmberCLI::Native::CapabilityManifest.default_for("existing_app")
      manifest.app.not_nil!.targets = ["web", "android"]
      manifest.android.not_nil!.application_id = "org.example.reference"
      value = "# Preserve my manifest comment\n" + manifest.to_yaml_document
      File.write("config/native.yml", value)
      installer = AmberCLI::Native::AndroidTargetInstaller.new(root)
      installer.outputs.has_key?("config/native.yml").should be_false
      installer.install
      File.read("config/native.yml").should eq(value)
      File.read("mobile/android/android-app.properties").should contain("applicationId=org.example.reference")
    end
  end

  {"src/app/counter.cr", "config/android_assets.yml", "mobile/android/app/src/main/res/values/strings.xml"}.each do |collision|
    it "rejects #{collision} before writing any other target file" do
      SpecHelper.within_temp_directory do |root|
        AndroidTargetSpec.project(root)
        Dir.mkdir_p(File.dirname(collision))
        File.write(collision, "keep")
        expect_raises(ArgumentError, "Refusing to overwrite") { AmberCLI::Native::AndroidTargetInstaller.new(root) }
        File.read(collision).should eq("keep")
        File.exists?("src/platform/android/app.cr").should be_false
        File.exists?("config/native.yml").should be_false
      end
    end
  end

  it "rejects a dangling destination symlink without following or replacing it" do
    SpecHelper.within_temp_directory do |root|
      AndroidTargetSpec.project(root)
      Dir.mkdir("config")
      File.symlink("missing-user-file", "config/android_assets.yml")
      expect_raises(ArgumentError, "Refusing to overwrite") { AmberCLI::Native::AndroidTargetInstaller.new(root) }
      File.symlink?("config/android_assets.yml").should be_true
      File.exists?("mobile").should be_false
    end
  end

  it "rejects a symlinked output parent even when no destination exists" do
    SpecHelper.within_temp_directory do |root|
      AndroidTargetSpec.project(root)
      Dir.mkdir("outside")
      File.symlink(File.join(root, "outside"), "mobile")
      expect_raises(ArgumentError, "real directory") { AmberCLI::Native::AndroidTargetInstaller.new(root) }
      Dir.empty?("outside").should be_true
    end
  end

  it "rechecks collisions when a previously planned installation is applied" do
    SpecHelper.within_temp_directory do |root|
      AndroidTargetSpec.project(root)
      installer = AmberCLI::Native::AndroidTargetInstaller.new(root)
      Dir.mkdir("config")
      File.write("config/native.yml", "arrived after dry run")
      expect_raises(ArgumentError, "Refusing to overwrite") { installer.install }
      File.read("config/native.yml").should eq("arrived after dry run")
      File.exists?("mobile").should be_false
    end
  end

  it "does not silently migrate Apple v1 or a custom configured manifest" do
    SpecHelper.within_temp_directory do |root|
      AndroidTargetSpec.project(root)
      Dir.mkdir("config")
      apple = AmberCLI::Native::CapabilityManifest.default_for("existing_app")
      apple.schema_version = 1
      apple.app = nil
      apple.android = nil
      File.write("config/native.yml", apple.to_yaml_document)
      expect_raises(ArgumentError, "v2 manifest") { AmberCLI::Native::AndroidTargetInstaller.new(root) }
      File.write(".amber.yml", "native_manifest: config/other-native.yml\n")
      expect_raises(ArgumentError, "custom manifest") { AmberCLI::Native::AndroidTargetInstaller.new(root) }
      File.exists?("mobile").should be_false
    end
  end

  it "rejects missing dependencies without installing or editing them" do
    SpecHelper.within_temp_directory do |root|
      AndroidTargetSpec.project(root)
      File.write("shard.yml", "name: existing_app\n")
      expect_raises(ArgumentError, "Declare Android-capable") { AmberCLI::Native::AndroidTargetInstaller.new(root) }
      File.read("shard.yml").should eq("name: existing_app\n")
      File.exists?("lib").should be_false
      File.exists?("mobile").should be_false
    end
  end

  it "rolls back its own unchanged files and directories after partial publication" do
    SpecHelper.within_temp_directory do |root|
      AndroidTargetSpec.project(root)
      initial = Dir.glob("**/*", match: File::MatchOptions.glob_default | File::MatchOptions::DotFiles).sort
      installer = AndroidTargetSpec::FailingInstaller.new(root)
      expect_raises(IO::Error, "injected publication failure") { installer.install }
      Dir.glob("**/*", match: File::MatchOptions.glob_default | File::MatchOptions::DotFiles).sort.should eq(initial)
      File.read("shard.lock").should eq("existing dependency lock\n")
    end
  end

  it "does not roll back an installed file that another owner has changed" do
    SpecHelper.within_temp_directory do |root|
      AndroidTargetSpec.project(root)
      installer = AndroidTargetSpec::FailingInstaller.new(root)
      installer.preserve_edit = true
      first_path = installer.outputs.keys.first
      expect_raises(IO::Error, "injected publication failure") { installer.install }
      File.read(first_path).should eq("concurrent owner edit")
      File.exists?(installer.outputs.keys[1]).should be_false
      Dir.children(root).any?(&.starts_with?(".amber-android-target")).should be_false
    end
  end
end

describe AmberCLI::Commands::AndroidCommand do
  it "uses an exact executable/argument vector and supports project paths with spaces" do
    SpecHelper.within_temp_directory do |root|
      project = File.join(root, "app with spaces")
      Dir.mkdir_p(File.join(project, "mobile/android"))
      File.write(File.join(project, "mobile/android/android.sh"), "exit 0\n")
      invocation = AndroidTargetSpec.command("run", ["android", "--project", project, "--device", "emulator-5556"]).invocation
      actual_root = File.realpath(project)
      invocation.should eq({"bash", [File.join(actual_root, "mobile/android/android.sh"), "run", "emulator-5556"], actual_root})
    end
  end

  {"run", "test"}.each do |action|
    it "requires explicit device selection for #{action}" do
      expect_raises(ArgumentError, "requires --device") { AndroidTargetSpec.command(action, ["android"]).invocation }
    end
  end

  {"", "-d", "device;touch-pwned", "device\nother", "$(id)", "a" * 257}.each do |serial|
    it "rejects malformed serial #{serial.inspect}" do
      expect_raises(ArgumentError, "requires --device") { AndroidTargetSpec.command("test", ["android", "--device=#{serial}"]).invocation }
    end
  end

  it "rejects a device on build, a non-Android target and missing target files" do
    expect_raises(ArgumentError, "only used by run/test") { AndroidTargetSpec.command("build", ["android", "--device=emulator-5556"]).invocation }
    expect_raises(ArgumentError, "android target explicitly") { AndroidTargetSpec.command("build", ["web"]).invocation }
    SpecHelper.within_temp_directory do |root|
      expect_raises(ArgumentError, "No Android target") { AndroidTargetSpec.command("doctor", ["android", "--project", root]).invocation }
    end
  end
end
