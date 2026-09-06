# Native capability manifest v2

Development checkpoint — 2026-09-04. New native scaffolds now emit schema v2.
Existing Apple-only v1 manifests still load without acquiring Android metadata
or permissions. Upgrading an existing app is explicit: choose v2, add `app`
metadata and declare the platforms you intend to generate.

The schema, validation and standalone Android exporter are implemented in the
development checkout. A fresh hybrid project passes a real emulator test.
See [generator commands and exact proof limits](android-generator.md).
Existing old scaffolds are not upgraded merely because configuration validates.

## Example: web plus Android

```yaml
schema_version: 2
app:
  identifier: counter
  display_name: Counter
  version: 0.1.0
  build_number: 1
  targets: [web, android]
android:
  application_id: dev.example.counter
  minimum_sdk: 31
  target_sdk: 35
  compile_sdk: 35
  abis: [arm64-v8a, x86_64]
  permissions: []
  features: []
  deep_links: []
  capabilities:
    network: false
    files: app_private
    camera: false
    microphone: false
    location: none
    notifications: false
    background: none
  appearance:
    icon: '@mipmap/ic_launcher'
    round_icon: '@mipmap/ic_launcher_round'
    theme: '@style/Theme.App'
    splash_background: '@color/splash_background'
  allow_cleartext_traffic: false
  allow_backup: false
```

`app.targets` is explicit. Apple identity is required when targeting macOS/iOS;
Android identity is required for Android. The original `apple` configuration
remains available unchanged. Android application IDs must contain at least two
letter-led package segments. They will be supplied to Gradle rather than a
source manifest's `package` attribute, following the
[Android application-ID contract](https://developer.android.com/guide/topics/manifest/manifest-element).

API 31/SDK 35 are the current local proof baseline, not current-store-policy
guidance or a tested API-level matrix. Lower native APIs and unsupported ABIs
are rejected. SDK ordering must be minimum <= target <= compile. Version/build
metadata follows Android's separate user-visible version and integer build
number model; the build number is limited to the documented Play maximum.
[Android versioning](https://developer.android.com/studio/publish/versioning)

## Capability declarations are not grants or implementations

All optional sensitive capabilities default off. `declared_permissions`
combines explicit permissions with those implied by **explicitly enabled**
capability flags, deduplicates them and returns stable sorted output. It does
not modify the original declarations or inspect application UI to infer access.

| Capability | Manifest permission declaration |
| --- | --- |
| Network | INTERNET |
| Camera | CAMERA |
| Microphone | RECORD_AUDIO |
| Notifications | POST_NOTIFICATIONS |
| Approximate foreground location | ACCESS_COARSE_LOCATION |
| Precise foreground location | ACCESS_COARSE_LOCATION and ACCESS_FINE_LOCATION |
| App-private/user-selected files | No broad storage permission added |
| Deferred background work | No foreground-service or background-location permission added |

Permissions still require platform policy and, where applicable, runtime user
consent. Android 13+ notification permission is a concrete example: declaring
it is not a grant. [Notification permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission)

Camera, media, locations, notifications and deferred-work declarations do not
mean their runtime adapters exist. Background location and foreground-service
modes are rejected until separately supported. Feature declarations carry an
explicit `required` flag; optional features default false so a metadata default
does not unintentionally filter devices.

## Links and resources

Each deep link declares a lowercase scheme, optional exact host and optional
absolute path prefix. Web links require a host; `auto_verify` is only valid for
HTTP/HTTPS with an explicit host. Wildcards, ports and malformed hostnames are
rejected in this initial schema.

The exporter keeps distinct URL combinations in separate intent filters and
includes HTTP and HTTPS for verified App Links. A real website association and
runtime link-handler proof remain required; a manifest field cannot prove
domain ownership or successful handling.
[Android App Links filters](https://developer.android.com/training/app-links/add-applinks)

Appearance fields must reference the appropriate local Android resource type.
Validation does not yet prove that those resources exist; the generated project
build will enforce that. Unknown YAML fields, duplicate identities/permissions,
unsupported target names and contradictory SDK settings fail validation.

## Validation and scaffold safety

```bash
crystal spec spec/native/android_capabilities_spec.cr spec/generators/native_app_spec.cr
```

The generator no longer creates a machine-specific `local.properties`. Its
real Activity test checks state, input, validation, recreation and native cleanup.
Shell regressions reject crashed instrumentation even when ADB returns zero and
propagate failure through the legacy all-platform orchestrator. The standalone
Gradle host/native entrypoint now passes development generated-project E2E;
released-dependency proof and the broader support gates remain open.
