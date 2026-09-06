require "../amber_cli_spec"
require "../../src/amber_cli/native/capability_manifest"

describe "native capability manifest v2" do
  it "validates bounded explicit notification channels and preserves them in YAML" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("app")
    android = manifest.android.not_nil!
    channel = AmberCLI::Native::CapabilityManifest::AndroidNotificationChannel.new("updates", "Updates 雪")
    android.notification_channels << channel
    expect_raises(ArgumentError, /requires capabilities.notifications/) { manifest.validate! }
    android.capabilities.notifications = true
    android.target_sdk = 32
    expect_raises(ArgumentError, /explicit permission timing/) { manifest.validate! }
    android.target_sdk = 35
    loaded = AmberCLI::Native::CapabilityManifest.from_yaml(manifest.to_yaml_document).validate!
    loaded.android.not_nil!.notification_channels.first.name.should eq("Updates 雪")
    channel.importance_value.should eq(2)
    android.notification_channels << channel
    expect_raises(ArgumentError, /duplicate/) { manifest.validate! }
    android.notification_channels.pop
    channel.id = "bad/channel"
    expect_raises(ArgumentError, /channel id/) { manifest.validate! }
    channel.id = "updates"
    channel.name = "雪" * 43
    expect_raises(ArgumentError, /channel name/) { manifest.validate! }
    channel.name = "Updates"
    channel.importance = "critical"
    expect_raises(ArgumentError, /importance/) { manifest.validate! }
  end
  it "defaults new apps to explicit Android metadata without optional permissions" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("my_app")
    manifest.schema_version.should eq(2)
    manifest.app.not_nil!.display_name.should eq("MyApp")
    manifest.app.not_nil!.targets.should eq(["macos", "ios", "android"])
    android = manifest.android.not_nil!
    android.application_id.should eq("com.example.my.app")
    android.declared_permissions.should be_empty
    android.allow_cleartext_traffic.should be_false
    android.allow_backup.should be_false
  end

  it "keeps legacy Apple-only version 1 readable without silently adding Android" do
    manifest = AmberCLI::Native::CapabilityManifest.from_yaml("schema_version: 1\napple:\n  bundle_identifier: com.example.legacy\n").validate!
    manifest.schema_version.should eq(1)
    manifest.android.should be_nil
    manifest.app.should be_nil
    manifest.apple.bundle_identifier.should eq("com.example.legacy")
  end

  it "requires an explicit version upgrade for Android metadata" do
    expect_raises(ArgumentError, /schema_version 2/) do
      AmberCLI::Native::CapabilityManifest.from_yaml("schema_version: 1\napple:\n  bundle_identifier: com.example.legacy\nandroid:\n  application_id: com.example.legacy\n").validate!
    end
  end

  it "allows web/Android applications without an Apple identity" do
    manifest = AmberCLI::Native::CapabilityManifest.from_yaml(<<-YAML
schema_version: 2
app:
  identifier: counter
  display_name: Counter
  targets: [web, android]
android:
  application_id: dev.example.counter
YAML
    ).validate!
    manifest.apple.bundle_identifier.should be_empty
    manifest.android.not_nil!.application_id.should eq("dev.example.counter")
  end

  it "does not accept an Android target without Android configuration" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("app")
    manifest.android = nil
    expect_raises(ArgumentError, /android metadata is missing/) { manifest.validate! }
  end

  it "normalizes numeric app-name segments into valid Android identities" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("123_notes")
    manifest.android.not_nil!.application_id.should eq("com.example.app123.notes")
  end

  it "rejects unknown schema fields instead of ignoring misspelled capabilities" do
    expect_raises(YAML::ParseException) do
      AmberCLI::Native::CapabilityManifest::AndroidCapabilities.from_yaml("application_id: com.example.app\ncapabilites: {}\n")
    end
  end

  it "resolves explicit service capabilities into deduplicated permissions" do
    android = AmberCLI::Native::CapabilityManifest::AndroidCapabilities.new("dev.example.app")
    android.permissions << "android.permission.INTERNET"
    android.capabilities.network = true
    android.capabilities.camera = true
    android.capabilities.microphone = true
    android.capabilities.notifications = true
    android.capabilities.location = "precise"
    android.declared_permissions.should eq([
      "android.permission.ACCESS_COARSE_LOCATION", "android.permission.ACCESS_FINE_LOCATION",
      "android.permission.CAMERA", "android.permission.INTERNET",
      "android.permission.POST_NOTIFICATIONS", "android.permission.RECORD_AUDIO",
    ])
    android.capabilities.location = "approximate"
    android.declared_permissions.should_not contain("android.permission.ACCESS_FINE_LOCATION")
    android.permissions.should eq(["android.permission.INTERNET"])
  end

  it "rejects unsupported ABIs, lower unproved APIs and inconsistent SDK policies" do
    android = AmberCLI::Native::CapabilityManifest::AndroidCapabilities.new("dev.example.app")
    android.minimum_sdk = 26
    expect_raises(ArgumentError, /baseline 31/) { android.validate! }
    android.minimum_sdk = 31
    android.compile_sdk = 34
    expect_raises(ArgumentError, /SDK policy/) { android.validate! }
    android.compile_sdk = 35
    android.abis = ["armeabi-v7a"]
    expect_raises(ArgumentError, /android.abis/) { android.validate! }
    android.abis = ["arm64-v8a", "arm64-v8a"]
    expect_raises(ArgumentError, /duplicate/) { android.validate! }
  end

  it "rejects malformed package names and duplicate permission declarations" do
    android = AmberCLI::Native::CapabilityManifest::AndroidCapabilities.new("dev.123app")
    expect_raises(ArgumentError, /letter-led/) { android.validate! }
    android.application_id = "dev.example.app"
    android.permissions = ["android.permission.CAMERA", "android.permission.CAMERA"]
    expect_raises(ArgumentError, /duplicate/) { android.validate! }
  end

  it "validates explicit deep-link hosts, schemes and verification intent" do
    link = AmberCLI::Native::CapabilityManifest::AndroidDeepLink.new("https", "example.com", "/items", true)
    link.validate!
    link.scheme = "counter"
    expect_raises(ArgumentError, /auto_verify/) { link.validate! }
    link.auto_verify = false
    link.validate!
    link.host = "example.com/path"
    expect_raises(ArgumentError, /hostname/) { link.validate! }
    link.host = "-example.com"
    expect_raises(ArgumentError, /hostname/) { link.validate! }
    link.host = nil
    expect_raises(ArgumentError, /path_prefix/) { link.validate! }
  end

  it "restricts resource references to each appearance field's Android resource type" do
    appearance = AmberCLI::Native::CapabilityManifest::AndroidAppearance.new
    appearance.validate!
    appearance.theme = "@drawable/icon"
    expect_raises(ArgumentError, /appearance.theme/) { appearance.validate! }
    appearance.theme = "@style/Theme.App"
    appearance.icon = "../secret.png"
    expect_raises(ArgumentError, /appearance.icon/) { appearance.validate! }
  end

  it "round-trips platform settings and rejects unsupported background/location modes" do
    manifest = AmberCLI::Native::CapabilityManifest.default_for("app")
    android = manifest.android.not_nil!
    android.features << AmberCLI::Native::CapabilityManifest::AndroidFeature.new("android.hardware.camera.any", false)
    android.deep_links << AmberCLI::Native::CapabilityManifest::AndroidDeepLink.new("counter", "open", "/items")
    android.capabilities.files = "user_selected"
    android.capabilities.background = "deferred"
    loaded = AmberCLI::Native::CapabilityManifest.from_yaml(manifest.to_yaml_document).validate!
    loaded.android.not_nil!.features.first.required.should be_false
    loaded.android.not_nil!.deep_links.first.path_prefix.should eq("/items")
    loaded.android.not_nil!.capabilities.files.should eq("user_selected")
    android.capabilities.location = "background"
    expect_raises(ArgumentError, /foreground access only/) { manifest.validate! }
    android.capabilities.location = "none"
    android.capabilities.background = "foreground_service"
    expect_raises(ArgumentError, /separately supported adapter/) { manifest.validate! }
  end
end
