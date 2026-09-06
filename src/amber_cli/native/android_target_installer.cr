require "./android_shell_generator"

module AmberCLI::Native
  # Additive installation into an existing Amber project. Never rewrites web
  # source, dependency declarations, the lockfile, or the existing native YAML.
  class AndroidTargetInstaller
    getter root : String
    getter outputs : Hash(String, String)

    def initialize(project_path : String)
      @root = File.realpath(project_path)
      {".amber.yml", "shard.yml"}.each { |path| require_regular_file(path) }
      config = YAML.parse(File.read(File.join(@root, ".amber.yml")))
      if configured = config["native_manifest"]?.try(&.as_s?)
        unless File.expand_path(configured, @root) == File.join(@root, "config/native.yml")
          raise ArgumentError.new("Android attachment currently requires config/native.yml; preserve and migrate the custom manifest explicitly")
        end
      end
      shard = YAML.parse(File.read(File.join(@root, "shard.yml")))
      name = shard["name"]?.try(&.as_s?) || raise ArgumentError.new("shard.yml requires a project name")
      raise ArgumentError.new("Use a lowercase shard name containing letters, digits, underscores or hyphens") unless name.matches?(/\A[a-z][a-z0-9_-]*\z/)
      dependencies = shard["dependencies"]?.try(&.as_h?)
      unless dependencies && {"amber", "asset_pipeline"}.all? { |dependency| dependencies.has_key?(YAML::Any.new(dependency)) }
        raise ArgumentError.new("Declare Android-capable amber and asset_pipeline dependencies in shard.yml first; no dependencies were changed")
      end

      native_path = File.join(@root, "config/native.yml")
      existing_manifest = !File.info?(native_path, follow_symlinks: false).nil?
      manifest = if existing_manifest
                   require_regular_file("config/native.yml")
                   CapabilityManifest.load(native_path)
                 else
                   CapabilityManifest.default_for(name).tap { |value| value.app.not_nil!.targets = ["web", "android"] }
                 end
      @outputs = AndroidShellGenerator.new(manifest, name).files
      @outputs["config/native.yml"] = manifest.to_yaml_document unless existing_manifest
      preflight!
    end

    def preflight! : Nil
      @outputs.each_key do |relative|
        check_parents(relative)
        if File.info?(File.join(@root, relative), follow_symlinks: false)
          raise ArgumentError.new("Refusing to overwrite #{relative}; no target files were written")
        end
      end
    end

    def install : Nil
      preflight!
      staging = File.tempname(".amber-android-target", dir: @root)
      Dir.mkdir(staging, 0o700)
      staged = [] of String
      installed = [] of {String, String, String}
      directories = [] of String
      begin
        # Stage every byte before publishing. A hard link publishes each complete
        # file with exclusive-create semantics; a concurrent destination wins.
        @outputs.each_with_index do |(relative, content), index|
          source = File.join(staging, index.to_s)
          staged << source
          File.write(source, content)
          File.chmod(source, executable?(relative) ? 0o755 : 0o644)
        end
        preflight!
        @outputs.each_with_index do |(relative, content), index|
          check_parents(relative)
          create_parents(relative, directories)
          source = staged[index]
          destination = File.join(@root, relative)
          publish_file(source, destination)
          installed << {source, destination, content}
        end
      rescue error
        # Roll back only unchanged files still owned by this installation.
        installed.reverse_each do |source, destination, content|
          source_info = File.info?(source, follow_symlinks: false)
          destination_info = File.info?(destination, follow_symlinks: false)
          if source_info && destination_info && source_info.same_file?(destination_info) && File.read(destination) == content
            File.delete(destination)
          end
        end
        directories.reverse_each { |directory| Dir.delete(directory) if Dir.exists?(directory) && !File.symlink?(directory) && Dir.empty?(directory) }
        raise error
      ensure
        staged.each { |source| File.delete(source) if File.info?(source, follow_symlinks: false) }
        Dir.delete(staging)
      end
    end

    protected def publish_file(source : String, destination : String) : Nil
      File.link(source, destination)
    end

    private def executable?(relative : String) : Bool
      relative.ends_with?(".sh") || relative.ends_with?("/gradlew")
    end

    private def check_parents(relative : String) : Nil
      current = @root
      relative.split('/')[0...-1].each do |part|
        current = File.join(current, part)
        if info = File.info?(current, follow_symlinks: false)
          raise ArgumentError.new("Target parent must be a real directory: #{current}") unless info.directory?
        end
      end
    end

    private def create_parents(relative : String, created : Array(String)) : Nil
      current = @root
      relative.split('/')[0...-1].each do |part|
        current = File.join(current, part)
        unless File.info?(current, follow_symlinks: false)
          Dir.mkdir(current)
          created << current
        end
      end
      check_parents(relative)
    end

    private def require_regular_file(relative : String) : Nil
      check_parents(relative)
      info = File.info?(File.join(@root, relative), follow_symlinks: false)
      raise ArgumentError.new("Expected a regular project file: #{relative}") unless info && info.file?
    end
  end
end
