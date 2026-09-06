#!/usr/bin/env bash
# Fresh consumer proof using the actual CLI executable, not a generator class.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
usage() {
  echo "Usage: $0 <adb-serial> <cli-binary> --development <amber-root> <asset-pipeline-root>" >&2
  echo "       $0 <adb-serial> <released-cli-binary> --released" >&2
  exit 2
}
[[ $# -ge 3 ]] || usage
serial="$1"
cli="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
mode="$3"
[[ -x "$cli" ]] || { echo "Missing executable CLI: $cli" >&2; exit 1; }
case "$mode" in
  --development) [[ $# == 5 ]] || usage ;;
  --released) [[ $# == 3 ]] || usage ;;
  *) usage ;;
esac
proof_root="$(mktemp -d "${TMPDIR:-/tmp}/amber-generated-android.XXXXXX")"
proof_root="$(cd "$proof_root" && pwd)"
project="$proof_root/counter_app"
echo "Fresh generated-consumer proof ($mode): $proof_root"
shasum -a 256 "$cli" > "$proof_root/cli-sha256.txt"
"$cli" new "$project" --type hybrid --targets web,android --no-deps | tee "$proof_root/generation.txt"
[[ -f "$project/shard.yml" && -x "$project/mobile/android/gradlew" ]] || {
  echo "CLI did not generate the requested destination" >&2; exit 1;
}
if [[ "$mode" == --development ]]; then
  crystal run "$script_dir/android_development_override.cr" -- "$project" "$4" "$5" > "$proof_root/development-overrides.txt"
else
  [[ ! -f "$project/shard.override.yml" ]]
  if grep -Eq '^[[:space:]]*(path|branch):' "$project/shard.yml"; then
    echo "Released-consumer proof requires release-pinned dependencies, not local paths/development branches." >&2; exit 1
  fi
fi
cd "$project"
shards install 2>&1 | tee "$proof_root/shards.txt"
if [[ "$mode" == --released ]] && grep -Eq '^[[:space:]]*path:' shard.lock; then
  echo "Local shard resolution is forbidden in the released lane." >&2; exit 1
fi
mkdir -p build
hash_sources() (
  cd "$1"
  set -- src android scripts config mobile shard.yml shard.lock
  for path do
    [[ ! -e "$path" ]] || rg --files --hidden --no-require-git \
      -g '!**/build/**' -g '!**/.gradle/**' -g '!**/jniLibs/**' "$path"
  done | LC_ALL=C sort | while IFS= read -r path; do shasum -a 256 "$path"; done
)
hash_sources "$project" > "$proof_root/generated-source-before.sha256"
hash_sources "$project/lib/amber" > "$proof_root/amber-source-before.sha256"
hash_sources "$project/lib/asset_pipeline" > "$proof_root/asset-source-before.sha256"
crystal --version > "$proof_root/crystal-version.txt"
shards --version > "$proof_root/shards-version.txt"
cp lib/asset_pipeline/config/android_toolchain.env "$proof_root/android-toolchain.env"
crystal spec --error-trace 2>&1 | tee "$proof_root/shared-specs.txt"
crystal build src/counter_app_web.cr -o build/counter_app_web --error-trace
web_port="${ANDROID_WEB_TEST_PORT:-3189}"
web_pid=""
cleanup() {
  if [[ -n "$web_pid" ]]; then kill "$web_pid" 2>/dev/null || true; wait "$web_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
HOST=127.0.0.1 PORT="$web_port" ./build/counter_app_web > "$proof_root/web-server.txt" 2>&1 &
web_pid=$!
for attempt in {1..30}; do
  kill -0 "$web_pid" 2>/dev/null || { echo "Generated web server exited; inspect $proof_root/web-server.txt" >&2; exit 1; }
  if grep -q 'Server started in' "$proof_root/web-server.txt"; then break; fi
  sleep 0.2
done
grep -q 'Server started in' "$proof_root/web-server.txt"
crystal run "$script_dir/test_generated_web.cr" -- "http://127.0.0.1:$web_port" | tee "$proof_root/web-runtime.txt"
cleanup
web_pid=""
ANDROID_TEST_EVIDENCE="$proof_root/android-runtime" bash mobile/android/android.sh test "$serial" 2>&1 | tee "$proof_root/android-build-and-test.txt"
hash_sources "$project" > "$proof_root/generated-source-after.sha256"
hash_sources "$project/lib/amber" > "$proof_root/amber-source-after.sha256"
hash_sources "$project/lib/asset_pipeline" > "$proof_root/asset-source-after.sha256"
cmp "$proof_root/generated-source-before.sha256" "$proof_root/generated-source-after.sha256"
cmp "$proof_root/amber-source-before.sha256" "$proof_root/amber-source-after.sha256"
cmp "$proof_root/asset-source-before.sha256" "$proof_root/asset-source-after.sha256"
echo "PASS: fresh CLI generation, shared/web runtime, Android packaging and emulator/device interactions ($mode)" | tee "$proof_root/result.txt"
echo "Evidence retained at $proof_root. Development mode is not released-consumer proof."
