# Amber CLI — Multi-Platform Native App Support (WIP Plan)

**Status:** Work in Progress
**Last Updated:** 2026-03-03
**Validation Project:** [Scribe](~/personal_coding_projects/scribe) — native dictation app

---

## What This Document Is

This is a living plan for adding native app (macOS/iOS/Android) scaffolding support to the Amber CLI. Today the CLI only generates web applications. This plan tracks what needs to change so that `amber new my_app --type native` produces a working native app scaffold.

The plan is being developed alongside the Scribe project, which serves as the first real native app built with the Amber V2 + Asset Pipeline stack. Every gap or friction point discovered while building Scribe gets added here.

**For future agents:** If you're told to "update the Amber CLI multi-platform plan" or "add notes to the native app plan", this is the document. Read it, add your findings, and update the status of items.

---

## Goal

A developer should be able to run:

```bash
amber new my_app --type native --targets macos,ios,android
```

And get a project that:
1. Compiles for macOS immediately (`make macos`)
2. Has the correct directory structure for FSDD process managers and Asset Pipeline UI
3. Uses `Amber.settings` (not `Amber::Server.configure`)
4. Has a Makefile with per-platform build targets
5. Includes the ObjC bridge compilation step
6. Has platform-specific entry points (NSApplication for macOS, etc.)

---

## Current CLI Behavior (What It Does Today)

The `amber new <app>` command generates a **web-only** scaffold:

```
src/
├── <app>.cr          → Amber::Server.configure + Amber::Server.start
├── controllers/      → HTTP controllers
├── models/
└── views/            → ECR templates
config/
├── application.cr    → Amber::Server.configure with port, env, secret_key_base
├── environments/
└── initializers/
```

**Problems for native apps:**
- `Amber::Server.configure` creates HTTP server infrastructure
- `Amber::Server.start` blocks on HTTP listener
- No platform-specific code generation
- No Makefile
- No compile-time platform flag awareness (`-Dmacos`, etc.)
- No Asset Pipeline UI integration in scaffold

---

## Required Changes

### Phase 1: New CLI Flag and App Type

**Priority:** HIGH
**Status:** Not started

Add `--type` flag to `amber new`:
```bash
amber new my_app --type native    # Native app (macOS/iOS/Android)
amber new my_app --type web       # Web app (current behavior, default)
amber new my_app                  # Web app (backwards compatible)
```

Optional `--targets` flag:
```bash
amber new my_app --type native --targets macos         # macOS only
amber new my_app --type native --targets macos,ios     # macOS + iOS
amber new my_app --type native --targets all           # All supported
```

Default targets when `--targets` is not specified: `macos` (build what you can test locally).

### Phase 2: Modified `.amber.yml`

**Priority:** HIGH
**Status:** Not started

When `--type native`, generate an extended `.amber.yml`:

```yaml
app: my_app
type: native
database: sqlite
targets:
  macos:
    renderer: appkit
    build_flags: [-Dmacos]
    link_frameworks: [AppKit, Foundation]
  ios:
    renderer: uikit
    build_flags: [-Dios]
    cross_compile: aarch64-apple-ios17.0
  android:
    renderer: android
    build_flags: [-Dandroid]
    cross_compile: aarch64-linux-android31
```

### Phase 3: Native App Entry Point Template

**Priority:** HIGH
**Status:** Pattern validated in Scribe

When `--type native`, generate `src/<app>.cr` as:

```crystal
require "amber"
require "asset_pipeline/ui"
require "../config/application"

require "./ui/**"
require "./controllers/**"

{% if flag?(:macos) %}
  require "./platform/macos/**"
{% elsif flag?(:ios) %}
  # iOS: crystal_init() called from Swift host
{% elsif flag?(:android) %}
  # Android: JNI entry point
{% end %}

{% if flag?(:macos) %}
  <AppModule>::Platform::MacOS::App.run
{% end %}
```

And `config/application.cr` as:

```crystal
require "amber"

Amber.settings.name = "<app>"
# No Amber::Server.configure — native apps don't use HTTP
```

### Phase 4: Native App Directory Structure

**Priority:** HIGH
**Status:** Pattern validated in Scribe

Generate these additional directories for native apps:

```
src/
├── platform/
│   ├── macos/
│   │   ├── app.cr                 — NSApplication lifecycle, window creation
│   │   └── ext/
│   │       └── <app>_platform_bridge.m  — ObjC bridge for app-level FFI
│   ├── ios/
│   │   └── app.cr                 — UIApplication integration
│   └── android/
│       └── app.cr                 — Activity/JNI integration
├── process_managers/              — FSDD business logic
├── ui/
│   └── main_view.cr               — Asset Pipeline UI root view
├── events/                        — Internal event bus
├── controllers/
│   └── application_controller.cr
└── models/
```

### Phase 5: Makefile Generation

**Priority:** HIGH
**Status:** Pattern validated in Scribe

Generate a Makefile with per-platform targets:

```makefile
PROJECT_DIR := $(shell pwd)
CRYSTAL := crystal-alpha

macos: ext
	$(CRYSTAL) build src/<app>.cr -o bin/<app> -Dmacos \
		--link-flags="<bridge .o files> -framework AppKit -framework Foundation -lobjc"

ext:
	@# Compile ObjC bridges
	clang -c lib/asset_pipeline/.../objc_bridge.m -o ...objc_bridge.o -fno-objc-arc
	clang -c src/platform/macos/ext/<app>_platform_bridge.m -o ...o -fno-objc-arc

run: macos
	./bin/<app>
```

### Phase 6: Platform Bridge Template

**Priority:** MEDIUM
**Status:** Pattern validated in Scribe

Generate a minimal ObjC bridge (`<app>_platform_bridge.m`) with:
- `<app>_create_window()` — NSWindow creation with content rect and style mask
- `<app>_shared_application()` — NSApplication singleton
- `<app>_set_activation_policy_regular()` / `_accessory()` — app type
- `<app>_activate_app()` / `<app>_run_app()` — event loop
- `<app>_set_content_view()` — mount rendered view in window

And matching Crystal FFI bindings in `src/platform/macos/app.cr`.

### Phase 7: shard.yml Dependencies

**Priority:** MEDIUM
**Status:** Not started

When `--type native`, add to shard.yml:

```yaml
dependencies:
  amber:
    github: crimson-knight/amber
    branch: master
  asset_pipeline:
    github: amberframework/asset_pipeline
    branch: feature/utility-first-css-asset-pipeline
```

And NOT include web-only dependencies (kilt, slang, etc.).

### Phase 8: Build Validation Command

**Priority:** LOW
**Status:** Not started

Add `amber build` command that reads `.amber.yml` and runs the correct build:

```bash
amber build macos          # Build for macOS
amber build ios            # Cross-compile for iOS
amber build android        # Cross-compile for Android
amber build                # Build default target
```

---

## Discoveries from Scribe (Knowledge Gaps for CLI)

These are issues encountered while building Scribe that the CLI should prevent:

| # | Issue | How CLI Should Handle It |
|---|-------|------------------------|
| 1 | `require "asset_pipeline/ui"` not `require "ui"` | Generate correct require in template |
| 2 | Must pass `-Dmacos` explicitly (not auto-detected) | Include in Makefile build commands |
| 3 | `Amber.settings` not `Amber::Server.configure` for native | Generate correct config template |
| 4 | Asset Pipeline objc_bridge.m must be compiled first | Include in Makefile `ext` target |
| 5 | Link flags need absolute paths (crystal-alpha quirk) | Use `$(PROJECT_DIR)` in Makefile |
| 6 | Asset Pipeline has no window/app management | Generate platform bridge template |
| 7 | Amber schema examples run at require time (noisy) | Fix in Amber core (not CLI) |
| 8 | crystal-audio ext needs `make ext` before linking | Include in Makefile when audio dep present |

---

## Testing Checklist

Before shipping multi-platform CLI support, validate:

- [ ] `amber new test_app --type native` generates compilable macOS app
- [ ] `make macos` builds successfully on first try
- [ ] `make run` launches app with visible window
- [ ] Generated code follows FSDD patterns
- [ ] Asset Pipeline UI renders correctly in window
- [ ] `--targets ios` generates iOS-specific files
- [ ] `--targets android` generates Android-specific files
- [ ] Web app generation (`amber new test_app`) still works (no regression)
- [ ] shard.yml has correct dependencies for native vs web
- [ ] .amber.yml has correct platform configuration

---

## Related Documents

- Scribe gap analysis: `~/personal_coding_projects/scribe/docs/fsdd/knowledge-gaps/multi-platform-gap-analysis.md`
- Scribe knowledge gaps: `~/personal_coding_projects/scribe/docs/fsdd/knowledge-gaps/knowledge-gaps.md`
- Scribe tech stack: `~/personal_coding_projects/scribe/docs/fsdd/tech-stack/tech-stack.md`
- Asset Pipeline CLAUDE.md: `~/open_source_coding_projects/asset_pipeline/CLAUDE.md`
- Amber CLAUDE.md: `~/open_source_coding_projects/amber/CLAUDE.md`
