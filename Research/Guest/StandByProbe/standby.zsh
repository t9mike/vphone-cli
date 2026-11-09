#!/bin/zsh
# Research helper for an existing, running iPhone Duo guest. No VM creation.
set -euo pipefail
here=${0:a:h}
mode=${1:-}
machine=${2:-iphone-duo}
case "$mode" in
  tent) tabletop=7; hinge=partially-open ;;
  book) tabletop=3; hinge=open-flat ;;
  off) tabletop=0; hinge=closed ;;
  *) print -u2 'Usage: standby.zsh tent|book|off [existing-running-machine]'; exit 2 ;;
esac
cli=${VPHONE_LAUNCHPAD_CLI:-${commands[vphone-launchpad-cli]:-$HOME/.local/bin/vphone-launchpad-cli}}
[[ -x "$cli" ]] || { print -u2 "Missing CLI: $cli"; exit 1; }

field() { /usr/bin/plutil -extract "$1" raw -o - -- -; }
rpc() {
  local params=${2-'{}'}
  reply=$("$cli" guest rpc "$machine" "$1" "$params")
  if [[ $(field ok <<< "$reply") != true ]]; then
    print -u2 -- "$reply"; return 1
  fi
}
rpc device.snapshot
[[ $(field result.model <<< "$reply") == iPhone19,4 ]] || {
  print -u2 'This probe is validated only for an iPhone Duo (iPhone19,4).'; exit 1
}
print -- "Guest: $machine; iOS $(field result.ios_version <<< "$reply")"

build_dir=$(mktemp -d /tmp/vphone-standby.XXXXXX)
trap 'rm -rf -- "$build_dir"' EXIT
"$here/build.zsh" "$build_dir" >/dev/null
rpc files.mkdir '{"path":"/private/var/tmp/StandByProbe.bundle"}'
for item in StandByProbe Info.plist; do
  reply=$("$cli" guest push "$machine" "$build_dir/StandByProbe.bundle/$item" "/private/var/tmp/StandByProbe.bundle/$item" --mode 755)
  [[ $(field ok <<< "$reply") == true ]] || { print -u2 -- "$reply"; exit 1; }
done
pose() {
  local payload value
  payload=$(printf '{"source":"ObjC.use(\"NSBundle\").bundleWithPath_(\"/private/var/tmp/StandByProbe.bundle\").load(); ObjC.use(\"VPStandByProbe\").poseJSONOrientation_hinge_tabletop_(%d,%d,%d)"}' "$1" "$2" "$3")
  rpc script.eval "$payload"
  [[ $(field result.ok <<< "$reply") == true ]] || { print -u2 -- "$reply"; return 1; }
  value=$(field result.result <<< "$reply")
  [[ $(field applied <<< "$value") == true ]] || { print -u2 "Pose was not accepted: $value"; return 1; }
  print -- "$value"
}

# Reset the override and deliver a real hinge transition before another pose.
# This also restores normal CoreMotion-driven fold controls when leaving.
pose 0 0 0
rpc display.posture '{"hinge":"closed","orientation":"portrait"}'
sleep 2
if [[ "$mode" == off ]]; then
  rpc display.pose
  [[ $(field result.tabletop <<< "$reply") == 0 && $(field result.hinge <<< "$reply") == 1 ]] || {
    print -u2 "Normal closed pose was not restored: $reply"; exit 1
  }
  print 'Normal fold controls restored; guest left closed.'
  exit 0
fi
rpc display.posture "{\"hinge\":\"$hinge\",\"orientation\":\"portrait\"}"
sleep 2
rpc device.snapshot
if [[ $(field result.lock.locked <<< "$reply") == false ]]; then
  rpc input.button '{"name":"power"}'
  sleep 1
fi
rpc device.snapshot
if [[ $(field result.lock.screen_off <<< "$reply") == true ]]; then
  rpc input.button '{"name":"power"}'
  sleep 1
fi
pose 1 2 "$tabletop"
sleep 2
rpc display.pose
[[ $(field result.tabletop <<< "$reply") == "$tabletop" && $(field result.hinge <<< "$reply") == 2 ]] || {
  print -u2 "Pose did not persist: $reply"; exit 1
}
print -- "$mode pose verified. Inspect the guest window for StandBy."
print -- 'To edit colors: long-press the face, choose Customize, then Color.'
print -- "To restore normal fold controls: $here/standby.zsh off $machine"
