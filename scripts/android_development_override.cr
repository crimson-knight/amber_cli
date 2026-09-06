require "yaml"
require "file_utils"

# Explicit local development lane only; never part of a released-consumer proof.
project, amber, asset = ARGV
amber = File.realpath(amber)
asset = File.realpath(asset)
raise "Missing Amber native facade" unless File.file?(File.join(amber, "src/amber/native.cr"))
raise "Missing AssetPipeline public Android runtime" unless File.file?(File.join(asset, "src/ui/android/application.cr"))
override = File.join(project, "shard.override.yml")
raise "Refusing to overwrite #{override}" if File.exists?(override)
version = YAML.parse(File.read(File.join(amber, "shard.yml")))["version"].as_s
File.write(override, {"dependencies" => {
  "amber"          => {"path" => amber, "version" => ">= #{version}"},
  "asset_pipeline" => {"path" => asset},
}}.to_yaml)
puts "Installed explicit local development overrides (including Amber prerelease constraint)."
