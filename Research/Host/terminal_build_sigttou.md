# Terminal build suspended during package notice staging

Observed on macOS 27.2 (26B123), Xcode 27.2, 2026-11-08. A terminal invocation of the full VPhone build stalled in `stage-package-notices.zsh`. The build-phase process group was stopped, with `kinfo_proc.kp_proc.p_xstat` equal to 22 (SIGTTOU). Sending SIGCONT immediately stopped it again.

A small test launcher forked, placed its child in a separate process group with `setpgid(0, 0)`, executed the command, and observed `waitpid(..., WUNTRACED)`. Under a controlling terminal, Apple's `/bin/zsh` stopped on this minimal command even though its input was a regular file:

```zsh
while IFS= read -r -d '' item; do print -r -- "$item"; done < nul-records
```

Ordinary `read -r` did not stop. `read -d` with a nonempty delimiter and an explicit input file descriptor also stopped. Redirecting build stdout through tee and replacing process substitution with a regular file did not fix it. The failure was not a compiler hang, package-download wait, or administrator prompt.

The package notice collector now captures `git ls-tree -z` and `find -print0` output into zsh arrays using quoted `(@0)` splitting. This preserves spaces and newlines in records without the terminal-sensitive `read -d` path. Assignment failure also propagates under errexit. The existing package notice tests passed under the background-process-group reproducer after the change; the original collector stopped with SIGTTOU there.

The development CLI additionally streams the full build output through tee to `.build/XcodeBundle/dev-build.log`, preserving failure status with pipefail. That logging change improves diagnosis; the notice collector change fixes the suspension. No job-control signals or host protections are disabled.

The complete `scripts/dev-vphone.zsh build` then passed in a real PTY, including nested builds, package notices, bundle signing and validation. Launchpad installed the resulting local bundle and passed policy and host preflight using its existing authorization, without a manual sudo command.
