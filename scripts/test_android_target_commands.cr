require "digest/sha256"
require "file_utils"
require "json"

# Actual CLI process contract. All mutations are confined to a fresh fixture.
cli, evidence = ARGV
cli = File.realpath(cli)
raise "Evidence directory must not already exist" if File.info?(evidence, follow_symlinks: false)
Dir.mkdir_p(evidence)
evidence = File.realpath(evidence)
project = File.join(evidence, "existing app")
Dir.mkdir(project)
Dir.mkdir(File.join(project, "src"))
File.write(File.join(project, ".amber.yml"), "type: app\n# Existing web configuration\n")
File.write(File.join(project, "shard.yml"), "name: attached_counter\nversion: 0.1.0\ndependencies:\n  amber:\n    path: ../amber\n  asset_pipeline:\n    path: ../asset_pipeline\n")
File.write(File.join(project, "shard.lock"), "keep installed dependency lock\n")
File.write(File.join(project, "src/web.cr"), "# Existing web source\n")
originals = {".amber.yml", "shard.yml", "shard.lock", "src/web.cr"}.to_h do |path|
  {path, Digest::SHA256.hexdigest(File.read(File.join(project, path)))}
end

def invoke(cli, project, arguments, output_path, env = {} of String => String)
  File.open(output_path, "w") do |output|
    Process.run(cli, arguments, chdir: project, env: env, output: output, error: output).exit_code
  end
end

raise "Dry run failed" unless invoke(cli, project, ["target", "add", "android", "--dry-run"], File.join(evidence, "dry-run.txt")) == 0
raise "Dry run wrote native files" if File.exists?(File.join(project, "mobile"))
raise "Attachment failed" unless invoke(cli, project, ["target", "add", "android"], File.join(evidence, "attachment.txt")) == 0
originals.each do |path, hash|
  raise "Existing file changed: #{path}" unless Digest::SHA256.hexdigest(File.read(File.join(project, path))) == hash
end
raise "Native app was not generated" unless File.file?(File.join(project, "src/platform/android/app.cr"))
raise "Duplicate attachment unexpectedly succeeded" if invoke(cli, project, ["target", "add", "android"], File.join(evidence, "duplicate.txt")) == 0

# This fixture-only host proves dispatch/exit handling, not SDK/emulator behavior.
script = File.join(project, "mobile/android/android.sh")
File.write(script, "#!/usr/bin/env bash\nset -euo pipefail\nprintf '%s\\n' \"$@\" > \"$ARG_CAPTURE\"\nexit \"${FAKE_EXIT:-0}\"\n")
capture = File.join(evidence, "arguments.txt")
invalid = [
  ["run", "android"], ["test", "android"], ["build", "web"],
  ["build", "android", "--device=emulator-5556"],
  ["test", "android", "--device=device;echo-bad"],
]
invalid.each_with_index do |arguments, index|
  code = invoke(cli, project, arguments, File.join(evidence, "rejected-#{index}.txt"), {"ARG_CAPTURE" => capture})
  raise "Invalid invocation succeeded" if code == 0
  raise "Invalid invocation ran the target" if File.exists?(capture)
end
{"doctor", "build", "run", "test"}.each do |action|
  arguments = [action, "android", "--project", project]
  expected = [action]
  if {"run", "test"}.includes?(action)
    arguments += ["--device", "[::1]:5555"]
    expected << "[::1]:5555"
  end
  code = invoke(cli, project, arguments, File.join(evidence, "#{action}.txt"), {"ARG_CAPTURE" => capture})
  raise "Action failed: #{action}" unless code == 0
  raise "Arguments changed: #{action}" unless File.read_lines(capture) == expected
end
code = invoke(cli, project, ["test", "android", "--device=emulator-5556"], File.join(evidence, "child-failure.txt"), {"ARG_CAPTURE" => capture, "FAKE_EXIT" => "23"})
raise "Child failure was not propagated" unless code == 23
File.write(File.join(evidence, "preserved-web-sha256.json"), originals.to_pretty_json)
puts "PASS: actual CLI additive attachment, preserved web/dependency files, dry-run, duplicate rejection, exact command arguments and child-failure propagation."
puts "The stubbed command fixture is not Android runtime evidence."
