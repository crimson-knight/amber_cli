# Android generator — development checkpoint

## Released-lane consumer proof from GitHub-hosted commits — September 6

`amber new counter_app --type hybrid --targets web,android`, run with the CLI
built from this branch (`shards install --without-development --skip-postinstall`
because the linter's post-install step does not compile on Crystal 1.21), now
emits commit pins instead of branch references: Amber at
`crimson-knight/amber` commit `ab90eae9` (the native facade) and AssetPipeline at
`crimson-knight/asset_pipeline` commit `4c40068c` (the API 36 migration). With
that, `scripts/test_generated_android.sh <serial> bin/amber --released` passes
its structural gate (no `path:` or `branch:` anywhere) and completes from an
empty directory with **no local checkout of either dependency**: shards resolve
from GitHub, the shared specs pass, the generated web app passes its runtime
checks, both ABI dependency bundles build fresh, the Crystal object links, the
Gradle project packages, and the emulator runs **13 Android tests plus the
separate exact-state process restoration** on API 35 (`emulator-5556`). Evidence:
`~/android_target_evidence/2026-09-06-claude/consumer-released-api35/`.

This is the generated-project end-to-end gate in every respect except the tag:
the pins are commits on pushed branches rather than released versions. Tagging
those commits and replacing the pins with version constraints is the remaining
release step. The proof script now hashes sources with `find` rather than
ripgrep so it runs on hosts without `rg`.


## Equal-width native actions — September 6

The [equal-width checkpoint](../../asset_pipeline/docs/android-equal-width-proof-2026-09-06.md)
adds a shared equal-width Save/Open Details row to the generated counter. Its
own native test verifies equal allocated cells and retains the existing actual
actions, navigation, validation, keyboard and restoration gates. Both ABI
artifact inspections now require the equal-width runtime export.

All **526 CLI examples** pass. A fresh actual-CLI project passes shared/web
checks, **93 freshly executed JVM tests**, **13 Android tests** and separate
exact-state process restoration on API 31 ARM64, with all **733 inputs** unchanged.
Its reviewed normal app restores count 6 and the exact Unicode name. The
same generated project also passes **13 Android tests and separate restoration
on API 35**, with all **733 inputs** reverified and count 34 restored. That
rebuild reuses the JVM reports. The canonical sample separately passes the full
50-test/failure target on both API 31 and 35. This is not a released consumer or
complete Tier A support; Android 16 migration is a separate checkpoint.

## Input-method regression — September 6

The [input/minimum-version checkpoint](../../asset_pipeline/docs/android-input-api31-proof-2026-09-06.md)
fixes a generated-test composing-range error exposed on API 31. Moving the
selection is insufficient before appending text through an InputConnection:
an active composition would be replaced. The test now establishes and finishes
a composing span deterministically, preserves the typed prefix, appends exact
Unicode, and notifies the system IME about its external edit (API 33+
invalidation, API 31/32 restart). Production typing is not restarted per key.

The full CLI suite passes **526 examples**. A fresh actual-CLI project passes
shared/web checks, **93 freshly executed JVM tests**, **13 Android tests and
separate exact-state process restoration on both API 31 and API 35 ARM64**.
The API 35 rebuild reuses unchanged JVM reports; all **733 consumer inputs**
remain unchanged. No generated app is manually repaired. The earlier failed
consumer and the sample's fresh-AVD keyboard-readiness failure remain in the
evidence. This is local-development validation, not independent x86_64 CI,
physical-phone proof, a released consumer or complete Android support.

## Existing-project attachment and command surface

The CLI now provides additive Android attachment for an existing Amber project
with declared `amber` and `asset_pipeline` dependencies:

```sh
amber target add android --dry-run
amber target add android
amber doctor android
amber build android
amber run android --device emulator-5556
amber test android --device emulator-5556
```

Use `--project /absolute/project/path` on any of these commands when outside the
project directory. Run/test require an explicit ready ADB serial. Child failures
are propagated; these wrappers do not substitute a no-device success path.

Attachment preserves `.amber.yml`, `shard.yml`, `shard.lock`, installed libraries,
web source and an existing valid v2 `config/native.yml`. Without that manifest it
creates a web/Android default with public metadata and no optional permissions.
It preflights all destination files and real parent directories, rejects existing
files/directories/dangling symlinks, stages bytes before publication, and uses
exclusive hard-link creation rather than overwriting. A failed publication rolls
back its own unchanged files; an independently edited file is preserved. Do not
run concurrent target installers or edit output parents during attachment. This
is not a crash-atomic transaction across the whole directory tree.

The initial native screen is the already-tested counter starter, **not an automatic
translation of existing web components or working application authentication**.
Add real shared use cases and explicitly author native views after attachment.
An existing Apple-v1 or custom-path native manifest requires explicit migration;
the command does not silently change its schema or configuration pointer. Source
collisions require an intentional integration, not a force-overwrite option.

Before Android-capable releases exist, explicitly select development dependencies.
The attached AgentC proof uses a byte-verified, task-owned native source projection
with local Amber/AssetPipeline symlinks; it leaves the original installed library
directories untouched. That is not a public dependency-resolution proof.

The actual command-contract script is `scripts/test_android_target_commands.cr`.
Its stubbed host verifies dispatch and exit behavior only. Real SDK/package/runtime
proof is a separate mandatory gate, not inferred from those process tests.
The [attachment checkpoint](../../asset_pipeline/docs/android-target-attachment-proof-2026-09-05.md)
records 181 passing CLI examples, the actual AgentC attachment, unchanged web
files, 309 web/shared examples (three existing pending checks), all four real
Android command paths and the separate fresh-new-project emulator regression.

The [native semantics checkpoint](../../asset_pipeline/docs/android-semantics-proof-2026-09-05.md)
separates testing IDs from spoken metadata and forwards the canonical Activity
keyboard handling. The generated app has an intentional image label, native
heading/editor semantics and an Increment shortcut. Both ABI artifact gates
require the new checked semantics export; SemanticsPolicy's JVM report is
mandatory. A fresh actual-CLI app passes **76 JVM tests, 13 Android tests and
separate exact-Unicode process restoration**, with all **717 source entries
unchanged** and count 16 restored. The sample separately passes 28 Android tests
and 1,100 partial-render cleanup checks, including actual accessibility-node
actions and injected Tab traversal. See the
[bounded contract](../../asset_pipeline/docs/android-semantics.md) for remaining
TalkBack, compound-control, touch-target and keyboard limits. This is verified
local-development progress, not full Tier A or public-release completion.

The [native view-state checkpoint](../../asset_pipeline/docs/android-view-state-proof-2026-09-05.md)
uses the canonical Activity-owned mount and runtime resources, stable screen/
editor keys, saved-state lifecycle and the new checked metadata export. Its
generated editor retains focus/selection through backgrounding, recreation,
toolbar Up and system Back. The final actual-CLI consumer passes **70 JVM tests,
13 Android tests and separate exact-state restoration**, with **712 unchanged
source entries**, count 14 and exact Unicode text restored in a new process.
The sample separately proves composition-aware refresh, scroll restoration,
private-text snapshot suppression, bounded metadata and 1,000 failure-cleanup
cases. See the [state contract](../../asset_pipeline/docs/android-view-state.md)
for its full-tree replacement policy and remaining focus/keyboard/route limits.
This remains local-development proof, not full target or public-release completion.

The [native-layout checkpoint](../../asset_pipeline/docs/android-layout-proof-2026-09-05.md)
requires all five layout bridge exports in both ABI packages and the canonical
LayoutPolicy JVM report. The generated name field now demonstrates bounded
flexible width and has a real native dimension assertion. The fresh actual-CLI
consumer passes **64 JVM tests, 13 Android tests and a separate exact-state
restoration test**, with **706 unchanged source entries** and count 12/Unicode
text restored in a new process. The sample separately proves 24 layout
configurations, real axis gestures and 1,000 partial-render cleanup checks.
See [the layout contract](../../asset_pipeline/docs/android-layout.md) for
parent-allocation semantics and remaining equal-width, state-preservation and
accessibility work. This remains local-development proof, not full support.

The [checked-JNI checkpoint](../../asset_pipeline/docs/android-jni-errors-proof-2026-09-05.md)
adds `android_exception_pending` to both ABI artifact gates. The canonical
runtime now stops non-cleanup JNI calls after a Java exception, explicitly
unwinds partial Crystal ownership and preserves the original Java Throwable.
The fresh actual-CLI consumer passes **60 JVM tests, 13 Android tests and a
separate exact-state restoration test**, with **703 source entries unchanged**
and count 11/Unicode text restored in a new process. The sample separately proves
400 genuine Java partial-render failures and the prior 600 Crystal failures.
The [bounded JNI contract](../../asset_pipeline/docs/android-jni-errors.md)
records remaining direct-service, allocation/cleanup and full device-matrix gaps.
This is local-development proof, not completion of the full Android target.

The [failure-boundary checkpoint](../../asset_pipeline/docs/android-failure-boundaries-proof-2026-09-05.md)
adds checked callback exports to both ABI artifact inspections and makes positive
runtime tests reject callback-error diagnostics. The matching canonical runtime
contains Crystal callback errors, rejects reuse of failed UI sessions and
explicitly releases partial renders. The fresh actual-CLI consumer passes
**60 JVM tests, 13 Android tests and a separate exact-state restoration test**,
with **698 source entries unchanged** and count 10/Unicode text restored in a new
process. The canonical sample separately passes six deliberate-failure cases
and 600 partial-render cleanup checks. See the
[bounded failure contract](../../asset_pipeline/docs/android-failure-boundaries.md)
for matching C/Kotlin requirements and remaining JNI safety work. This is still
local-development proof, not released-consumer or full Android completion.

The [native-navigation checkpoint](../../asset_pipeline/docs/android-navigation-proof-2026-09-05.md)
adds a retained Crystal stack and a second native details screen. Generated hosts
install canonical Android Back handling; native tests exercise toolbar Up and
system Back, while artifact checks require both ABI navigation exports and
predictive-Back opt-in in both compiled APK manifests. The
final actual-CLI consumer passes **58 JVM tests, 13 Android tests and a separate
exact-state restoration test**, with **696 unchanged source entries**. Count 9
and the Unicode name restore in a new process. Web and Android share model code,
not synchronized storage. The [navigation contract](../../asset_pipeline/docs/android-navigation.md)
records remaining route-restoration, accessibility and richer-navigation limits.
This remains a local-development target, not a public release or full Tier A claim.

The [native-text checkpoint](../../asset_pipeline/docs/android-text-proof-2026-09-05.md)
adds standard Unicode bridge conversion and real editor submission/multiline
behavior. The actual-CLI consumer passes **58 JVM tests, 13 Android interaction/
platform tests and a separate exact-state restoration test**, with **694 source
entries unchanged**. It saves `Android 雪 😀 é`, verifies the exact native text in
a different read-only process, and cold-launches the app for final inspection.
The additional restoration test and EditorActions report are mandatory gates.
This remains local-development proof, not a released or fully supported target.

Bundled images now use `config/android_assets.yml` and the installed
AssetPipeline compiler, automatically invoked by Gradle. The generated counter
includes its own VectorDrawable source and a real `UI::Image("app_mark")`.
Its mandatory native test verifies the loaded drawable. Artifact inspection
resolves catalog/drawable names through both APK resource tables (release files
may have shortened names), checks payload entries, and retains the source ledger.
See the [image contract](../../asset_pipeline/docs/android-images.md) and
[image proof checkpoint](../../asset_pipeline/docs/android-images-proof-2026-09-05.md)
for tested behavior and remaining asset/renderer limits.
The final image-era actual-CLI consumer passes **54 JVM tests, 13 Android tests,
two shared examples and the actual web checks**, with **687 unchanged source
entries** and both ABI/package/symbol gates. Its bundled app mark is visible,
and count 5/name Android restore in a separate process. This is the explicit
local-development lane; released-consumer and full renderer support remain open.

Local-notification generation now accepts `android.capabilities.notifications`
and a bounded `android.notification_channels` catalog. It emits the explicit
permission, lifecycle-compatible canonical runtime, channel label resources and
a monochrome small icon. Default apps remove transitive POST_NOTIFICATIONS;
debug/release package inspection checks the selected permission policy. The
shared notification-wire and permission-state reports are mandatory alongside
existing JVM tests. See the [adapter contract](../../amber-v2-beta-release/docs/android-notifications.md)
for limits and the distinction between local posting and push/background work.
The [notification checkpoint](../../asset_pipeline/docs/android-notifications-proof-2026-09-05.md)
records the passing actual-CLI consumer: **54 JVM tests, 13 Android tests and 682
unchanged source entries**, both ABI/symbol/package gates and process-restarted
count 3/name Android. Default debug/release APKs have neither INTERNET nor
POST_NOTIFICATIONS. The generated Counter uses ordinary Storage; real notification
behavior is proved by the dedicated Amber fixture, not inferred from the scaffold.

The [app-private files checkpoint](../../asset_pipeline/docs/android-files-proof-2026-09-05.md)
adds a descriptor-relative native file backend, included by generated build
scripts, required file JNI exports and canonical file policy/platform tests.
The public Amber Files adapter is exercised by its dedicated native fixture;
the generated counter still uses ordinary key/value state for its own data.

The [protected-secrets checkpoint](../../asset_pipeline/docs/android-secrets-proof-2026-09-05.md)
adds a separate Android Keystore vault to the canonical runtime. Generated hosts
compile the same implementation and require its JVM/platform tests plus native
symbol inspection. Actual Amber secrets round-trips and key-loss policy are
proved by dedicated fixtures, not by the generated counter's ordinary saved state.

The [HTTP/platform-trust checkpoint](../../asset_pipeline/docs/android-http-proof-2026-09-05.md)
adds shared pinned HTTP dependencies, mandatory networking JVM reports, a packaged
INTERNET-permission gate and explicit removal of transitive internet permission
when application metadata has not opted in. This remains a development target.

September 4, 2026. A freshly generated web/Android application now passes a
local end-to-end test. This is development-source proof, not a supported public
release or a claim that all Android APIs are implemented.
The earlier [storage/persistence checkpoint](../../asset_pipeline/docs/android-storage-proof-2026-09-04.md)
supersedes the older runtime counts below; those earlier checkpoints are historical.

The earlier HTTP-era consumer passed 157 generator examples, 31 canonical JVM
tests and three Android tests. All 661 generated/dependency source entries were
unchanged. Debug/release APKs exclude unrequested INTERNET permission; a separate
process restored count 4/name Android. Actual TLS is tested through Amber's direct
native HTTP fixture, not by the generated counter's storage-only application code.

The newer secrets-era consumer passes **36 canonical JVM tests and eight Android
tests**, with **667 unchanged source entries**. The same 157 generator examples
pass, including mandatory secrets-report failures. Both packaged APK variants
still exclude unrequested INTERNET permission, and a fresh process restores
count 1/name Android. This adds canonical Keystore backend coverage; the direct
Amber fixture proves the actual Secrets API, key loss and terminal cancellation.

The latest file-era consumer passes **40 JVM tests and 13 Android tests**, with
**675 unchanged source entries**. Both file JNI exports and native debug symbols
are present in both packaged ABIs. The counter restores count 2/name Android in
a different process, preserving the same test application's earlier saved data.
The dedicated Amber fixture proves binary Files API behavior; the generated
counter itself remains an ordinary Storage consumer.

## Generate an application

```sh
amber new counter_app --type hybrid --targets web,android --no-deps
amber new android_app --type native --targets android --no-deps
```

The ordinary web default is unchanged. The legacy `--type native` command
still emits its Apple/desktop scaffolds, now with this complete Android host.
It has not received the same whole-application regression proof as the explicit
Android/hybrid route. Native/hybrid generation currently instructs the caller
to install dependencies; `--no-deps` does not hide an automatic installation.

The generated project includes:

- Shared Crystal counter/state/schema rules in `src/app`.
- A server-free native entrypoint importing `amber/native` and
  `asset_pipeline/ui/android/application`.
- A separate Amber HTTP controller/entrypoint when web is selected.
- A complete Android Gradle project, verified wrapper/distribution hashes,
  Activity, manifest, resources, icons/splash, instrumentation and build scripts.
- Public AssetPipeline Kotlin/JNI/runtime integration through the installed
  shard, without importing its showcase/sample application.
- Debug APK, unsigned release APK and unsigned release-mode App Bundle builds,
  both configured ABIs, and retained native debug symbols.

The namespace `dev.amber.generated` and library `asset_pipeline_app` are
deliberately independent of the configured application ID. AssetPipeline's
canonical helper package remains `dev.assetpipeline.androidhost`.

## Local development dependencies

Until Android-capable releases exist, dependencies use development branches.
Do not claim those remote branches contain unpublished local changes. For local
work, create explicit `shard.override.yml` entries:

```yaml
dependencies:
  amber:
    path: /absolute/path/to/amber-v2-beta-release
    version: ">= 2.0.0-beta.2"
  asset_pipeline:
    path: /absolute/path/to/asset_pipeline
```

The prerelease constraint is necessary for the current local Amber version;
a path-only override was observed to fail dependency resolution. The E2E
development helper derives that constraint from the selected checkout's version.
No server dependencies, database ORM or audio shard are added to the hybrid
example.

```sh
shards install
crystal spec
crystal run src/counter_app_web.cr
bash mobile/android/android.sh doctor
bash mobile/android/android.sh build
bash mobile/android/android.sh run emulator-5554
bash mobile/android/android.sh test emulator-5554
```

The device serial is mandatory for run/test. Missing/unauthorized/not-yet-booted
devices and crashed/empty instrumentation fail. Tests enable and verify CheckJNI,
restore its previous property afterwards, inspect the actual application logs,
then launch a separate process and verify its initial state and runtime probe.
No device setting, phone authorization or SDK path is inferred from a template.

The build reads AssetPipeline's pinned toolchain. The wrapper must match that
contract. `CRYSTAL_CROSS_DEPS` can select a shared dependency cache; otherwise
the generated project's own build directory is used. A cache hit validates
archive content but is not a new independent dependency build.

## Metadata and ownership

`config/native.yml` v2 drives the initial generated Android properties,
manifest, configuration and resources. See [the schema](android-manifest-v2.md).
Generation refuses to overwrite existing application files. Additive `target add`
is implemented above; safe metadata regeneration remains open. Editing the YAML
alone does not yet regenerate the native outputs.

Android string resources have their own escaping after XML parsing; the
exporter quotes labels, escapes Android syntax and disables format interpretation.
This follows [Android's string-resource rules](https://developer.android.com/guide/topics/resources/string-resource#escaping_quotes).
The Gradle distribution and embedded wrapper hashes match the official
[distribution checksum](https://services.gradle.org/distributions/gradle-9.3.1-bin.zip.sha256)
and [wrapper checksum](https://services.gradle.org/distributions/gradle-9.3.1-wrapper.jar.sha256).

Handwritten Activity/screens/domain code belong to the app. JNI/bootstrap,
listeners, renderer and native dependency build support belong to AssetPipeline.
Permission declarations do not implement adapters or grant runtime consent.
Custom resource references must resolve at Android build time.

## Repeatable fresh-project proof

From the CLI checkout, after building its real executable:

```sh
crystal build src/amber_cli.cr -o /tmp/amber-android-development
CRYSTAL_CROSS_DEPS=/tmp/asset-pipeline-android-goal-deps \
  bash scripts/test_generated_android.sh \
  emulator-5554 /tmp/amber-android-development \
  --development /absolute/path/amber-v2-beta-release /absolute/path/asset_pipeline
```

This creates a new temporary directory, invokes the CLI, resolves shards, runs
shared specs and a live web server test (state, validation, CSRF, HTML escaping),
builds both native libraries/packages, installs and instruments Android, and
inspects packaged ELF architecture, JNI exports, matching build IDs and debug
symbols. Before/after source manifests must match. No generated source file is
patched during this lane. Evidence is retained; the OS may remove temporary files.

The `--released` lane rejects local overrides and development branch dependencies.
It currently fails as intended because Android releases are not yet pinned.
It must eventually run with independently verified released CLI/shard artifacts,
not be renamed to turn development proof into release proof.

## Verified checkpoint

- CLI native/configuration/generator regression suite: 156 examples, zero failures.
- Fresh generated shared Crystal spec: one example, zero failures.
- Generated local web runtime proof: passed.
- ARM64 API 35 emulator: `OK (1 test)`, 10.6 seconds; separate launch passed.
- Debug APK, unsigned release APK and App Bundle: both ARM64/x86_64 libraries.
- Both native debug-symbol files match their packaged libraries' build IDs.
- Generated/Amber/AssetPipeline source manifests unchanged across the run.

Evidence: `/private/var/folders/81/8xr46ykx0p350l1g_v0nk7hr0000gn/T/amber-generated-android.60JcSX`.
The emulator was left displaying CounterApp. Its observed relaunch PID was 8300.
The test uses rebuilt app sources with previously built, revalidated GC/PCRE2
archives and warm tool caches. It is not clean-cache or independent dependency
reproducibility proof. x86_64 was packaged/inspected, not executed.

## Release signing — September 7

The generated `app/build.gradle.kts` signs the release APK and App Bundle
from the environment and never from source control: `AMBER_ANDROID_KEYSTORE`
(a path), `AMBER_ANDROID_KEYSTORE_PASSWORD`, `AMBER_ANDROID_KEY_ALIAS` and
`AMBER_ANDROID_KEY_PASSWORD` must all be set for `android.sh build` to sign;
with none set the release artifacts stay unsigned, and a partial set fails
the Gradle configuration with the missing names. The generated
`inspect_artifacts.sh` accepts either output name, verifies a signed release
APK with `apksigner` and the bundle with `jarsigner`, records the signer
certificate or `unsigned` in `release-signing.txt`, and fails when a key was
configured but the output is unsigned. Store upload keys and the Play Console
side are outside this generator.

## Remaining support gates

The subsequent dependency milestone passed two independent, byte-identical
ARM64/x86_64 API 31 builds and 18 negative cache cases. The native linker now
requires ABI/API/source/toolchain/recipe-keyed v2 bundles; flat legacy caches
must be rebuilt. Artifact evidence retains these per-ABI dependency receipts.
The host and generator explicitly select resize-based keyboard handling.

The fresh generated app was reverified against those bundles at
`/private/var/folders/81/8xr46ykx0p350l1g_v0nk7hr0000gn/T/amber-generated-android.ydiGP5`:
web checks, packages, source stability and `OK (1 test)` in 9.852 seconds.
This remains a local development lane, not released-consumer or cross-host proof.

Unified `amber doctor/build/run/test/target` commands; safe metadata regeneration;
remaining Android service adapters and
permission flows; complete Tier A UI/accessibility/navigation/IME support;
cross-host dependency/CI validation; AgentC's reference screens;
existing-platform regression/CI; independently verified releases and consumer
proof; API-level/x86_64 runtime matrix; physical-phone testing; signing and
current store-policy review. The full Android goal remains active.

## Lifecycle checkpoint — September 4, 2026

The generated Activity now forwards visibility to Amber's retained lifecycle,
separately from releasing its View tree. Application managers start once across
background/foreground, recreation and closing/reopening an Activity in the same
process. The canonical runtime rejects worker-thread UI calls and a simultaneous
second surface. Explicit terminal session close is separate from Activity death;
process-death durability is not implemented yet.

Fresh proof: `/private/var/folders/81/8xr46ykx0p350l1g_v0nk7hr0000gn/T/amber-generated-android.QBg7ZA`.
All eight canonical host-session unit tests and the generated emulator test
passed (17.168 seconds), alongside the shared/web checks, both ABI packages and
debug symbols. All 646 generated/dependency source entries were unchanged.
See the [complete lifecycle proof](../../asset_pipeline/docs/android-lifecycle-proof-2026-09-04.md)
for exact artifacts, semantics and remaining gates.

## Storage checkpoint — September 4, 2026

The counter now saves a validated versioned snapshot through Amber's Storage
interface into Android's app-private SQLite backend. It waits for load before
exposing controls, reports completed saves and refuses to overwrite invalid
stored data. The platform corruption handler preserves damaged database files
for explicit recovery. This is not protected secret storage or Grant support.

Final fresh proof: `/private/var/folders/81/8xr46ykx0p350l1g_v0nk7hr0000gn/T/amber-generated-android.4Sk137`.
Two shared Crystal examples, the live web checks, nineteen JVM contracts, both ABI
packages/symbols and three Android tests passed. The runner verified that process
12339 saved count 3/name Android and that new process 12440 restored them.
All 653 source entries matched before/after, with no generated source edits.

Tests mutate the demo's existing counter/name without clearing its database.
Use a dedicated development app ID, not an app holding important user data.
The native artifact inspector now requires the service/lifecycle exports too.
See the complete storage checkpoint for receipts, limitations and remaining work.

## Continuous lanes (2026-09-10)

Every generated application carries `.github/workflows/android-native.yml`
and `.github/scripts/report_outcome.sh`. The lane runs on every pull request,
push to `main`, nightly (GitHub runs schedules from the default branch only)
and on dispatch: it installs the Crystal the generator names
(`AndroidShellGenerator::CRYSTAL_VERSION`), installs the shards, reads every
toolchain pin from `lib/asset_pipeline/config/android_toolchain.env`, runs
the AssetPipeline doctor, boots its own emulator through
`lib/asset_pipeline/scripts/ci/android_emulator.sh` for the app's floor, its
target (`config/native.yml`) and the newest supported runtime
(`AndroidShellGenerator::NEWEST_SUPPORTED_ANDROID_RUNTIME`, `36`, the ceiling of
AssetPipeline's own gate; the newest released runtime is AssetPipeline's
`android-next` lane to prove first), and runs
`mobile/android/android.sh test` on it. A failing scheduled, dispatched or
push run opens one issue labeled `ci-failure` and `lane:android-native` that
mentions and assigns the maintainers (the repository variable
`CI_MAINTAINERS`, handles separated by spaces or commas; the repository owner
when unset), comments while the failure persists, and closes on recovery.
The reporter is a copy of AssetPipeline's `scripts/ci/report_outcome.sh`;
the shard's copy is canonical and the app's copy is its own, so the report
job needs no shard install. A `report_selftest` dispatch input opens and
closes a `lane:selftest` issue to prove the tagging without a failing gate.

The CLI proves itself the same way. `.github/workflows/generated-android.yml`
builds the CLI, reads the AssetPipeline commit `hybrid_app.cr` pins, checks
that commit out for its pins and launcher, generates a hybrid application
with the built CLI, and runs `scripts/test_generated_android.sh --released`
on the generated application's target and on the newest supported runtime
(`spec/native/generated_android_lane_spec.cr` holds the contract). When
AssetPipeline moves, the pin in `hybrid_app.cr` moves with it and this lane
says whether generated applications still build and pass on the runtimes
that matter.
