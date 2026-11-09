# Preserve window orientation during agent connection gaps

Observed on 2026-11-08 with the local 2.15.2 bundle, iPhone19,4 / iOS 27.1 guest, and Sundial+ running. The user reported window rotation while moving the mouse around or outside the VM window.

The guest's attitude and gyroscope overrides were both disabled. Twelve consecutive `display.orientation` requests at approximately half-second intervals returned ten successful landscape (`degrees: 90`) readings and two `The guest agent is not connected` failures. StandBy was off. No evidence established that mouse movement was changing the guest's physical orientation.

The host has an independent rotation-reset bug: `VPhoneGuestControl.setDisconnected()` clears `interfaceOrientation`, and the window observer converted that nil value to `.portrait`. The next successful orientation poll restored landscape. A transient health-probe failure can therefore animate the window into portrait and back even though iOS never rotates.

The window observer now ignores unknown orientation readings and retains the last rendered orientation. Initial window construction already establishes portrait, and subsequent concrete orientation readings still animate normally. Connection status remains unavailable during the gap; this change does not hide disconnection or change guest rotation lock, motion inputs, StandBy pose, or polling behavior.

Validation: scoped source/diff checks and the full `VPhone` Debug bundle build, followed by a live test on local bundle `2.15.2-local.263764d1` (host and guest environment) on November 8, 2026, America/Chicago. The original boot-chain bundle remains `2.15.2`.

With Tent StandBy visible, twenty orientation polls returned nineteen landscape readings (`degrees: 90`, `fold_angle: 100`) and one disconnected failure. Moving the cursor between the guest title bar and the macOS menu bar, and switching focus between the guest and Fold Posture panel, did not produce an unwanted rotation.

At `2026-11-09T05:02:45.748Z`, a CUA accessibility snapshot caught a real disconnected state: Home disabled and the iOS/IP subtitle absent. Its simultaneous host-window screenshot still showed the green Tent face upright in the same landscape window (786 × 644 including chrome). The next connected snapshot restored the subtitle/Home control with the same rotation and dimensions. This directly verifies preservation across an unknown-orientation notification, rather than inferring it from guest framebuffer captures alone.

Intentional rotation also works: StandBy Off and normal Closed returned the host to a portrait lock screen; the toolbar's ordinary open action returned to landscape with StandBy off. Tent was then re-entered and left running. CUA does not expose pure mouse-hover motion, so the cursor/focus test is bounded to the interactions above. The underlying intermittent transport failures still occur and were not root-caused by this fix.

RPC polling evidence: `/Users/mmuegel/Documents/ChatGPT/Misc/output/duo-standby/live-ui/orientation-polls.txt`. Host-window screenshots and accessibility snapshots are retained in the test conversation.
