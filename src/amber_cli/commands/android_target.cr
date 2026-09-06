require "../core/base_command"
require "../native/android_target_installer"

module AmberCLI::Commands
  class TargetCommand < AmberCLI::Core::BaseCommand
    getter project_path : String = Dir.current
    getter dry_run : Bool = false

    def help_description : String
      "Add a native Android target without replacing an existing Amber web app"
    end

    def setup_command_options
      option_parser.banner = "Usage: amber target add android [--project PATH] [--dry-run]"
      option_parser.on("--project=PATH", "Existing Amber project directory") { |value| @project_path = value }
      option_parser.on("--dry-run", "Validate and list new files without writing") { @dry_run = true }
    end

    def execute
      raise ArgumentError.new("Usage: amber target add android [--project PATH] [--dry-run]") unless remaining_arguments == ["add", "android"]
      installer = Native::AndroidTargetInstaller.new(@project_path)
      if @dry_run
        installer.outputs.keys.sort.each { |path| puts "create #{path}" }
        puts "Dry run: no files or dependencies changed."
      else
        installer.install
        puts "Added Android starter. Existing web files, dependencies and native manifest were preserved."
        puts "Install Android-capable dependencies, then run amber doctor android and amber test android --device <serial>."
        puts "The starter is not a native conversion of existing web pages; see mobile/android/README.md."
      end
    rescue error : ArgumentError | File::Error | YAML::ParseException
      exit!(error.message || "Android target attachment failed", error: true)
    end
  end

  class AndroidCommand < AmberCLI::Core::BaseCommand
    getter project_path : String = Dir.current
    getter device : String? = nil

    def help_description : String
      "Build, inspect or run the project's native Android target"
    end

    def setup_command_options
      option_parser.banner = "Usage: amber #{@command_name} android [--project PATH] [--device SERIAL]"
      option_parser.on("--project=PATH", "Amber project directory") { |value| @project_path = value }
      option_parser.on("--device=SERIAL", "Explicit ADB target; required for run/test") { |value| @device = value }
    end

    # Return an argument vector, never a shell-interpolated command string.
    def invocation : {String, Array(String), String}
      raise ArgumentError.new("Select the android target explicitly") unless remaining_arguments == ["android"]
      raise ArgumentError.new("Unsupported Android action") unless {"doctor", "build", "run", "test"}.includes?(@command_name)
      if {"run", "test"}.includes?(@command_name)
        serial = @device
        unless serial && !serial.empty? && serial.bytesize <= 256 && serial.matches?(/\A[a-zA-Z0-9_.:\[\]-]+\z/) && !serial.starts_with?('-')
          raise ArgumentError.new("Run/test requires --device with an explicit ADB serial; no device was selected")
        end
      elsif @device
        raise ArgumentError.new("--device is only used by run/test")
      end
      root = File.realpath(@project_path)
      script = File.join(root, "mobile/android/android.sh")
      raise ArgumentError.new("No Android target found; run amber target add android") unless File.file?(script)
      args = [script, @command_name]
      args << @device.not_nil! if @device
      {"bash", args, root}
    end

    def execute
      executable, arguments, root = invocation
      status = Process.run(executable, arguments, chdir: root,
        input: Process::Redirect::Inherit, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      exit(status.exit_code)
    rescue error : ArgumentError | File::Error
      exit!(error.message || "Android command failed", error: true)
    end
  end
end

AmberCLI::Core::CommandRegistry.register("target", ([] of String), AmberCLI::Commands::TargetCommand)
{"doctor", "build", "run", "test"}.each do |name|
  AmberCLI::Core::CommandRegistry.register(name, ([] of String), AmberCLI::Commands::AndroidCommand)
end
