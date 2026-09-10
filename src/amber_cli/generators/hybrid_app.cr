require "../native/android_shell_generator"

module AmberCLI::Generators
  class HybridApp
    def initialize(@path : String, @name : String, @targets = ["web", "android"] of String)
      unless @name.matches?(/\A[a-z][a-z0-9_-]*\z/)
        raise ArgumentError.new("Use a lowercase project name containing letters, digits, underscores or hyphens")
      end
      unless @targets.includes?("android") && @targets.uniq.size == @targets.size && @targets.all? { |target| {"web", "android"}.includes?(target) }
        raise ArgumentError.new("This generator supports android or web,android targets")
      end
    end

    def generate : Nil
      if Dir.exists?(@path) && Dir.children(@path).any? { |entry| entry != ".git" }
        raise ArgumentError.new("Generate into an empty directory; existing application files will not be overwritten")
      end
      manifest = AmberCLI::Native::CapabilityManifest.default_for(@name)
      manifest.app.not_nil!.targets = @targets
      manifest.validate!
      shell = AmberCLI::Native::AndroidShellGenerator.new(manifest, @name)
      outputs = shell.files
      outputs["config/native.yml"] = manifest.to_yaml_document
      outputs[".amber.yml"] = {"app" => @name, "type" => (@targets.includes?("web") ? "hybrid" : "native"), "native_manifest" => "config/native.yml"}.to_yaml
      outputs[".gitignore"] = "/lib/\n/bin/\n/build/\n/.shards/\n*.dwarf\n.DS_Store\n"
      outputs["shard.yml"] = shard_yml
      if @targets.includes?("web")
        outputs["src/platform/web/counter_controller.cr"] = {{ read_file("#{__DIR__}/../templates/android/web_controller.cr") }}
        outputs["src/#{@name}_web.cr"] = <<-CRYSTAL
require "amber"
require "./platform/web/counter_controller"

Amber.settings.name = #{@name.inspect}
Amber.settings.host = ENV["HOST"]? || "127.0.0.1"
Amber.settings.port = (ENV["PORT"]? || "3000").to_i
Amber::Server.configure do
  pipeline :web do
    plug Amber::Pipe::Error.new
    plug Amber::Pipe::Session.new
    plug Amber::Pipe::CSRF.new
  end
  routes :web do
    get "/", App::WebCounterController, :index
    get "/state", App::WebCounterController, :snapshot
    post "/increment", App::WebCounterController, :increment
    post "/name", App::WebCounterController, :rename
  end
end
Amber::Server.start
CRYSTAL
      end
      outputs["README.md"] = <<-MARKDOWN
# #{@name}

Targets: #{@targets.join(", ")}. Shared application rules live in `src/app`.
Android renders native Views; web uses a separate HTTP presentation layer.
The example is an in-memory counter, not authentication or durable storage.

Install Android-capable Amber/AssetPipeline dependencies, then run:

```sh
shards install
crystal spec
bash mobile/android/android.sh doctor
bash mobile/android/android.sh test emulator-5554
```

#{@targets.includes?("web") ? "Start the web app with `crystal run src/#{@name}_web.cr`; it binds localhost by default and protects form posts with CSRF. Set a server-only secret through Amber configuration before deploying.\n" : ""}
See `mobile/android/README.md` for native builds, device selection, testing and
current support limits. The Android target remains in development. The default
dependency branches must contain the Android work; while it is unreleased, use
explicit local shard overrides. No released-consumer support is claimed yet.
MARKDOWN
      outputs.each do |relative, content|
        destination = File.join(@path, relative)
        Dir.mkdir_p(File.dirname(destination))
        File.write(destination, content)
        File.chmod(destination, 0o755) if relative.ends_with?(".sh") || relative.ends_with?("/gradlew")
      end
    end

    private def shard_yml : String
      String.build do |io|
        io << "name: #{@name}\nversion: 0.1.0\ncrystal: \"~> 1.21.0\"\nlicense: UNLICENSED\n"
        if @targets.includes?("web")
          io << "targets:\n  #{@name}_web:\n    main: src/#{@name}_web.cr\n"
        end
        io << <<-YAML
\ndependencies:
  # Commit pins on the GitHub-hosted Android-capable branches until the
  # Android-capable releases are tagged; a released CLI replaces these with
  # version constraints. Commit pins resolve without any local checkout.
  amber:
    github: crimson-knight/amber
    commit: ab90eae910a4bd3a74f3f52ba8dfe238817994c3
  asset_pipeline:
    github: crimson-knight/asset_pipeline
    commit: 64ac6042de87a4d8911c51f3c1ff82f41765d3b6
YAML
      end
    end
  end
end
