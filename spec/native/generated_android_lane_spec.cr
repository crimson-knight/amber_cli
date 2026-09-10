require "../amber_cli_spec"
require "yaml"

# Configuration contracts for the CLI's own continuous proof of a generated
# application, not an assertion that remote CI has executed.
describe "Generated Android application lane" do
  root = File.expand_path("../..", __DIR__)
  text = File.read(File.join(root, ".github/workflows/generated-android.yml"))
  workflow = YAML.parse(text)
  generated = workflow["jobs"]["generated"]
  steps = generated["steps"].as_a
  report = workflow["jobs"]["report"]

  it "runs the generated application's target and the newest supported runtime on an explicit Linux runner" do
    generated["runs-on"].as_s.should eq("ubuntu-24.04")
    generated["strategy"]["matrix"]["api"].as_a.map(&.as_s).should eq(["35", "36"])
    generated["strategy"]["fail-fast"].as_bool.should be_false
    generated["timeout-minutes"].as_i.should be >= 60
    workflow["on"].as_h.keys.map(&.as_s).sort.should eq(["pull_request", "push", "schedule", "workflow_dispatch"])
    workflow["on"]["push"]["branches"].as_a.map(&.as_s).should eq(["main", "android-target"])
    workflow["on"]["schedule"].as_a.first["cron"].as_s.should match(/\A\d{1,2} \d{1,2} \* \* \*\z/)
  end

  it "never ignores or conditionally skips a mandatory gate and pins every external action" do
    generated["continue-on-error"]?.should be_nil
    generated["if"]?.should be_nil
    workflow["jobs"].as_h.each_value do |job|
      job["steps"].as_a.each do |step|
        step["continue-on-error"]?.should be_nil
        if action = step["uses"]?.try(&.as_s)
          action.should match(/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+@[0-9a-f]{40}\z/)
        end
        if step["name"].as_s == "Checkout"
          step["with"]["persist-credentials"].as_bool.should be_false
        end
      end
    end
    steps.each do |step|
      step["if"]?.should be_nil unless step["name"].as_s == "Retain evidence, including failures"
    end
    workflow["permissions"].as_h.size.should eq(1)
    workflow["permissions"]["contents"].as_s.should eq("read")
  end

  it "builds the CLI, checks out the AssetPipeline commit the generator pins, and proves a released-mode generated app on the shard's launcher" do
    runs = steps.compact_map { |step| step["run"]?.try(&.as_s) }.join("\n")
    runs.should contain("shards install --without-development")
    runs.should contain("crystal build src/amber_cli.cr --no-debug -o build/amber")
    runs.should contain("mkdir -p build/generated-ci")
    runs.should contain("src/amber_cli/generators/hybrid_app.cr")
    runs.should contain("git clone --quiet https://github.com/crimson-knight/asset_pipeline.git build/asset_pipeline")
    runs.should contain("source build/asset_pipeline/config/android_toolchain.env")
    runs.should contain("bash build/asset_pipeline/scripts/doctor_android.sh")
    runs.should contain(%(bash build/asset_pipeline/scripts/ci/android_emulator.sh run "$ANDROID_RUNTIME_API" 5554 -- bash scripts/test_generated_android.sh emulator-5554 ./build/amber --released))
    runs.should contain("git diff --exit-code")
    runs.should_not contain("|| true")
    # The pin the workflow reads is the one the generator writes into every app.
    pinned = File.read(File.join(root, "src/amber_cli/generators/hybrid_app.cr"))[/asset_pipeline:\n\s+github: crimson-knight\/asset_pipeline\n\s+commit: ([0-9a-f]{40})/, 1]
    pinned.should_not be_nil
  end

  it "reports the outcome to an issue on the runs nobody is watching, with the reporter the generator ships" do
    report["needs"].as_s.should eq("generated")
    report["if"].as_s.should eq("always() && github.event_name != 'pull_request'")
    report["permissions"].as_h.size.should eq(2)
    report["permissions"]["issues"].as_s.should eq("write")
    reporter = report["steps"].as_a.find { |step| step["run"]?.try(&.as_s) == "bash src/amber_cli/templates/android/report_outcome.sh" }.not_nil!
    reporter["env"]["OUTCOME"].as_s.should eq("${{ needs.generated.result }}")
    reporter["env"]["LANE"].as_s.should eq("generated-android")
    reporter["env"]["MAINTAINERS"].as_s.should eq("${{ vars.CI_MAINTAINERS }}")
    selftest = report["steps"].as_a.find { |step| step["name"].as_s.starts_with?("Reporter self-test") }.not_nil!
    selftest["if"].as_s.should eq("github.event_name == 'workflow_dispatch' && inputs.report_selftest")
    File.read(File.join(root, "src/amber_cli/templates/android/report_outcome.sh")).should contain(%(lane_label="lane:${lane}"))
  end

  it "retains evidence on failure and fails when no requested artifacts exist" do
    upload = steps.last
    upload["if"].as_s.should eq("always()")
    upload["with"]["if-no-files-found"].as_s.should eq("error")
    upload["with"]["path"].as_s.should contain("build/generated-ci/")
  end
end
