# glib 0.18.5 security backport

`glib-0.18.5/` contains the complete crates.io source archive, including its MIT
license and copyright notices, with only the two-line fix from upstream
[gtk-rs-core PR #1343](https://github.com/gtk-rs/gtk-rs-core/pull/1343) applied to
`src/variant_iter.rs`. The pointer passed to the variadic C function is now
mutable (`let mut p` and `&mut p`). This fixes
[RUSTSEC-2024-0429](https://rustsec.org/advisories/RUSTSEC-2024-0429.html).

Tauri's Linux GTK3 dependencies require the glib 0.18 API. The current upstream
0.18 branch still contains the defect; glib 0.20 is not a compatible replacement
for that dependency graph. This copy deliberately retains version **0.18.5**.

Provenance:

- Archive: https://static.crates.io/crates/glib/glib-0.18.5.crate
- Archive SHA-256: `233daaf6e83ae6a12a52055f568f9d7cf4671dabb78ff9560ab6da230ce00ee5`
- Upstream source commit: `42b9caf98e03ded086362d9653ca58fe94dc8658`
- Fix commit: `b5a4071e439bef2b5eea76c3aa25e5ae84839e34`
- Original source tree SHA-256: `bbddb7d9a33942228342f3015d2d620505839f9c30138e7edb3cc09bc83d3d21`
- Patched source tree SHA-256: `f22fab2b2dfb31cee274824539dce5b1f601dc80eab177fbbf56eb72834bb356`

The tree hashes cover all 121 archive files, sorted by relative POSIX path, with
each path, a NUL byte, the exact file bytes, and another NUL byte added to SHA-256.
`vendor/.gitattributes` preserves those bytes on Windows too.

Verification:

```sh
node scripts/verify-glib-patch.mjs --resolve
cargo test --manifest-path scripts/glib-regression/Cargo.toml --release --locked
cargo audit --file src-tauri/Cargo.lock --deny unsound
```

The regression needs the GLib development library (`libglib2.0-dev` on Ubuntu,
`glib` through Homebrew on macOS). It exercises every affected iterator method,
including Unicode and empty strings, under release optimization. The original
registry source reproduced a SIGSEGV with this test; the exact backport passes.

`cargo audit` does not match crates.io advisories against local path packages.
Therefore an audit without the source integrity and Linux dependency-resolution
checks is not sufficient evidence for this backport. No advisory is ignored and
no patched-version number is fabricated. The audit still reports unrelated
unmaintained dependencies. The existing license generator discovers this path
package through Cargo metadata and includes its original MIT license.

Remove the override and this vendored source when Tauri's GTK dependency graph
supports a maintained, patched upstream release; rerun all three checks and
regenerate `THIRD_PARTY_LICENSES.html` when doing so. Keep this source unchanged
when formatting application code.
