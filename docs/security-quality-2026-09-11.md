# Security and quality follow-up — 2026-09-11

This is a code-only 0.2.9 maintenance update. It merges the three reviewed
Dependabot PRs, fixes actual findings and CI failures, and records narrowly scoped
false-positive decisions. No release tag, store upload, or signing configuration
change is part of this work.

## Dependency PRs

- [#57](https://github.com/Nemoyuzx/where_to_study/pull/57): update the pinned
  `Swatinem/rust-cache` commit. The upstream comparison changes its own coverage/
  Nix workflows, not the action runtime. Workflow permissions stay unchanged.
- [#61](https://github.com/Nemoyuzx/where_to_study/pull/61): compatible npm tooling
  updates, including Vite 8.2.2 and React plugin 6.1.1. npm audit found no existing
  npm vulnerability before or after the update; this is not represented as a
  security fix for the Rust dependency alert.
- [#63](https://github.com/Nemoyuzx/where_to_study/pull/63): compatible Cargo lock
  updates. The three headless-client locks also move the yanked chacha20 0.10.1
  to 0.10.2. App versions remain 0.2.9. License notices are regenerated.

## Actual security fixes

### Assignment cache and terminal output

CodeQL #21: remove the password SHA-1 fingerprint entirely. Merely replacing it
with SHA-256 would still create an inappropriate fast password verifier. The
cache now accepts the credential revision captured alongside credentials under
the caller's account guard, and checks that same revision at read, write and
return. Old flights cannot populate or return a newer credential cache. Tests
use an isolated cache object to exercise rotation and stale completion without
network access. See [CodeQL guidance](https://codeql.github.com/codeql-query-help/rust/rust-weak-sensitive-data-hashing/).

CodeQL #17: remove the student-account value from CLI login-success output.
Password prompting remains hidden, and no password/credential command-line
argument is introduced.

### glib / RUSTSEC-2024-0429

The actual GTK3 graph requires glib 0.18, so substituting glib 0.20 is not an API-
compatible update. The original 0.18.5 crate reproducibly SIGSEGVs under the
optimized iterator regression. The exact upstream two-line fix passes the same
test. The reviewed source is vendored without a fabricated version number.
See [backport provenance and verification](../vendor/README.md) and
[the upstream fix](https://github.com/gtk-rs/gtk-rs-core/pull/1343).

Path dependencies are not matched against crates.io advisories by cargo-audit.
The security workflow therefore verifies all 121 source files and the actual
Linux Cargo graph before running the optimized regression and auditing five
lockfiles with `--deny unsound`. There is no advisory ignore list. Format checks
target the application package without reformatting the upstream source.

## CodeQL false positives

These instances retain their scan coverage and have individual GitHub dismissal
comments. No whole rule, production path, or scanner was disabled.

| Alerts | Evidence |
| --- | --- |
| #1, #29 | Constant `bash -c` text with separate, quoted positional arguments. Adversarial labels and file paths containing quotes, semicolons and command-substitution text remain data in the added regression. #29 is the updated helper fingerprint of the same safe invocation. |
| #2–10, #12–13, #22 | Fictional passwords in `settings_store`'s `cfg(test)` module, injected fake stores and isolated temporary directories. Never used for live authentication. |
| #11 | An empty password in a rejection-path test, not a usable deployed secret. |
| #18–20 | Temporary TUI credential fixtures testing round trips, deletion and 0700/0600 permissions. |
| #23–25 | Directory/file path constants (`where-to-study`, `cli-credentials.json`, `.config`) misattributed as the secret JSON contents read from a file. The path strings are not credentials. |

#26–28 were also fictional inputs to the now-removed password-hash test; their
instances disappear with the real #21 fix and are left for scan-based closure.

The `3294999` Rust analysis automatically marked #17, #21 and #26–28 fixed. Its
newly indexed vendored code produced #30–42, which were individually reviewed
against the full SARIF paths and concrete Rust/GLib types before dismissal:

- #30 incorrectly dispatches a `bool` conversion to `LogLevel::from_glib`.
- #31–35 connect concrete string/Error conversions to incompatible GObject,
  GValue or test-only `MyBoxed` implementations; some paths also disregard the
  non-null error branch and FFI out-parameter initialization.
- #36–41 connect `gchar**` string-array conversions to incompatible Checksum,
  GList, GSList or GPtrArray implementations. The actual results are
  `Vec<GString>` or `Vec<OsString>`, with documented populated out arrays.
- #42 confuses element destruction with freeing the backing allocation.
  `drop_in_place` followed by `ptr::write` reinitializes a still-valid slot;
  the allocation is freed only by `PtrSlice::drop`.

References: [GLib filename charsets](https://docs.gtk.org/glib/func.get_filename_charsets.html),
[GLib shell argument parsing](https://docs.gtk.org/glib/func.shell_parse_argv.html),
and [Rust drop-in-place safety](https://doc.rust-lang.org/std/ptr/fn.drop_in_place.html).
No vendored implementation was changed to mask these reports.

## Quality and verification

Windows/Linux strict Clippy failures are fixed using `std::slice::from_ref`
instead of cloned one-element slices. The TUI match guard now expresses its
length constraint directly. Strict warnings remain enabled.

The first new Linux build passed tests and Clippy but its Debian-package gate
detected an embedded checkout path. The Linux build wrapper now preserves caller
flags and adds rustc `--remap-path-prefix` via `CARGO_ENCODED_RUSTFLAGS`, including
checkout paths with spaces. The private-path rejection gate remains enabled and
now names the offending packaged file on failure. The next CI run must verify
the actual Debian/AppImage outputs; a local flag test alone is not that proof.

Local checks cover npm install, 190 repository tests, production build, npm
audit (zero findings), license verification, strict Tauri/CLI/TUI Clippy and
unit tests, exact glib source/resolve checks and the optimized glib regression.
The Rust audits report zero vulnerabilities, zero unsound findings and zero
yanked crates. Unmaintained-dependency notices remain visible: six in Tauri and
one in the independent regression crate. They are not hidden or represented as
fixed vulnerabilities. Headless core/CLI/TUI audits have no warnings.

Remote CI and the repository's alert states must be checked after the push;
local checks alone do not establish successful Windows/Linux builds or a
completed CodeQL analysis. GitHub's native secret-scanning API reports that
feature is disabled on this repository; the existing Gitleaks workflow and
local redacted scan remain active. No new security access was enabled.
