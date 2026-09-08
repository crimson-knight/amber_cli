require "yaml"

module AmberCLI::Native
  class CapabilityManifest
    class ApplicationMetadata
      include YAML::Serializable
      include YAML::Serializable::Strict

      property identifier : String = ""
      property display_name : String = ""
      property version : String = "0.1.0"
      property build_number : Int32 = 1
      property targets : Array(String) = ["macos", "ios", "android"] of String

      def initialize(@identifier : String = "", @display_name : String = "")
      end

      def validate! : self
        raise ArgumentError.new("app.identifier cannot be blank") if @identifier.strip.empty?
        raise ArgumentError.new("app.display_name cannot be blank") if @display_name.strip.empty?
        raise ArgumentError.new("app.version cannot be blank") if @version.strip.empty?
        raise ArgumentError.new("app.build_number must be between 1 and 2100000000") unless 1 <= @build_number <= 2_100_000_000
        if @targets.empty? || @targets.uniq.size != @targets.size || @targets.any? { |target| !{"web", "macos", "ios", "android"}.includes?(target) }
          raise ArgumentError.new("app.targets must select unique entries from web, macos, ios and android")
        end
        self
      end
    end

    class AndroidCapabilities
      include YAML::Serializable
      include YAML::Serializable::Strict

      property application_id : String = ""
      # Current proof baseline, not a claim about future store submission rules.
      property minimum_sdk : Int32 = 31
      property target_sdk : Int32 = 35
      property compile_sdk : Int32 = 35
      property abis : Array(String) = ["arm64-v8a", "x86_64"] of String
      property permissions : Array(String) = [] of String
      property features : Array(AndroidFeature) = [] of AndroidFeature
      property deep_links : Array(AndroidDeepLink) = [] of AndroidDeepLink
      property capabilities : AndroidServices = AndroidServices.new
      property notification_channels : Array(AndroidNotificationChannel) = [] of AndroidNotificationChannel
      property appearance : AndroidAppearance = AndroidAppearance.new
      property allow_cleartext_traffic : Bool = false
      property allow_backup : Bool = false
      # A project directory of files the application loads by path (art, fonts,
      # documents): staged into the APK as assets/ap_bundle and extracted once
      # per install by the runtime. The same tree the Apple target copies as a
      # folder reference.
      property bundled_assets : String? = nil

      def initialize(@application_id : String = "")
      end

      def validate! : self
        unless @application_id.matches?(/\A[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+\z/)
          raise ArgumentError.new("android.application_id must have two or more letter-led Java package segments")
        end
        raise ArgumentError.new("android.minimum_sdk must be at least the proven native API baseline 31") if @minimum_sdk < 31
        unless @minimum_sdk <= @target_sdk <= @compile_sdk
          raise ArgumentError.new("Android SDK policy must satisfy minimum_sdk <= target_sdk <= compile_sdk")
        end
        if @abis.empty? || @abis.any? { |abi| !{"arm64-v8a", "x86_64"}.includes?(abi) }
          raise ArgumentError.new("android.abis must select arm64-v8a and/or x86_64")
        end
        ensure_unique(@abis, "android.abis")
        ensure_unique(@permissions, "android.permissions")
        @permissions.each do |permission|
          unless permission.matches?(/\A[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+\z/)
            raise ArgumentError.new("Invalid android permission name: #{permission}")
          end
        end
        @features.each(&.validate!)
        ensure_unique(@features.map(&.name), "android.features")
        @deep_links.each(&.validate!)
        ensure_unique(@deep_links.map { |link| {link.scheme, link.host, link.path_prefix}.join("|") }, "android.deep_links")
        @capabilities.validate!
        raise ArgumentError.new("Android notifications require target_sdk >= 33 for explicit permission timing") if @capabilities.notifications && @target_sdk < 33
        raise ArgumentError.new("android.notification_channels requires capabilities.notifications") if !@notification_channels.empty? && !@capabilities.notifications
        raise ArgumentError.new("android.notification_channels supports at most 32 channels") if @notification_channels.size > 32
        @notification_channels.each(&.validate!)
        ensure_unique(@notification_channels.map(&.id), "android.notification_channels")
        if bundle = @bundled_assets
          segments = bundle.split('/')
          if bundle.empty? || bundle.starts_with?('/') || segments.any? { |segment| segment.empty? || segment == "." || segment == ".." }
            raise ArgumentError.new("android.bundled_assets must be a plain project-relative directory path")
          end
        end
        @appearance.validate!
        self
      end

      # Capability flags are explicit declarations. Resolve the corresponding
      # manifest permissions; this neither grants them nor implements an adapter.
      def declared_permissions : Array(String)
        validate!
        resolved = @permissions.dup
        resolved << "android.permission.INTERNET" if @capabilities.network
        resolved << "android.permission.CAMERA" if @capabilities.camera
        resolved << "android.permission.RECORD_AUDIO" if @capabilities.microphone
        resolved << "android.permission.POST_NOTIFICATIONS" if @capabilities.notifications
        if @capabilities.location != "none"
          resolved << "android.permission.ACCESS_COARSE_LOCATION"
          resolved << "android.permission.ACCESS_FINE_LOCATION" if @capabilities.location == "precise"
        end
        resolved.uniq.sort
      end

      private def ensure_unique(values : Array(String), label : String) : Nil
        raise ArgumentError.new("duplicate #{label}") unless values.uniq.size == values.size
      end
    end

    class AndroidServices
      include YAML::Serializable
      include YAML::Serializable::Strict

      property network : Bool = false
      property files : String = "app_private"
      property camera : Bool = false
      property microphone : Bool = false
      property location : String = "none"
      property notifications : Bool = false
      property background : String = "none"

      def initialize
      end

      def validate! : self
        unless {"none", "app_private", "user_selected"}.includes?(@files)
          raise ArgumentError.new("android.capabilities.files must be none, app_private or user_selected")
        end
        unless {"none", "approximate", "precise"}.includes?(@location)
          raise ArgumentError.new("android.capabilities.location must be none, approximate or precise (foreground access only)")
        end
        unless {"none", "deferred"}.includes?(@background)
          raise ArgumentError.new("android.capabilities.background must be none or deferred; foreground services require a separately supported adapter")
        end
        self
      end
    end

    class AndroidFeature
      include YAML::Serializable
      include YAML::Serializable::Strict

      property name : String = ""
      property required : Bool = false

      def initialize(@name : String = "", @required : Bool = false)
      end

      def validate! : self
        unless @name.matches?(/\A[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+\z/)
          raise ArgumentError.new("Invalid android feature name: #{@name}")
        end
        self
      end
    end

    class AndroidNotificationChannel
      include YAML::Serializable
      include YAML::Serializable::Strict

      property id : String = ""
      property name : String = ""
      property description : String = ""
      # Silent local notifications by default. User settings always win.
      property importance : String = "low"

      def initialize(@id : String = "", @name : String = "")
      end

      def validate! : self
        raise ArgumentError.new("Invalid Android notification channel id") unless @id.matches?(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/)
        raise ArgumentError.new("Invalid Android notification channel name") unless @name.valid_encoding? && !@name.strip.empty? && @name.bytesize <= 128 && !@name.matches?(/[\x00-\x1f\x7f]/)
        raise ArgumentError.new("Invalid Android notification channel description") unless @description.valid_encoding? && @description.bytesize <= 1024 && !@description.matches?(/[\x00-\x1f\x7f]/)
        raise ArgumentError.new("Android notification importance must be low, default or high") unless {"low", "default", "high"}.includes?(@importance)
        self
      end

      def importance_value : Int32
        validate!
        {"low" => 2, "default" => 3, "high" => 4}[@importance]
      end
    end

    class AndroidDeepLink
      include YAML::Serializable
      include YAML::Serializable::Strict

      property scheme : String = ""
      property host : String? = nil
      property path_prefix : String? = nil
      property auto_verify : Bool = false

      def initialize(@scheme : String = "", @host : String? = nil, @path_prefix : String? = nil, @auto_verify : Bool = false)
      end

      def validate! : self
        raise ArgumentError.new("android deep-link scheme must be a lowercase URI scheme") unless @scheme.matches?(/\A[a-z][a-z0-9+.-]*\z/)
        if host = @host
          unless host.size <= 253 && host.split('.').all? { |part| part.matches?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/) }
            raise ArgumentError.new("android deep-link host must be a lowercase hostname without path, port or wildcard")
          end
        end
        if prefix = @path_prefix
          unless @host && prefix.starts_with?("/") && !prefix.matches?(/[\x00-\x20\x7f]/)
            raise ArgumentError.new("android deep-link path_prefix requires a host and must start with /")
          end
        end
        if {"http", "https"}.includes?(@scheme) && @host.nil?
          raise ArgumentError.new("Android web links require an explicit host")
        end
        if @auto_verify && (!{"http", "https"}.includes?(@scheme) || @host.nil?)
          raise ArgumentError.new("android auto_verify requires an http/https scheme and explicit host")
        end
        self
      end
    end

    class AndroidAppearance
      include YAML::Serializable
      include YAML::Serializable::Strict

      property icon : String = "@mipmap/ic_launcher"
      property round_icon : String = "@mipmap/ic_launcher_round"
      property theme : String = "@style/Theme.App"
      property splash_background : String = "@color/splash_background"

      def initialize
      end

      def validate! : self
        {"icon" => @icon, "round_icon" => @round_icon, "theme" => @theme, "splash_background" => @splash_background}.each do |name, value|
          pattern = case name
                    when "theme"             then /\A@style\/[A-Za-z][A-Za-z0-9_.]*\z/
                    when "splash_background" then /\A@color\/[a-z][a-z0-9_]*\z/
                    else                          /\A@(?:mipmap|drawable)\/[a-z][a-z0-9_]*\z/
                    end
          unless value.matches?(pattern)
            raise ArgumentError.new("android.appearance.#{name} must be a local Android resource reference")
          end
        end
        self
      end
    end
  end
end
