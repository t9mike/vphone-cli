#!/bin/zsh
set -euo pipefail

# Local development through the same bundle installer and VM lifecycle as
# Launchpad. Authorization stays in Launchpad's existing privileged helper.
repo=${0:a:h:h}
derived="$repo/.build/XcodeBundle"
bundle="$derived/Build/Products/Debug/VPhone.bundle"

usage() {
  cat <<'EOF'
usage: dev-vphone.zsh COMMAND [MACHINE]

  build             Build and validate the complete Debug VPhone.bundle.
  deploy MACHINE    Install the existing build, stop the named guest, bind it
                    to that build, and update its guest components. Leave stopped.
  run MACHINE       Start the guest with its currently bound bundle; wait ready.
  up MACHINE        Build, deploy, and run. Restarts the named guest if running.
  stop MACHINE      Shut down the guest through Launchpad.
  status            Show host setup and all machines, including bundle bindings.
  logs MACHINE      Show the latest 100 VM log lines.

Requires Xcode and vphone-launchpad-cli on PATH. Launchpad starts automatically
and may display its administrator authorization dialog. No machine is created.
Deployment preserves the default bundle and uses --update-environment for the
named guest; the boot chain is unchanged and no restore is performed. Failed operations
stop the workflow; a failed environment update may leave the guest stopped
and bound to the new bundle. Fix the reported error and repeat deploy.
EOF
}

fail() { print -u2 -- "error: $*"; exit 1; }
action=${1:-help}
case "$action" in
  help|-h|--help) usage; exit 0 ;;
  build|status) (( $# == 1 )) || { usage >&2; exit 2; } ;;
  deploy|run|up|stop|logs)
    (( $# == 2 )) && [[ -n $2 && $2 != -* ]] || { usage >&2; exit 2; }
    machine=$2
    ;;
  *) usage >&2; exit 2 ;;
esac

if [[ $action != build ]]; then
  cli=$(command -v vphone-launchpad-cli) || fail 'vphone-launchpad-cli is not on PATH.'
fi

build() {
  mkdir -p "$derived"
  print -u2 -- "Building VPhone.bundle; log: $derived/dev-build.log"
  # pipefail preserves build failures while tee keeps progress visible and
  # retains the full output for diagnosing failed or stalled builds.
  (cd "$repo" && xcodebuild -workspace VPhone.xcworkspace -scheme VPhone \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived" build </dev/null 2>&1) | tee "$derived/dev-build.log"
}

deploy() {
  [[ -d $bundle ]] || fail "No build at $bundle. Run '$0 build' first."
  # Resolve exactly one existing machine before installing or stopping anything.
  local machines candidate matches=0 index
  machines=$("$cli" vm list)
  for (( index=0; ; index++ )); do
    if ! candidate=$(print -rn -- "$machines" | /usr/bin/plutil -extract "$index.name" raw -o - - 2>/dev/null); then break; fi
    if [[ $candidate == "$machine" ]]; then (( matches += 1 )); fi
  done
  (( matches == 1 )) || fail "Expected one existing machine named '$machine'; found $matches."

  # Install and verify before stopping the working guest. Never guess the local
  # version: Launchpad derives its identifier from the finished bundle seal.
  local result version preflight policy accepted
  result=$("$cli" bundle install-local "$bundle" --keep-default)
  version=$(print -rn -- "$result" | /usr/bin/plutil -extract version raw -o - -)
  preflight=$(print -rn -- "$result" | /usr/bin/plutil -extract preflight raw -o - -)
  policy=$(print -rn -- "$result" | /usr/bin/plutil -extract policy raw -o - -)
  accepted=$(print -rn -- "$result" | /usr/bin/plutil -extract accepted raw -o - -)
  [[ -n $version && $preflight == passed && $policy == passed && $accepted == false ]] ||
    fail 'The installed build did not pass normal policy and host preflight checks.'
  print -u2 -- "Deploying $version to $machine"
  "$cli" vm stop "$machine"
  "$cli" vm set-bundle "$machine" "$version" --update-environment
}

case "$action" in
  build) build ;;
  deploy) deploy ;;
  run) "$cli" vm start "$machine" --wait ;;
  up) build; deploy; "$cli" vm start "$machine" --wait ;;
  stop) "$cli" vm stop "$machine" ;;
  status) "$cli" status; "$cli" vm list ;;
  logs) "$cli" vm log "$machine" --lines 100 ;;
esac
