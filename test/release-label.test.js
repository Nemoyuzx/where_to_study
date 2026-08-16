import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import test from "node:test";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const validationScript = path.join(root, "scripts", "package-validation.sh");

function validateReleaseLabel(label) {
  execFileSync(
    "bash",
    ["-c", 'source "$1"; validate_release_label "$2"', "validate", validationScript, label],
    { stdio: "pipe" },
  );
}

test("release labels accept stable and unnumbered alpha versions", () => {
  for (const label of ["v0.1.4", "v0.2.0-alpha", "v0.2.0-beta.1"]) {
    assert.doesNotThrow(() => validateReleaseLabel(label), label);
  }
});

test("release labels reject numeric suffixes after alpha", () => {
  for (const label of ["v0.2.0-alpha.1", "v0.2.0-alpha2", "v0.2.0-Alpha-4"]) {
    assert.throws(() => validateReleaseLabel(label), label);
  }
});

test("all tracked client projects use the stable 0.1.4 release version", () => {
  const packageMetadata = JSON.parse(readFileSync(path.join(root, "package.json")));
  const tauriMetadata = JSON.parse(
    readFileSync(path.join(root, "src-tauri", "tauri.conf.json")),
  );
  const cargoManifest = readFileSync(path.join(root, "src-tauri", "Cargo.toml"), "utf8");
  const nativeAndroid = readFileSync(
    path.join(root, "native", "android", "app", "build.gradle.kts"),
    "utf8",
  );
  const nativeApple = readFileSync(path.join(root, "native", "apple", "project.yml"), "utf8");
  const tauriApple = readFileSync(path.join(root, "src-tauri", "gen", "apple", "project.yml"), "utf8");
  const tauriAppleInfo = readFileSync(
    path.join(root, "src-tauri", "gen", "apple", "where_to_study_iOS", "Info.plist"),
    "utf8",
  );

  assert.equal(packageMetadata.version, "0.1.4");
  assert.equal(tauriMetadata.version, "0.1.4");
  assert.equal(tauriMetadata.bundle.android.versionCode, 1004);
  assert.match(cargoManifest, /^version = "0\.1\.4"$/m);
  assert.match(nativeAndroid, /versionName = "0\.1\.4"/);
  assert.match(nativeAndroid, /versionCode = 18/);
  assert.match(nativeApple, /MARKETING_VERSION: "0\.1\.4"/);
  assert.match(nativeApple, /CURRENT_PROJECT_VERSION: "32"/);
  assert.match(tauriApple, /CFBundleShortVersionString: 0\.1\.4/);
  assert.match(tauriApple, /CFBundleVersion: "31"/);
  assert.match(tauriAppleInfo, /<string>0\.1\.4<\/string>/);
  assert.match(tauriAppleInfo, /<string>31<\/string>/);
});

test("Android adaptive icons keep the canonical logo inside the launcher safe zone", () => {
  const iconRoot = path.join(
    root,
    "native",
    "android",
    "app",
    "src",
    "main",
    "res",
  );

  const safeForeground = readFileSync(
    path.join(iconRoot, "drawable", "ic_launcher_foreground_safe.xml"),
    "utf8",
  );
  assert.match(safeForeground, /android:drawable="@mipmap\/ic_launcher_foreground"/);
  assert.match(safeForeground, /android:inset="18dp"/);

  for (const filename of ["ic_launcher.xml", "ic_launcher_round.xml"]) {
    const adaptiveIcon = readFileSync(
      path.join(iconRoot, "mipmap-anydpi-v26", filename),
      "utf8",
    );
    assert.match(adaptiveIcon, /@drawable\/ic_launcher_foreground_safe/);
    assert.match(adaptiveIcon, /@color\/ic_launcher_background/);
  }
});
