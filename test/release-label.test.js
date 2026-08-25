import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
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
  for (const label of ["v0.2.2", "v0.2.1", "v0.2.0-alpha", "v0.2.0-beta.1"]) {
    assert.doesNotThrow(() => validateReleaseLabel(label), label);
  }
});

test("release labels reject numeric suffixes after alpha", () => {
  for (const label of ["v0.2.0-alpha.1", "v0.2.0-alpha2", "v0.2.0-Alpha-4"]) {
    assert.throws(() => validateReleaseLabel(label), label);
  }
});

test("all tracked client projects use the stable 0.2.6 release version", () => {
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
  const nativeHarmony = readFileSync(
    path.join(root, "native", "harmony", "AppScope", "app.json5"),
    "utf8",
  );
  const tauriApple = readFileSync(path.join(root, "src-tauri", "gen", "apple", "project.yml"), "utf8");
  const tauriAppleInfo = readFileSync(
    path.join(root, "src-tauri", "gen", "apple", "where_to_study_iOS", "Info.plist"),
    "utf8",
  );
  const coreManifest = readFileSync(path.join(root, "where-to-study-core", "Cargo.toml"), "utf8");
  const cliManifest = readFileSync(path.join(root, "wts-cli", "Cargo.toml"), "utf8");
  const tuiManifest = readFileSync(path.join(root, "wts-tui", "Cargo.toml"), "utf8");
  const cliWorkflow = readFileSync(
    path.join(root, ".github", "workflows", "build-cli.yml"),
    "utf8",
  );
  const tuiWorkflow = readFileSync(
    path.join(root, ".github", "workflows", "build-tui.yml"),
    "utf8",
  );
  const androidPackageScript = readFileSync(
    path.join(root, "scripts", "native-android-package.sh"),
    "utf8",
  );
  const iosPackageScript = readFileSync(
    path.join(root, "scripts", "native-ios-package.sh"),
    "utf8",
  );
  const macosPackageScript = readFileSync(
    path.join(root, "scripts", "native-macos-package.sh"),
    "utf8",
  );

  assert.equal(packageMetadata.version, "0.2.6");
  assert.equal(tauriMetadata.version, "0.2.6");
  assert.equal(tauriMetadata.bundle.android.versionCode, 2009);
  assert.match(cargoManifest, /^version = "0\.2\.6"$/m);
  assert.match(coreManifest, /^version = "0\.2\.6"$/m);
  assert.match(cliManifest, /^version = "0\.2\.6"$/m);
  assert.match(tuiManifest, /^version = "0\.2\.6"$/m);
  assert.match(nativeAndroid, /versionName = "0\.2\.6"/);
  assert.match(nativeAndroid, /versionCode = 42/);
  assert.match(nativeApple, /MARKETING_VERSION: "0\.2\.6"/);
  assert.match(nativeApple, /CURRENT_PROJECT_VERSION: "72"/);
  assert.match(nativeHarmony, /"versionName": "0\.2\.6"/);
  assert.match(nativeHarmony, /"versionCode": 1002010/);
  assert.match(tauriApple, /CFBundleShortVersionString: 0\.2\.6/);
  assert.match(tauriApple, /CFBundleVersion: "45"/);
  assert.match(tauriAppleInfo, /<string>0\.2\.6<\/string>/);
  assert.match(tauriAppleInfo, /<string>45<\/string>/);
  assert.match(cliWorkflow, /grep -F '0\.2\.6'/);
  assert.match(tuiWorkflow, /grep -F '0\.2\.6'/);
  assert.match(androidPackageScript, /RELEASE_LABEL="\$\{1:-v0\.2\.6\}"/);
  assert.match(iosPackageScript, /RELEASE_LABEL="\$\{1:-v0\.2\.6\}"/);
  assert.match(macosPackageScript, /RELEASE_LABEL="\$\{1:-v0\.2\.6\}"/);
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

test("Android release validates the packaged narrow contest API cleartext exception", () => {
  const packagingScript = readFileSync(
    path.join(root, "scripts", "native-android-package.sh"),
    "utf8",
  );

  assert.match(packagingScript, /AAPT2=.*-name aapt2/);
  assert.match(packagingScript, /dump xmltree "\$SIGNED_APK" --file AndroidManifest\.xml/);
  assert.match(packagingScript, /xml\\\/network_security_config\$/);
  assert.match(packagingScript, /A: cleartextTrafficPermitted=false/);
  assert.match(packagingScript, /A: cleartextTrafficPermitted=true/);
  assert.match(packagingScript, /A: includeSubdomains=false/);
  assert.match(packagingScript, /A: src="system"/);
  assert.match(packagingScript, /101\.201\.29\.29/);
  assert.match(packagingScript, /NETWORK_DOMAIN_COUNT/);
  assert.doesNotMatch(
    packagingScript,
    /unzip -p "\$SIGNED_APK" AndroidManifest\.xml.*networkSecurityConfig/,
  );
});

test("native Apple targets keep the App Store Connect bundle identifiers", () => {
  const nativeApple = readFileSync(path.join(root, "native", "apple", "project.yml"), "utf8");
  const appStoreScript = readFileSync(
    path.join(root, "scripts", "native-apple-app-store.sh"),
    "utf8",
  );
  const iosPackageScript = readFileSync(
    path.join(root, "scripts", "native-ios-package.sh"),
    "utf8",
  );

  assert.equal(
    nativeApple.match(
      /^\s*PRODUCT_BUNDLE_IDENTIFIER: com\.nemoyu\.wheretostudy\.native\.macos$/gm,
    )?.length,
    2,
  );
  assert.match(
    appStoreScript,
    /MAIN_BUNDLE_IDENTIFIER="com\.nemoyu\.wheretostudy\.native\.macos"/,
  );
  assert.match(
    iosPackageScript,
    /EXPECTED_BUNDLE_IDENTIFIER="com\.nemoyu\.wheretostudy\.native\.macos"/,
  );
});

test("native macOS release restores a verified universal DMG", () => {
  const packagingScript = readFileSync(
    path.join(root, "scripts", "native-macos-package.sh"),
    "utf8",
  );
  const nativeWorkflow = readFileSync(
    path.join(root, ".github", "workflows", "build-native.yml"),
    "utf8",
  );

  assert.match(packagingScript, /native-macos-universal\.dmg/);
  assert.match(packagingScript, /PACKAGE_APP="\$TEMP_DIR\/WhereToStudyMac\.app"/);
  assert.match(
    packagingScript,
    /ditto "\$PACKAGE_APP" "\$DMG_ROOT\/WhereToStudyMac\.app"/,
  );
  assert.match(packagingScript, /ln -s \/Applications/);
  assert.match(packagingScript, /hdiutil create/);
  assert.match(packagingScript, /-format UDZO/);
  assert.match(packagingScript, /hdiutil verify "\$DMG"/);
  assert.match(nativeWorkflow, /native-macos-universal\.dmg/);
  assert.match(nativeWorkflow, /native-macos-universal\.dmg\.sha256/);
});

test("native Apple CI retries transient UI automation failures and preserves diagnostics", () => {
  const nativeAppleBuildScript = readFileSync(
    path.join(root, "scripts", "native-apple-build.sh"),
    "utf8",
  );
  const nativeWorkflow = readFileSync(
    path.join(root, ".github", "workflows", "build-native.yml"),
    "utf8",
  );

  assert.match(nativeAppleBuildScript, /-retry-tests-on-failure/);
  assert.match(nativeAppleBuildScript, /-test-iterations 2/);
  assert.match(nativeWorkflow, /timeout-minutes: 45/);
  assert.match(nativeWorkflow, /Upload Apple test diagnostics on failure/);
  assert.match(nativeWorkflow, /native\/apple\/DerivedData\/\*\*\/Logs\/Test\/\*\.xcresult/);
  assert.match(nativeWorkflow, /where-to-study-native-apple-test-results-/);
});

test("Xcode Cloud generates the ignored native Apple project after cloning", () => {
  const cloudScript = readFileSync(
    path.join(root, "native", "apple", "ci_scripts", "ci_post_clone.sh"),
    "utf8",
  ).replaceAll("\r\n", "\n");
  const nativeApple = readFileSync(path.join(root, "native", "apple", "project.yml"), "utf8");
  const gitignore = readFileSync(path.join(root, ".gitignore"), "utf8");

  assert.match(gitignore, /^native\/apple\/WhereToStudyNative\.xcodeproj\/$/m);
  assert.match(gitignore, /^native\/apple\/Generated\/$/m);
  assert.match(nativeApple, /minimumXcodeGenVersion: 2\.45\.4/);
  assert.match(cloudScript, /^#!\/bin\/sh\nset -eu/m);
  assert.match(cloudScript, /CI_PRIMARY_REPOSITORY_PATH/);
  assert.match(cloudScript, /brew install xcodegen/);
  assert.match(cloudScript, /scripts\/native-apple-generate\.sh/);
  assert.match(cloudScript, /PROJECT="\$APPLE_DIR\/WhereToStudyNative\.xcodeproj"/);
  assert.match(cloudScript, /"\$PROJECT\/project\.pbxproj"/);
  assert.match(cloudScript, /xcodebuild -project "\$PROJECT" -list/);
});

test("Linux releases build and validate both deb and AppImage artifacts", () => {
  const packageMetadata = JSON.parse(readFileSync(path.join(root, "package.json")));
  const workflow = readFileSync(
    path.join(root, ".github", "workflows", "build-linux.yml"),
    "utf8",
  );
  const packagingScript = readFileSync(
    path.join(root, "scripts", "linux-package.sh"),
    "utf8",
  );
  const hardeningScript = readFileSync(
    path.join(root, "scripts", "harden-linux-appimage.sh"),
    "utf8",
  );

  assert.match(packageMetadata.scripts["tauri:build:linux"], /--bundles deb,appimage/);
  assert.match(workflow, /runner: ubuntu-22\.04/);
  assert.match(workflow, /runner: ubuntu-22\.04-arm/);
  assert.match(workflow, /artifact: where-to-study-linux-aarch64/);
  assert.match(workflow, /runs-on: ubuntu-24\.04/);
  assert.match(workflow, /Acquire::Retries=5/);
  assert.match(workflow, /libwebkit2gtk-4\.1-dev/);
  assert.match(workflow, /install --no-install-recommends -y "\$deb_path"/);
  assert.match(workflow, /\.\/scripts\/linux-package\.sh "\$RELEASE_LABEL"/);
  assert.match(packagingScript, /dpkg-deb -f "\$DEB_PATH" Version/);
  assert.match(packagingScript, /lib\(ayatana-\)\?appindicator3-1/);
  assert.match(packagingScript, /--appimage-extract/);
  assert.match(packagingScript, /DEB_EXPECTED_ARCHITECTURE="arm64"/);
  assert.match(packagingScript, /RELEASE_ARCHITECTURE="aarch64"/);
  assert.match(packagingScript, /linux-\$RELEASE_ARCHITECTURE\.deb/);
  assert.match(packagingScript, /linux-\$RELEASE_ARCHITECTURE\.AppImage/);
  assert.match(packagingScript, /APPIMAGETOOL_PATH/);
  assert.match(packagingScript, /APPIMAGE_TOOL_SHA256/);
  assert.match(packagingScript, /harden-linux-appimage\.sh/);
  assert.match(hardeningScript, /libwayland-\*\.so\*/);
  assert.match(hardeningScript, /GIO_MODULE_DIR/);
  assert.match(hardeningScript, /GIO_USE_VFS=local/);
});

test(
  "Linux AppImage hardening removes Wayland ABI libraries and is idempotent",
  { skip: process.platform === "win32" },
  () => {
    const fixture = mkdtempSync(path.join(tmpdir(), "wts-appimage-hardening-"));
    const appDir = path.join(fixture, "WhereToStudy.AppDir");
    const libDir = path.join(appDir, "usr", "lib");
    const hookDir = path.join(appDir, "apprun-hooks");
    const hookPath = path.join(hookDir, "linuxdeploy-plugin-gtk.sh");
    const hardener = path.join(root, "scripts", "harden-linux-appimage.sh");

    try {
      mkdirSync(path.join(libDir, "aarch64-linux-gnu", "gio", "modules"), {
        recursive: true,
      });
      mkdirSync(hookDir, { recursive: true });
      writeFileSync(path.join(libDir, "libwayland-client.so.0"), "fixture");
      writeFileSync(path.join(libDir, "libwayland-egl.so.1"), "fixture");
      writeFileSync(hookPath, "#!/usr/bin/env bash\nexport APPDIR\n");

      execFileSync("bash", [hardener, appDir], { stdio: "pipe" });
      execFileSync("bash", [hardener, appDir], { stdio: "pipe" });

      assert.equal(existsSync(path.join(libDir, "libwayland-client.so.0")), false);
      assert.equal(existsSync(path.join(libDir, "libwayland-egl.so.1")), false);
      const hook = readFileSync(hookPath, "utf8");
      assert.match(hook, /export GIO_MODULE_DIR=/);
      assert.match(hook, /export GIO_EXTRA_MODULES=/);
      assert.match(hook, /export GIO_USE_VFS=local/);
      assert.match(hook, /unset GST_PLUGIN_SYSTEM_PATH GST_PLUGIN_SYSTEM_PATH_1_0/);
      assert.equal(
        hook.match(/# Where To Study AppImage host ABI isolation/g)?.length,
        1,
      );
    } finally {
      rmSync(fixture, { recursive: true, force: true });
    }
  },
);

test("Linux CLI and TUI workflows package x86_64 and native arm64 archives", () => {
  for (const [workflowName, binary] of [
    ["build-cli.yml", "where-to-study-cli"],
    ["build-tui.yml", "where-to-study-tui"],
  ]) {
    const workflow = readFileSync(
      path.join(root, ".github", "workflows", workflowName),
      "utf8",
    );
    assert.match(workflow, /runner: ubuntu-22\.04/);
    assert.match(workflow, /runner: ubuntu-22\.04-arm/);
    assert.match(workflow, /arch: x86_64/);
    assert.match(workflow, /arch: aarch64/);
    assert.match(workflow, new RegExp(`${binary}-linux-\\$\\{\\{ matrix\\.arch \\}\\}\\.tar\\.gz`));
  }
});
