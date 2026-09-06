require "file_utils"
require "digest/sha256"
require "json"

# Snapshot only the attached native target for an explicit local-development
# build. Installed libraries, web secrets/configuration and the real project's
# build tree are not modified. This is not a shards-resolution/release proof.
original, evidence, amber, asset = ARGV
original = File.realpath(original)
amber = File.realpath(amber)
asset = File.realpath(asset)
raise "Missing current Amber native boundary" unless File.file?(File.join(amber, "src/amber/native.cr"))
raise "Missing current AssetPipeline Android entrypoint" unless File.file?(File.join(asset, "src/ui/android/application.cr"))
raise "Proof destination must be new" if File.info?(evidence, follow_symlinks: false)
Dir.mkdir_p(evidence)
evidence = File.realpath(evidence)
project = File.join(evidence, "project")
Dir.mkdir(project)
selected = [".amber.yml", "shard.yml", "shard.lock", "config/native.yml", "config/android_assets.yml",
            "src/app", "src/platform/android", "src/assets", "spec/counter_spec.cr", "mobile/android"]
sources = [] of String
selected.each do |relative|
  absolute = File.join(original, relative)
  raise "Missing attached target input: #{relative}" unless File.exists?(absolute)
  if File.directory?(absolute)
    Dir.glob(File.join(absolute, "**/*"), match: File::MatchOptions.glob_default | File::MatchOptions::DotFiles).each do |entry|
      next if File.directory?(entry)
      sources << Path[entry].relative_to(original).to_s
    end
  else
    sources << relative
  end
end
sources.reject! { |relative| relative.split('/').any? { |part| {"build", ".gradle", "jniLibs", "local.properties"}.includes?(part) } }
hashes = {} of String => String
sources.sort.each do |relative|
  source = File.join(original, relative)
  raise "Proof inputs must be regular files: #{relative}" unless File.info(source, follow_symlinks: false).file?
  destination = File.join(project, relative)
  Dir.mkdir_p(File.dirname(destination))
  FileUtils.cp(source, destination)
  hash = Digest::SHA256.hexdigest(File.read(source))
  raise "Source changed while copying: #{relative}" unless Digest::SHA256.hexdigest(File.read(destination)) == hash
  hashes[relative] = hash
end
Dir.mkdir(File.join(project, "lib"))
File.symlink(amber, File.join(project, "lib/amber"))
File.symlink(asset, File.join(project, "lib/asset_pipeline"))
File.write(File.join(evidence, "projection.json"), {
  "mode" => "local-development-source-projection-no-shard-resolution",
  "original" => original, "project" => project, "amber" => amber, "asset_pipeline" => asset,
  "files" => hashes,
}.to_pretty_json)
puts "Prepared #{hashes.size} byte-verified target inputs with explicit local native dependencies."
puts "Native project: #{project}"
puts "No installed project libraries, web configuration or dependency locks were changed."
