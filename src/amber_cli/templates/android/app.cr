require "asset_pipeline/ui/android/application"
require "../../app/counter"
require "amber/native/android_storage"
require "./configuration"

module App::Android
  # Retain Crystal navigation across Activity recreation. Native views are
  # rebuilt from shared state; no Android View/Context is retained here.
  class CounterScreen < UI::View
    def initialize
      self.state_key = "counter-screen"
    end

    def accept(visitor : UI::PlatformVisitor)
      App::Android.counter_screen.accept(visitor)
    end
  end

  class DetailsScreen < UI::View
    def initialize
      self.state_key = "details-screen"
    end

    def accept(visitor : UI::PlatformVisitor)
      App::Android.details_screen.accept(visitor)
    end
  end

  # This manager belongs to the retained app session, not a transient View.
  class SessionProcess < Amber::Native::ProcessManager
    getter starts = 0
    getter backgrounds = 0

    def start : Nil
      @starts += 1
      App::Android.load
    end

    def background : Nil
      @backgrounds += 1
    end
  end

  @@process = SessionProcess.new
  @@lifecycle = Amber::Native::Lifecycle.new([@@process])
  @@state = App::Counter.new
  @@draft = ""
  @@notice = "Shared Crystal state, native Android views."
  @@storage : Amber::Native::Storage = Amber::Native::Android::Storage.new
  @@ready = false
  @@load_failed = false
  @@save_version = 0
  @@navigation : UI::NavigationStack = UI::NavigationStack.new(CounterScreen.new, "Counter").tap { |view| view.state_key = "counter-navigation" }

  def self.load : Nil
    @@storage.read("counter.snapshot.v1") do |result|
      @@ready = true
      case result
      when Amber::Native::ServiceError
        @@load_failed = true
        @@notice = "Storage could not be loaded: #{result.code}."
      when String
        @@load_failed = !@@state.restore(result)
        @@notice = @@load_failed ? "Stored state is invalid; it was not overwritten." : "Restored from local storage."
        @@draft = @@state.name unless @@load_failed
      else
        @@notice = "Storage ready."
      end
      UI::Android::Application.invalidate
    end
  rescue error : Amber::Native::ServiceError
    @@ready = true
    @@load_failed = true
    @@notice = "Storage could not be loaded: #{error.code}."
  end

  def self.persist : Nil
    @@save_version += 1
    version = @@save_version
    @@notice = "Saving locally..."
    @@storage.write("counter.snapshot.v1", @@state.snapshot) do |result|
      if version == @@save_version
        @@notice = result.is_a?(Amber::Native::ServiceError) ? "Save failed: #{result.code}." : "Saved locally."
        UI::Android::Application.invalidate
      end
    end
  rescue error : Amber::Native::ServiceError
    @@notice = "Save failed: #{error.code}."
  end

  def self.lifecycle(event : UI::Android::Application::LifecycleEvent) : Nil
    case event
    in .foreground? then @@lifecycle.activate
    in .background? then @@lifecycle.background
    in .stop?       then @@lifecycle.stop
    end
  end

  def self.screen : UI::View
    @@navigation
  end

  def self.details_screen : UI::View
    stack = UI::VStack.new(16.0, UI::Alignment::Leading)
    stack.padding = UI::EdgeInsets.new(top: 24.0, trailing: 24.0, bottom: 24.0, leading: 24.0)
    stack << UI::Label.new("Native details")
    stack << UI::Label.new("Count: #{@@state.count}")
    stack << UI::Label.new("Name: #{@@state.name}")
    stack << UI::Label.new("The counter and web application use the same Crystal model. This device's data stays local.")
    stack
  end

  def self.counter_screen : UI::View
    stack = UI::VStack.new(16.0, UI::Alignment::Leading)
    stack.padding = UI::EdgeInsets.new(top: 24.0, trailing: 24.0, bottom: 24.0, leading: 24.0)
    mark = UI::Image.new("app_mark")
    mark.minimum_width = mark.maximum_width = 48.0
    mark.minimum_height = mark.maximum_height = 48.0
    mark.test_id = "counter-app-mark"
    mark.accessibility_label = "#{DISPLAY_NAME} app mark"
    stack << mark
    heading = UI::Label.new(DISPLAY_NAME)
    heading.font = UI::Font.new(size: 28.0, weight: :bold)
    heading.test_id = "1.1-welcome-label"
    heading.accessibility_role = :header
    stack << heading
    stack << UI::Label.new("Session: #{@@lifecycle.state} / starts #{@@process.starts} / backgrounds #{@@process.backgrounds}")
    unless @@ready && !@@load_failed
      stack << UI::Label.new(@@ready ? @@notice : "Loading local state...")
      return stack
    end
    stack << UI::Label.new("Count: #{@@state.count}")
    increment = UI::Button.new("Increment") { @@state.increment; persist; nil }
    increment.test_id = "counter-increment"
    increment.accessibility_hint = "Increase the saved count by one"
    increment.accessibility_value = "Count: #{@@state.count}"
    increment.keyboard_shortcut = UI::KeyboardShortcut.new("i", [:control])
    stack << increment
    stack << UI::Label.new("Name: #{@@state.name}")
    input = UI::TextField.new("Name", text: @@draft) { |value| @@draft = value; nil }
    input.test_id = "counter-name"
    input.accessibility_identifier = "counter-name-field"
    input.accessibility_label = "Name"
    input.state_key = "counter-name"
    input.maximum_width = 280.5
    input.grow!
    stack << input
    save = UI::Button.new("Save name") do
      if @@state.rename(@@draft)
        persist
      else
        @@save_version += 1 # A previous save must not replace this newer validation message.
        @@notice = "Use at least two characters."
      end
      nil
    end
    save.test_id = "counter-save"
    actions = UI::HStack.new(12.0, UI::Alignment::Center)
    actions.test_id = "counter-actions"
    actions.fill_equally = true
    actions.grow!
    actions << save
    actions << UI::NavigationLink.new("Open details", DetailsScreen.new)
    stack << actions
    stack << UI::Label.new(@@notice)
    stack
  end
end

UI::Android::Application.on_lifecycle { |event| App::Android.lifecycle(event) }
UI::Android::Application.configure { |_route| App::Android.screen }
