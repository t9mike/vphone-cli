# Duo StandBy: live guest proof and repeatable control

Verified 2026-11-08 on the existing `iphone-duo` machine: iPhone19,4,
iOS 27.1 (24A94425), standard firmware preset, VPhone.bundle 2.15.2,
Launchpad 2.15.0. Research source baseline:
`cb23353eb61b74186bc0b345fe34e6868b733746`.

## Result

The installed guest contains and runs the redesigned Duo StandBy experience.
It is possible to enter tent and book layouts, open the Modular face editor,
select a color and Light appearance, save it, and see that choice after leaving
and re-entering StandBy. A green Modular face was verified visually.

The missing control is the tabletop pose. The CoreMotion relay path in
[`GuestAPI+Device.swift`](../../../VPhoneDaemon/Daemon/GuestAPI+Device.swift)
parses `display.posture.tabletop` but does not apply it: it publishes the hinge
and orientation and returns `tabletop: null`. The non-relay path already calls
SpringBoard's test-automation pose override. This distinction is also documented
in [`vphoned_http_api.md`](../../vphoned_http_api.md).

The installed guest exposes that same authorized test service. This probe uses
it directly through a temporary native bundle loaded into an isolated vphoned
script session. It does not inject code into SpringBoard or replace vphoned,
Launchpad, the virtualization engine, firmware, or host security settings.
The guest's existing vphoned entitlement permits the test-automation service.

## Run

Requires an already running Duo guest, Launchpad CLI, and Xcode with the iPhoneOS
SDK selected by `xcrun`. Uses only macOS system tools; no package installation.

From this directory:

```zsh
./standby.zsh tent                 # default existing machine: iphone-duo
./standby.zsh book
./standby.zsh off                  # restore normal controls; close the guest
# Optional second argument selects another existing, running Duo machine.
```

The script builds and ad-hoc signs a small arm64e bundle in a temporary host
directory, uploads it to `/private/var/tmp/StandByProbe.bundle`, resets the old
pose, transitions the virtual hinge, locks/wakes the display as needed, applies
the desired pose, and checks readback. It never creates or starts a machine.
Uploaded files remain for subsequent probe use; no startup item is installed.

On first use, finish or dismiss the guest's StandBy welcome screen, then run the
desired command again. For colors, long-press the visible face, select
**Customize → Color**, select a palette color and appearance, and finish with
the checkmark. Select the face card to return to live StandBy.

The ordinary vphone VM window was reliable for editing. Coordinate taps sent
through RPC were not consistently aligned with controls in the editor.

## Pose evidence and reset

The probe checks the Objective-C method encodings before calling either method:

```text
SBSTestAutomationService setDevicePoseOverride: v40@0:8{?=qiii}16
SBSTestAutomationService getDevicePose          {?=qiii}16@0:8
VPPose: int64 orientation; int32 deviceOrientation, hingeState, tabletopPose
```

| Mode | Device orientation | Hinge state | Tabletop pose | Observed UI |
|---|---:|---:|---:|---|
| Tent | 1 | 2 | 7 (PartiallyOpenFaceDown) | Full-width Modular face, saved green/Light styling |
| Book | 1 | 2 | 3 (PartiallyOpenPortrait) | Split face layout, Modular left and Photos placeholder right |
| Reset | 0 | 0 | 0 | Followed by normal closed/portrait relay request: hinge 1, tabletop 0, portrait Lock Screen |

The enum names are corroborated by the existing
[`duo-sim-baseline/sensors.md`](../Evidence/duo-sim-baseline/sensors.md).
The service updates asynchronously; the helper polls for up to two seconds,
then checks the pose again after another two seconds. Pose acceptance alone
does not prove that the rendered StandBy UI is visible.

The zero pose plus a real hinge transition restored ordinary CoreMotion control
in the live test. This is an empirically verified reset sequence, not a claim
that the private API documents a formal clear operation. No guest reboot was
needed or tested. Use `off` before returning to normal fold experimentation.

## Validation and remaining limits

- Native build passes `-Wall -Wextra -Werror`; scripts pass `zsh -n`.
- The packaged script passed tent, book, and off on the existing guest.
- Screenshots verify both layouts; the green face persisted across re-entry.
- Color palette and Light/Dark controls work. The Widgets editing tab is
  present, but a SundialPro widget was not installed or validated in this test.
- **Add a New Face** opened but remained on a loading spinner for approximately
  one minute during the original pose test. The later
  [gallery repair](../standby_gallery_hang.md) restored gallery loading and
  verified adding a colored Digital face on this guest. Every possible face
  remains untested.
- Book and tent showed different saved appearance selections. Do not assume
  customizing one presentation updates the other.
- Both captures were 2034×1398. The book layout appeared, but inner-panel pixel
  geometry and fidelity to physical Duo hardware are not established.
- This uses a private, ABI-checked API and is validated on the stated guest
  build. It is a development helper, not an Apple-supported simulator command.

Screenshots for this investigation are in
`/Users/mmuegel/Documents/ChatGPT/Misc/output/duo-standby/`:
`tent-verified.png`, `book-verified.png`, `color-editor.png`.

## Engine fork assessment

A virtualization-engine fork is unnecessary to demonstrate the desired colors
and layouts: the installed guest OS already renders them. For permanent product
support, a small vphoned change is the appropriate scope: expose an explicit
tabletop/test-pose override even when CoreMotion relay is active, define reset
semantics, and report requested versus observed pose. Keep ordinary hinge
requests on the existing CoreMotion route. Add readback and tent/book/normal
transition coverage before shipping that change.

The stalled face gallery may have a separate cause; this experiment does not
attribute it to the engine or claim a fix. No remote fork or PR was created.
The later [gallery investigation](../standby_gallery_hang.md) traced the
spinner to an unavailable local FaceSuggestions service and reproduced the
duetexpertd data-vault startup crash when that service was restored.
The subsequent repair created its missing asset directory, added the daemon
to this guest's service-profile allow list, and restarted the guest. It did
not require a binary patch or host security change.
The updated agent now shares that preparation between startup and Tent/Book
entry, and service-profile list 5 retains the daemon on iOS 27. Off and pose
readback do not prepare the gallery. See the repair note for the profile-owned
migration rule and validation limits.
The original local research branch was `codex/duo-standby-research`. Work now
lives in the user's [t9mike/vphone-cli fork](https://github.com/t9mike/vphone-cli),
checked out at `/Users/mmuegel/links/Git/Free/vphone-cli` on
`codex/duo-standby-ui`.

## Existing forks and UI integration (2026-11-08)

No ready-made Tent/Book StandBy UI implementation was found in the public work
examined. Research used GitHub's fork, branch, comparison, issue, PR, and code
search APIs plus web search. The fork listing yielded 1,974 entries. We selected
the 153 forks pushed on or after October 20 (before Duo bring-up), enumerated
all 421 branches, and compared their 269 unique heads with the pinned upstream
commit. There were 267 successful comparisons: 125 behind, 1 identical, 4 ahead,
and 137 diverged. Added lines and commit messages were searched for StandBy,
tabletop, tent, and Rushmore; changes in the fold panel and control were also
reviewed. The branch inventory and compact comparison results are retained
beside this document.

The closest candidates were:

- [xuhom/vphone-cli](https://github.com/xuhom/vphone-cli/tree/33c02fbf46bb6ffad2578b514c49137661eec98c):
  substantial Duo window, fold completion, and display-transition work. Its
  `use_display_tool` path improves fold completion, but the CoreMotion branch
  still does not apply tabletop and returns `tabletop: null`. No StandBy
  selection was added to the fold panel. See its
  [posture implementation](https://github.com/xuhom/vphone-cli/blob/33c02fbf46bb6ffad2578b514c49137661eec98c/VPhoneDaemon/Daemon/GuestAPI%2BDevice.swift#L641).
- [bvolpato's duo-global-display branch](https://github.com/bvolpato/vphone-cli/tree/ec2cbb1060b0504fbccc44d58d04521c1dfef221):
  global Duo display metadata and unrelated fixes, with no StandBy UI addition.
- [zhaoawd's duo-integration branch](https://github.com/zhaoawd/vphone-cli/tree/55e4f7ade3d188a0eecc86f6d3d2ce4197ddf79a):
  broader Duo integration, display/touch validation and power behavior, with
  no discovered Tent/Book StandBy selector.
- [steventroughtonsmith's Duo review branch](https://github.com/steventroughtonsmith/vphone-cli/tree/bb8e71c20d103aa1c166098b15146d5f929e050e)
  has no commits ahead of the current upstream baseline.
- The original [Duo support PR #728](https://github.com/Lakr233/vphone-cli/pull/728)
  was merged October 29. Upstream issue/PR search for StandBy returned no match;
  tabletop search returned that original PR. None of the three current open
  PRs adds StandBy controls.

Coverage limits: GitHub caps comparison file lists at 300; 13 heads hit this
limit. The expected current fold panel/model and device API files were fetched
directly for those heads (14 files existed, 25 paths were absent), with no
StandBy/tent/Rushmore match in those files. Two heads had no common ancestor:
one contained only always-on demonstration media, the other an old libtoolize
fix tree predating the current Duo implementation. This is a bounded survey of
public work, not proof that no private or unindexed implementation exists.

The existing **Device → Fold Posture** panel is the appropriate integration
point. Keep its Closed/Book/Open hinge selector and add a separate **StandBy**
section with **Off / Tent / Book**. Existing Book means a roughly 100-degree
hinge position; Book StandBy also requires tabletop classification and a locked
display. A UI implementation should use a dedicated guest capability/RPC for
the verified override/reset sequence, display actual readback, and clear the
override when ordinary fold controls are used. The title-bar open/close button
should continue working after leaving StandBy.

That would be a small host UI plus guest-daemon patch. The current native helper
proves the behavior before committing to a custom VPhone.bundle build. The
installed UI remains unchanged; no third-party fork was installed.

## UI implementation in this checkout

The Fold Posture panel now includes Off, Tent, and Book StandBy buttons and a
readback row. It uses the new `display_standby` capability and `display.standby`
RPC, so older guests retain normal folding while the new controls are disabled.
The guest performs the verified reset/hinge/lock/tabletop sequence, checks the
settled pose, and attempts reset after a failed entry. Ordinary fold requests
clear a StandBy tabletop override, including after its orientation changes.
The native pose setter now checks its Objective-C ABI before dispatch.

The panel reports pose acceptance rather than claiming that a face is visible.
Its readback polling does not overwrite a newer action, and the title-bar fold
button and StandBy commands share an in-flight guard. Failed transport replies
are followed by readback because the guest may already have applied the change.

Regression checks:

```zsh
VPhoneExecutable/VPhoneVirtualization/Tests/run-standby-tests.sh
VPhoneDaemon/Tests/run-methods-tests.sh
zsh VPhoneDaemon/Tests/run-result-schema-check.sh --method display.standby
xcodebuild -workspace VPhone.xcworkspace -scheme VPhone -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/XcodeBundle build
```

The regression suite covers both active poses, normal folding afterward, a
lost reply after a successful guest mutation, contradictory or unavailable
readback, old guests, and overlapping fold/StandBy requests. The native helper's
earlier live validation and the new UI/daemon build are separate evidence;
the initial build checks did not establish integrated UI behavior.

Validation completed in the fork checkout: the StandBy regression suite passed;
the method catalog reported 198 methods with zero failures; the focused
`display.standby` result-schema check passed; and the complete VPhone scheme
built successfully, including bundle admission validation. The resulting bundle
is `.build/XcodeBundle/Build/Products/Debug/VPhone.bundle`.

### Integrated live validation, November 8, 2026

Installed and ran `2.15.2-local.263764d1` through Launchpad's local-bundle
workflow on the existing `iphone-duo` guest, updating its guest environment.
The boot-chain bundle remains `2.15.2`; no machine was created and no host
security setting was changed.

The first integrated Tent test exposed an incorrect assumption: the daemon
waited for `getDevicePose` to reflect a real CoreMotion hinge transition.
That readback remained the zero test-override snapshot. This limitation is
also recorded in `iphone_duo_bringup.md`: the test-automation snapshot is not
reliable evidence of the current relay hinge. The corrected implementation
wakes the display, verifies the running HID provider's angle/orientation,
allows the display transition to settle, and uses test-automation readback
only for the explicit reset/Tent/Book overrides. Pose timeout errors now
include expected and observed values.

Tests performed by clicking the integrated Fold Posture panel:

| Action | Readback | Visible result |
| --- | --- | --- |
| Tent | mode tent, pose 1/2/7, angle 100°, interface 90° | Saved green Modular face, upright landscape |
| Tent → Book | mode book, pose 1/2/3, angle 180°, interface 90° | Split clock/calendar and Photos placeholder |
| Book → Off | mode off, angle 0°, interface 0° | Portrait cover lock screen |
| Off → Tent → ordinary Closed | mode off after Closed, angle 0° | StandBy cleared; normal portrait lock screen |
| Toolbar Open after Closed | mode off, angle 180°, interface 90° | Normal open lock screen |
| Open → Tent | mode tent, pose 1/2/7 | Green face visible; guest left here |

One Book click landed during a connection gap and did not transition; retrying
after reconnection succeeded. The transient connection failures remain, but
the host no longer bounces through portrait on disconnect. See
[`window_rotation_on_disconnect.md`](../window_rotation_on_disconnect.md)
for a simultaneous disconnected accessibility snapshot and landscape-window
capture. Real portrait/landscape changes were also verified after the fix.

The panel's Current Pose row reflects StandBy readback. Its existing Screen
State selector and Hinge Sensor detail rows retain the last normal-fold
request; they are not live StandBy hinge readouts.

The complete VPhone build, StandBy model/control regression suite, 198-method
catalog check, focused result-schema check, and `git diff --check` passed.
Guest captures are saved under
`/Users/mmuegel/Documents/ChatGPT/Misc/output/duo-standby/live-ui/` as
`tent.png`, `book.png`, and `off.png`. The integrated test does not establish
all face-gallery options, physical Duo panel fidelity, or Sundial widget
behavior. No PR, commit, or push was made.

## External references

- [Current upstream posture implementation](https://github.com/Lakr233/vphone-cli/blob/cb23353eb61b74186bc0b345fe34e6868b733746/VPhoneDaemon/Daemon/GuestAPI%2BDevice.swift#L622)
- [vphoned HTTP API and CoreMotion/tabletop behavior](https://lakr233.github.io/vphone-cli/research/vphoned_http_api.html)
- [Duo bring-up research](https://lakr233.github.io/vphone-cli/research/Guest/iphone_duo_bringup.html)
- [Apple: Use StandBy on iPhone](https://support.apple.com/en-jo/guide/iphone/iph878d77632/ios)
