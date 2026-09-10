#!/usr/bin/env bash
# Copied into generated applications from AssetPipeline scripts/ci/report_outcome.sh
# (crimson-knight/asset_pipeline); the shard copy is canonical, this one is
# the application's own so its report job needs no shard install.
# report_outcome.sh: turn a CI lane's outcome into one GitHub issue that tags
# the maintainers, and close that issue when the lane recovers.
#
# A workflow's last job runs this after the gates, on the runs nobody is
# watching (schedule, dispatch, push); pull requests already show their own
# checks. The script reads its inputs from the environment:
#
#   OUTCOME        success | failure | cancelled | skipped (the gate job's result)
#   LANE           short lane name, for example android-native; the issue carries
#                  the label lane:<LANE>, so each lane has at most one open issue
#   WORKFLOW_NAME  the workflow's display name, for the title
#   RUN_URL        the run's HTML URL
#   REPOSITORY     owner/name (default: GITHUB_REPOSITORY)
#   MAINTAINERS    handles to tag, with or without @, separated by spaces or
#                  commas (default: the repository owner)
#   EVENT_NAME, REF_NAME, SHA   context for the issue body
#   GH_TOKEN       a token with issues: write
#   REPORT_DRY_RUN=1   print the gh commands instead of running them
#
# Behavior:
#   failure    no open issue for the lane: create one (labels ci-failure and
#              lane:<LANE>), mention and assign the maintainers; an open issue:
#              comment on it, so a persisting failure is one thread
#   success    an open issue for the lane: comment that it recovered and close
#              it; no open issue: nothing to do
#   cancelled  or skipped: say so and exit 0; a cancelled run is not a verdict
#
# The script never exits nonzero for a failed gate; the gate's own job carries
# the red. It exits nonzero only when it cannot report.
set -euo pipefail

outcome="${OUTCOME:?OUTCOME is required (success|failure|cancelled|skipped)}"
lane="${LANE:?LANE is required}"
workflow_name="${WORKFLOW_NAME:-$lane}"
run_url="${RUN_URL:-}"
repository="${REPOSITORY:-${GITHUB_REPOSITORY:-}}"
[ -n "$repository" ] || { echo "report_outcome: REPOSITORY (or GITHUB_REPOSITORY) is required" >&2; exit 2; }
owner="${repository%%/*}"
event_name="${EVENT_NAME:-}"
ref_name="${REF_NAME:-}"
sha="${SHA:-}"
dry_run="${REPORT_DRY_RUN:-0}"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

failure_label="ci-failure"
lane_label="lane:${lane}"

# Normalize the maintainers into a mention line and an assignee list.
handles=()
raw="${MAINTAINERS:-}"
if [ -z "${raw//[[:space:],]/}" ]; then raw="$owner"; fi
for handle in ${raw//,/ }; do
  handle="${handle#@}"
  [ -n "$handle" ] && handles+=("$handle")
done
mention=""
for handle in "${handles[@]}"; do mention="${mention}@${handle} "; done
mention="${mention% }"
assignees="$(IFS=,; echo "${handles[*]}")"

gh_run() {
  if [ "$dry_run" = "1" ]; then
    printf 'DRY RUN: gh'; printf ' %q' "$@"; printf '\n'
    return 0
  fi
  gh "$@"
}

require_issues() {
  # A fork has issues off by default; without them nothing here can file.
  [ "$dry_run" = "1" ] && return 0
  local enabled
  enabled="$(gh api "repos/${repository}" --jq '.has_issues' 2>/dev/null || echo unknown)"
  if [ "$enabled" != "true" ]; then
    echo "report_outcome: issues are disabled on ${repository} (has_issues=${enabled}); enable them with: gh repo edit ${repository} --enable-issues" >&2
    return 1
  fi
}

ensure_labels() {
  # --force updates an existing label instead of failing, so this is idempotent.
  gh_run label create "$failure_label" -R "$repository" --force \
    --color B60205 --description "A continuous CI lane failed; opened by scripts/ci/report_outcome.sh" >/dev/null
  gh_run label create "$lane_label" -R "$repository" --force \
    --color 0E8A16 --description "The ${lane} lane" >/dev/null
}

open_issue_number() {
  # The issues endpoint, not the search-backed listing: the listing lagged once
  # and reported no open issue while one existed, and the reporter opened a
  # duplicate. Three attempts, then a loud failure rather than a guess.
  if [ "$dry_run" = "1" ]; then
    echo "${REPORT_DRY_RUN_OPEN_ISSUE:-}"
    return 0
  fi
  local attempt result
  for attempt in 1 2 3; do
    if result="$(gh api "repos/${repository}/issues?state=open&labels=${failure_label},${lane_label}&per_page=50" \
        --jq '[.[] | select(.pull_request == null)] | sort_by(.number) | .[0].number // empty')"; then
      echo "$result"
      return 0
    fi
    sleep $((attempt * 5))
  done
  echo "report_outcome: could not list the open issues for ${lane_label} after three attempts" >&2
  return 1
}

context_lines() {
  printf -- '- Run: %s\n' "${run_url:-(no run URL)}"
  printf -- '- Event: %s\n' "${event_name:-(unknown)}"
  printf -- '- Ref: %s at %s\n' "${ref_name:-(unknown)}" "${sha:-(unknown)}"
  printf -- '- Lane: %s\n' "$lane"
  printf -- '- Reported: %s\n' "$now"
}

create_issue() {
  local title body
  title="${workflow_name} failed on ${now%%T*} (${lane})"
  body="$(
    printf '%s the **%s** lane failed.\n\n' "$mention" "$workflow_name"
    context_lines
    printf '\nOpened by `scripts/ci/report_outcome.sh`. Later failures of this lane comment here; the next passing run closes it.\n'
  )"
  if [ "$dry_run" = "1" ]; then
    printf 'DRY RUN: gh issue create -R %q --title %q --label %q --assignee %q --body-file - <<BODY\n%s\nBODY\n' \
      "$repository" "$title" "${failure_label},${lane_label}" "$assignees" "$body"
    return 0
  fi
  # A handle that is not a collaborator makes the assignment fail; the mention
  # in the body still notifies, so retry without assignees rather than not report.
  if ! printf '%s' "$body" | gh issue create -R "$repository" --title "$title" \
      --label "${failure_label},${lane_label}" --assignee "$assignees" --body-file -; then
    echo "report_outcome: assignment to ${assignees} refused; creating the issue without assignees" >&2
    printf '%s' "$body" | gh issue create -R "$repository" --title "$title" \
      --label "${failure_label},${lane_label}" --body-file -
  fi
}

case "$outcome" in
  failure)
    require_issues
    ensure_labels
    existing="$(open_issue_number)"
    if [ -n "$existing" ]; then
      body="$(printf 'Failed again.\n\n'; context_lines)"
      gh_run issue comment "$existing" -R "$repository" --body "$body"
      echo "report_outcome: ${lane} still failing; commented on #${existing}"
    else
      create_issue
      echo "report_outcome: ${lane} failed; opened an issue tagging ${mention}"
    fi
    ;;
  success)
    require_issues
    existing="$(open_issue_number)"
    if [ -n "$existing" ]; then
      body="$(printf 'Recovered.\n\n'; context_lines; printf '\nClosing; a later failure opens a new issue.\n')"
      gh_run issue close "$existing" -R "$repository" --comment "$body"
      echo "report_outcome: ${lane} recovered; closed #${existing}"
    else
      echo "report_outcome: ${lane} passed and no issue was open; nothing to do"
    fi
    ;;
  cancelled|skipped)
    echo "report_outcome: ${lane} was ${outcome}; not a verdict, nothing reported"
    ;;
  *)
    echo "report_outcome: unknown OUTCOME '${outcome}'" >&2
    exit 2
    ;;
esac
