require "digest/sha256"
require "json"

evidence = File.realpath(ARGV.first)
projection = JSON.parse(File.read(File.join(evidence, "projection.json")))
raise "Not an attached-source projection" unless projection["mode"].as_s == "local-development-source-projection-no-shard-resolution"
files = projection["files"].as_h
raise "Empty source proof" if files.empty?
{"original", "project"}.each do |key|
  root = projection[key].as_s
  files.each do |relative, expected|
    actual = Digest::SHA256.hexdigest(File.read(File.join(root, relative)))
    raise "Attached input changed (#{key}): #{relative}" unless actual == expected.as_s
  end
end
puts "PASS: all #{files.size} attached inputs remain unchanged in both the original project and its native build projection."
