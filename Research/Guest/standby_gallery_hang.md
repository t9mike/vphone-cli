# Duo StandBy gallery: missing asset directory and verified guest workaround

Observed November 8, 2026 (America/Chicago) on the existing `iphone-duo`:
iPhone19,4, iOS 27.1 (24A94425), cloudOS 26.4 (23E5207q), host and guest
environment bundle `2.15.2-local.263764d1`, boot chain `2.15.2`.

## Repair result

### Automatic preparation in the local implementation

`GuestStandByAssets` prepares this directory from inside the guest, because
the host cannot mount its encrypted Data volume. The worker calls it at
startup; both `display.standby` entry modes (Tent and Book) call the same
preparation before changing the pose. Off and readback do not run it. This
covers a fresh restore, a setup/template boot, an older template clone that
runs the updated agent, and an explicit StandBy request after a failed startup
attempt. No template cache invalidation or new machine is needed.

Preparation applies only on OS major 27 with the owning daemon plist present.
It opens each directory component relative to a descriptor with `O_NOFOLLOW`,
creates missing components with mode 0755, and refuses links/non-directories.
It leaves existing contents, permissions and ownership intact. Repeated calls
do not rewrite the store. An entry-time failure is reported before changing
the pose; a startup failure is logged and does not prevent the agent starting.

Profile list version 5 omits duetexpertd from the iOS 27 trimming list. The
measured iOS 26 list retains it. For existing guests, preparation migrates only
a trimmed iOS 27 record that owns the duetexpertd override: enable it, load its
original plist if needed, start it, then remove that one ownership entry.
The record's other labels, groups, allow exceptions and list-version provenance
remain intact. Failure retains ownership for a retry. A service disabled
outside the profile is not automatically re-enabled. Applying a profile also
prepares the directory before reconciling the old override.

The startup work is part of the existing vphoned guest environment. It installs
no additional daemon or hook and changes no Apple executable or patch preset.
It requires a build containing this code; an older installed bundle does not
gain the behavior merely because this checkout was edited.

### Automatic repair validation (November 9, 2026)

Built the complete `VPhone` scheme and deployed `2.15.2-local.c1e2a33b`
to the existing `iphone-duo`. The daemon logic suite passed 500 checks; the
StandBy controller regression suite, 198-method routing suite, result-schema
check and bundle admission also passed.

On the running guest, moved the empty asset directory aside and disabled and
unloaded duetexpertd. Tent recreated the directory but correctly respected
the independently disabled service. Then simulated the old trimmed profile's
ownership of that override and requested Tent again. It enabled, loaded and
started duetexpertd and removed only that ownership entry. Opening Add a New
Face displayed the populated gallery without another guest restart. The
daemon retained PID 407 with exit status 0 through the check. This tests live
repair on an already-used guest; it does not prove recovery of every stale
connection state encountered during the original investigation.

Restored the original profile labels, groups and allow exception, removed the
empty test backup directory, and returned to the user's saved teal/pink
Digital face. Evidence is in the local `gallery/automatic/` directory.
Startup uses the same tested preparation helper; fresh VM creation was not
run. New machines must use the updated bundle to receive this behavior.

### Original manual repair and live evidence

The gallery loads after creating the missing asset directory, enabling
`com.apple.duetexpertd`, and restarting the existing guest. A new Digital face
with pink numerals on a teal background was selected from the gallery, saved,
and displayed in Tent mode. No binary patch, entitlement change, firmware
update, Apple-account sign-in, or host security change was needed.

This is a narrowly scoped filesystem workaround on this development guest,
not a claim that the kernel's data-vault creation implementation is fixed.
The directory was created normally with `files.mkdir`; its special data-vault
protection has not been established. Do not generalize this workaround to
physical devices or make it a default firmware patch without further study.

## Exact failure and repair

A temporary native probe in an isolated vphoned script process inspected
`ATXEnableMobileAssetDataVault`. Its two failing calls are to
`ASEnsureDataVault(@"com.apple.MobileAsset.DuetExpertCenterAsset", &error)`.
The public wrapper collapses failure to `MobileAssetError` code 32. Capturing
**mobileassetd's logs while starting the real duetexpertd** revealed the
underlying operation:

```text
client com.apple.duetexpertd requested data vault for com.apple.MobileAsset.DuetExpertCenterAsset
The attempt to create data vault failed, path: /private/var/MobileAsset/AssetsV2/com_apple_MobileAsset_DuetExpertCenterAsset , mode: 755, errno: 89
```

The real daemon passes the entitlement check. A separate attempt to invoke
the API from the vphoned probe was rejected for its missing asset entitlement;
that probe error is not the daemon's failure. A direct gallery-client probe
also failed an unrelated Biome entitlement assertion in its isolated process.
Neither required changing any entitlements.

Creating the previously absent directory was sufficient for the original
MobileAsset API to return success. Afterward duetexpertd logged:

```text
Confirmed data vault for com.apple.MobileAsset.DuetExpertCenterAsset
Successfully ensured datavault
Loaded default bundle for "com.apple.MobileAsset.DuetExpertCenterAsset" with version 1746 from path: /System/Library/DuetExpertCenter/Assets/Assets.bundle
```

It survived startup and a deliberate service restart. The existing gallery
continued to fail or wait even after restarting PosterBoard. A full guest
stop/start resolved the remaining connection/startup state; the gallery then
populated. These tests do not isolate which remaining component required the
full restart, so do not omit that step from the verified workaround.

The operations used on this existing guest were:

```sh
vphone-launchpad-cli guest rpc iphone-duo files.mkdir \
  '{"path":"/private/var/MobileAsset/AssetsV2/com_apple_MobileAsset_DuetExpertCenterAsset"}'
vphone-launchpad-cli guest rpc iphone-duo services.enable \
  '{"label":"com.apple.duetexpertd"}'
vphone-launchpad-cli guest rpc iphone-duo services.load \
  '{"paths":["/System/Library/LaunchDaemons/com.apple.duetexpertd.plist"]}'
vphone-launchpad-cli guest rpc iphone-duo services.start \
  '{"label":"com.apple.duetexpertd"}'
```

The saved profile was `trimmed` with base/app_store/signin_followup/accounts
groups and an empty allow list. Preserved those groups and added only the
daemon to its allow exceptions:

```sh
vphone-launchpad-cli guest rpc iphone-duo services.profile.apply \
  '{"profile":"trimmed","groups":["app_store","signin_followup","accounts"],"allow":["com.apple.duetexpertd"],"force":true}'
vphone-launchpad-cli vm stop iphone-duo
vphone-launchpad-cli vm start iphone-duo --wait
```

Read the existing profile before adapting this to another guest: `allow`
replaces that list, and the groups above reflect this machine's saved state.
The apply result had no newly disabled/enabled services and no failures;
it recorded the exception for the daemon already enabled above.

Validation: gallery categories and previews appeared; selecting a colored
Digital face opened Color/Font/Widgets customization, saving created a new
face, and selecting it showed the live clock. Some gallery thumbnails were
initially blank while others rendered; every template and online data source
has not been tested. Book mode retained its previous split presentation.
Existing faces were not removed.

A second full guest stop/start after saving the Digital face verified both
the profile exception and the new face persisted. The guest was left running
in Tent mode with that face visible. Final service readback showed
enabled=true, loaded=true, running=true, last_exit_status=0. The crash-report
inventory contained no new duetexpertd reports after the directory repair;
the latest report was from the preceding failing experiment at 05:42:57Z.
This is a short functional stability check, not a long-duration soak test.
The temporary diagnostic bundle was absent after reboot; no injected hook or
additional startup item remains.

Repair evidence is in the `repair/` subdirectory of the evidence directory
below, including `duet-mobileasset.json`, `duet-after-mkdir.json`,
`profile-allow.json`, `gallery-loaded.png`, and `digital-saved.png`.
`digital-after-restart.png`, `duet-final.json`, and `profile-after-restart.json`
record final persistence and service state.

## Finding

Opening **Add a New Face** in Tent StandBy leaves a permanent spinner.
The captured failure is local XPC communication, not an HTTP denial from
Apple. This does not prove every gallery asset is available offline; it
identifies the failure reached on this guest before a gallery is returned.

`Rushmore` hosts StandBy (PID 290 in this run). `PosterBoard` (PID 216)
requests both Lock Screen and Ambient gallery configurations through
`ATXFaceSuggestionClient`. At 2026-11-09T05:27:31Z its logs show:

```text
[PRPosterRoleAmbient] Calling proactive to FETCH gallery (may be cached)
-[ATXFaceSuggestionClient fetchFaceGalleryConfigurationForPosterRole:completion:]: role=2
error fetching remote object proxy: Error Domain=NSCocoaErrorDomain Code=4099
_pushFaceGalleryConfigurationUpdate: no gallery received? Erroring out...
com.apple.PosterBoard.generalErrorDomain Code=11 "Fetch from gallery service failed"
NSCocoaErrorDomain Code=4099 "Couldn't communicate with a helper application."
```

Here “remote object proxy” means a local XPC service, not an Apple web server.
The installed launch daemon plist assigns
`com.apple.proactive.FaceSuggestions.xpc` to `com.apple.duetexpertd`.
`services.status` initially returned enabled=false, loaded=false,
running=false, override=true. The saved service profile is `trimmed`, list
version 4, with base/app_store/signin_followup/accounts groups and no allow
exceptions. The trim list includes duetexpertd.

The same capture also reports a missing downloadable-asset metadata provider.
There were no mobileassetd entries in the bounded capture. Neither observation
alone establishes a network cause. A network trace was not collected.

## Re-enable experiment and rollback

Through Launchpad RPC, enabled the single service, loaded its existing plist,
started it, and reopened the gallery. No binary or entitlement was changed.
The gallery still spun. The service exited with signal 5 and produced crash
reports roughly ten seconds apart. The first report identifies:

```text
EXC_BREAKPOINT / SIGTRAP
ATXEnableMobileAssetDataVault + 580 (AppPredictionInternal)
Failed to initialize datavault for DuetExpertCenterAsset
_ATXInitializeInOwnerProcess
```

This confirms on this 27.1 Duo the same startup assertion previously documented
on 27.0 in [machine templates](../Host/machine_templates.md). Simply enabling
the service is therefore not a working workaround.

Rolled the experiment back with `services.disable` and `services.unload` for
only `com.apple.duetexpertd`. Readback verified enabled=false, loaded=false,
running=false, and no domains. The service-profile record was not modified.
Closed the gallery and restored StandBy Off/Closed, the state found at the
start of this investigation. Existing saved faces were retained. No reboot,
host security change, global service-profile reset, commit, or push was made.

## Initial workaround assessment (before the repair above)

- Existing-face editing remains the verified way to customize StandBy.
- Re-enabling duetexpertd alone is disproved by the live test above.
- A targeted guest repair must establish why data-vault initialization fails,
  make the daemon survive, and then allow that service in the trimmed profile.
  Do not globally exempt it before fixing the crash.
- A local gallery/configuration fallback is a separate possible development
  route. Its API, persistence, and asset requirements have not been validated.
- Blindly skipping the startup assertion does not establish a usable asset
  store and is not a verified fix. No such patch was applied.
- The installed duetexpertd and MobileAsset feature-flag declaration plists
  exposed no data-vault bypass flag. This is a bounded inspection, not proof
  that no undocumented preference exists.
- No Apple-server spoofing, TLS bypass, account sign-in, or firmware upgrade
  has evidence as a remedy for the captured failure.

Next useful static investigation: follow `ATXEnableMobileAssetDataVault` in
this exact AppPredictionInternal build to its failing local operation and
error value. Then test a narrowly scoped guest fix and verify gallery loading,
adding a face, persistence, and daemon stability. A kernel/firmware patch, if
actually needed, must follow the repository's patch-authoring skill.

## Evidence and sources

Local evidence directory:
`/Users/mmuegel/Documents/ChatGPT/Misc/output/duo-standby/gallery/`

- `posterboard-gallery.json`: successful capture spanning gallery reopen and
  the local helper errors.
- `mobileasset-gallery.json`: bounded asset-service capture, zero entries.
- `profile-before.json`: original service-profile record.
- `duet-crash.ips`: first 27.1 startup assertion report.
- `duet-crashes.json`: crash report inventory after enabling.
- `duet-restored.json`: verified rollback state.
- `duet-feature-flags.json`, `mobileasset-feature-flags.json`: read-only
  declaration inventories.

Some other exploratory log files are empty or cover the face picker rather
than the gallery; they are not evidence of successful gallery loading.

Primary upstream sources:

- [Service trimming](https://lakr233.github.io/vphone-cli/research/Guest/service_trimming.html)
- [Machine templates and the duetexpertd data-vault assertion](https://lakr233.github.io/vphone-cli/research/Host/machine_templates.html)
- [Apple's face customization workflow](https://support.apple.com/guide/iphone/use-standby-iph878d77632/ios)
