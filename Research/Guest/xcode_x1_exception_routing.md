# Xcode launch stops in libLogRedirect on the Duo guest

Observed and worked around on 2026-11-08 with Xcode 27.2, the existing iPhone19,4 iOS 27.1 (24A94425) guest, and the local 2.15.2 bundle with the StandBy UI changes.

## Failure

Xcode installed the development app successfully, then stopped before its application initializers completed:

```text
EXC_BAD_INSTRUCTION (code=1, subcode=0xdac1a7fe)
libLogRedirect.dylib`__logredirect__write_nocancel + 0: pacibsppc
/System/Cryptexes/OS/usr/lib/libLogRedirect.dylib
```

The captured stack led through `__swrite`, `_swrite`, `__sflush`, `_vdprintf`, `dprintf`, and `SystemHook-vphone.dylib`'s `vpLogProcess`, then dyld initializers. This was an illegal-instruction stop in the logging library, not an installation failure or an application-code segmentation fault.

The debugger's `platform.plugin.darwin.ignored-exceptions` setting was empty. The guest uses an inherited BAD_INSTRUCTION handler for on-demand X1 instruction lowering; see [the existing exception-action research](x1_exception_actions.md). LLDB's default exception registration can intercept that fault before the compatibility handler sees it.

## Verified session workaround

In Xcode's LLDB console, before the next launch:

```lldb
settings set platform.plugin.darwin.ignored-exceptions EXC_BAD_INSTRUCTION
```

End the failed app run, then use Product → Perform Action → Run Without Building (Control-Command-R). In the observed session the setting persisted across this relaunch. It does not change the exception ports of an already attached process, so simply continuing the original stop is not equivalent.

This leaves the guest's BAD_INSTRUCTION handler in place while allowing the debugger to handle other exception classes. LLDB's setting documentation says that a resulting BSD signal can still stop the debugger. Do not additionally suppress SIGILL: genuine unsupported instructions should remain diagnosable.

The implementation can be checked in upstream LLVM: [MachTask::StartExceptionThread](https://github.com/llvm/llvm-project/blob/main/lldb/tools/debugserver/source/MacOSX/MachTask.mm) excludes the requested exception mask from `task_set_exception_ports`; [RNBRemote::HandlePacket_QSetIgnoredExceptions](https://github.com/llvm/llvm-project/blob/main/lldb/tools/debugserver/source/RNBRemote.cpp) refuses changes after a process is active.

## Verification and scope

- The same installed Sundial+ development build launched as PID 705 after the setting change (the failing process was PID 626).
- Xcode reported `Running Sundial Pro on iphone-duo` with its debugger attached and live app logs, including `didFinishLaunching` and `mainViewReady`.
- Guest `apps.foreground` independently reported `com.tier9digital.sundialv2`, PID 705, `verified: true`; a screenshot showed the app's main screen and onboarding with the guest's Location Services prompt.
- No application source, shared scheme, global LLDB initialization file, guest binaries, firmware, or host security settings were changed for this workaround.
- This was one successful cold app launch. Breakpoint stepping, further app flows, and persistence across restarting Xcode were not tested.

The setting was applied only in the active LLDB session; a newly created debugger session may require it again. To return future launches in the current session to the default routing:

```lldb
settings clear platform.plugin.darwin.ignored-exceptions
```

If a persistent workflow is desired, scope the setting to a dedicated vphone scheme's LLDB initialization file rather than applying it globally to all debugging destinations.
