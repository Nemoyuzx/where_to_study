import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
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

function validateReleaseLabel(label, script = validationScript) {
  execFileSync(
    "bash",
    ["-c", 'source "$1"; validate_release_label "$2"', "validate", script, label],
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

test("release validation treats shell metacharacters in paths and labels as data", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "wts-label-arguments-"));
  const marker = path.join(directory, "unexpected-command");
  const script = path.join(directory, "validation 'quoted' $(exit 71); exit 72;.sh");
  try {
    writeFileSync(script, readFileSync(validationScript));
    assert.doesNotThrow(() => validateReleaseLabel("v0.2.9", script));
    for (const label of [
      `v0.2.9; touch '${marker}'`,
      `$(touch '${marker}')`,
      `v0.2.9\n touch '${marker}'`,
    ]) {
      assert.throws(() => validateReleaseLabel(label, script));
    }
    assert.equal(existsSync(marker), false);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("client versions consistently release 0.2.9 with fresh distribution build counters", () => {
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
  const nativeHarmonyAppMeta = readFileSync(
    path.join(root, "native", "harmony", "entry", "src", "main", "ets", "common", "AppMeta.ets"),
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
  const nativeWorkflow = readFileSync(
    path.join(root, ".github", "workflows", "build-native.yml"),
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

  assert.equal(packageMetadata.version, "0.2.9");
  assert.equal(tauriMetadata.version, "0.2.9");
  assert.equal(tauriMetadata.bundle.android.versionCode, 2011);
  assert.match(cargoManifest, /^version = "0\.2\.9"$/m);
  assert.match(coreManifest, /^version = "0\.2\.9"$/m);
  assert.match(cliManifest, /^version = "0\.2\.9"$/m);
  assert.match(tuiManifest, /^version = "0\.2\.9"$/m);
  assert.match(nativeAndroid, /versionName = "0\.2\.9"/);
  assert.match(nativeAndroid, /versionCode = 49/);
  assert.match(nativeApple, /MARKETING_VERSION: "0\.2\.9"/);
  assert.match(nativeApple, /CURRENT_PROJECT_VERSION: "92"/);
  assert.match(nativeHarmony, /"versionName": "0\.2\.9"/);
  assert.match(nativeHarmony, /"versionCode": 1002030/);
  assert.match(nativeHarmonyAppMeta, /static readonly version: string = '0\.2\.9'/);
  assert.match(tauriApple, /CFBundleShortVersionString: 0\.2\.9/);
  assert.match(tauriApple, /CFBundleVersion: "47"/);
  assert.match(tauriAppleInfo, /<string>0\.2\.9<\/string>/);
  assert.match(tauriAppleInfo, /<string>47<\/string>/);
  assert.match(cliWorkflow, /grep -F '0\.2\.9'/);
  assert.match(tuiWorkflow, /grep -F '0\.2\.9'/);
  assert.match(nativeWorkflow, /native-android-universal\.apk/);
  assert.doesNotMatch(nativeWorkflow, /native-android\.aab/);
  assert.match(androidPackageScript, /RELEASE_LABEL="\$\{1:-v0\.2\.9\}"/);
  assert.match(iosPackageScript, /RELEASE_LABEL="\$\{1:-v0\.2\.9\}"/);
  assert.match(macosPackageScript, /RELEASE_LABEL="\$\{1:-v0\.2\.9\}"/);
});

test("GitHub workflows publish neither HarmonyOS packages nor Android AAB files", () => {
  const workflowDirectory = path.join(root, ".github", "workflows");
  const workflowSource = readdirSync(workflowDirectory)
    .filter((filename) => /\.ya?ml$/.test(filename))
    .map((filename) => readFileSync(path.join(workflowDirectory, filename), "utf8"))
    .join("\n");

  assert.doesNotMatch(
    workflowSource,
    /\.hap\b|harmonyos-signed\.app|native-android\.aab/i,
  );
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

test("Android release validates an HTTPS-only packaged network policy", () => {
  const packagingScript = readFileSync(
    path.join(root, "scripts", "native-android-package.sh"),
    "utf8",
  );

  assert.match(packagingScript, /AAPT2=.*-name aapt2/);
  assert.match(packagingScript, /dump xmltree "\$SIGNED_APK" --file AndroidManifest\.xml/);
  assert.match(packagingScript, /xml\\\/network_security_config\$/);
  assert.match(packagingScript, /A: cleartextTrafficPermitted=false/);
  assert.match(packagingScript, /A: src="system"/);
  assert.match(packagingScript, /NETWORK_DOMAIN_CONFIG_COUNT.*!= 0/s);
  assert.match(packagingScript, /NETWORK_DOMAIN_COUNT/);
  assert.doesNotMatch(packagingScript, /cleartextTrafficPermitted=true/);
  assert.doesNotMatch(
    packagingScript,
    /unzip -p "\$SIGNED_APK" AndroidManifest\.xml.*networkSecurityConfig/,
  );
});

test("all graphical clients pin contest APIs to the HTTPS product domain", () => {
  const sourceFiles = [
    path.join(root, "src-tauri", "src", "deadlines.rs"),
    path.join(root, "native", "apple", "Sources", "Shared", "CalendarDeadlineClient.swift"),
    path.join(
      root,
      "native",
      "android",
      "app",
      "src",
      "main",
      "java",
      "com",
      "nemoyu",
      "wheretostudy",
      "nativeapp",
      "CalendarDailyInfoClient.kt",
    ),
    path.join(
      root,
      "native",
      "harmony",
      "entry",
      "src",
      "main",
      "ets",
      "net",
      "CalendarDailyInfoClient.ets",
    ),
  ];

  for (const filename of sourceFiles) {
    const source = readFileSync(filename, "utf8");
    assert.match(source, /https:\/\/where-to-study\.cn\/api\/contest-events/);
    assert.match(source, /https:\/\/where-to-study\.cn\/api\/contest-notices/);
    assert.doesNotMatch(source, /101\.201\.29\.29|http:\/\/where-to-study\.cn/);
  }
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
  assert.match(appStoreScript, /validate_exported_ios_package/);
  assert.match(appStoreScript, /Authority=Apple Distribution:/);
  assert.match(appStoreScript, /get-task-allow/);
  assert.match(
    appStoreScript,
    /IOS_SIGNING_STYLE" == "Automatic"[\s\S]*export_or_upload_platform "\$current_platform" export/,
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
  assert.match(packagingScript, /PACKAGE_APP="\$TEMP_DIR\/Where To Study\.app"/);
  assert.match(
    packagingScript,
    /ditto "\$PACKAGE_APP" "\$DMG_ROOT\/Where To Study\.app"/,
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
  ).replaceAll("\r\n", "\n");

  assert.match(nativeAppleBuildScript, /-retry-tests-on-failure/);
  assert.match(nativeAppleBuildScript, /-test-iterations 2/);
  for (const lineEnding of ["\n", "\r\n"]) {
    const workflowText = nativeWorkflow.replaceAll("\n", lineEnding).replaceAll("\r\n", "\n");
    assert.match(workflowText, /apple:\s*\n(?:.*\n)*?\s+timeout-minutes: 60/);
    assert.match(workflowText, /name: Build Apple clients and run platform unit tests\s*\n\s+timeout-minutes: 50/);
  }
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

  assert.equal(packageMetadata.scripts["tauri:build:linux"], "bash ./scripts/linux-build.sh");
  const linuxBuild = readFileSync(path.join(root, "scripts", "linux-build.sh"), "utf8");
  assert.match(linuxBuild, /--bundles deb,appimage/);
  assert.match(linuxBuild, /--remap-path-prefix=/);
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
  assert.match(packagingScript, /-name 'where_to_study'/);
  assert.match(hardeningScript, /libwayland-\*\.so\*/);
  assert.match(hardeningScript, /GIO_MODULE_DIR/);
  assert.match(hardeningScript, /GIO_USE_VFS=local/);
});

test(
  "Linux AppImage tools use fixed official asset IDs and reject unverified bytes",
  { skip: process.platform === "win32" },
  () => {
    const script = readFileSync(path.join(root, "scripts", "linux-package.sh"), "utf8");
    const pins = script.match(/case "\$RELEASE_ARCHITECTURE" in\n[\s\S]+?\nesac/)[0];
    const start = script.indexOf('\nAPPIMAGE_TOOL="${APPIMAGETOOL_PATH:-}"');
    const verifiedEnd = script.indexOf('\nchmod +x "$APPIMAGE_TOOL"', start);
    assert.ok(start >= 0 && verifiedEnd > start);
    assert.ok(verifiedEnd < script.indexOf('"$APPIMAGE_TOOL" --appdir "$APPDIR"'));
    const fetchAndVerify = script.slice(start, verifiedEnd);
    assert.doesNotMatch(fetchAndVerify, /releases\/download\/continuous/);

    const expectedPins = {
      x86_64: ["538914683", "0441769ab38009504d2678c38cd7e526955388dd30a215b4a20afaa5471652f2"],
      aarch64: ["538914264", "ce574719bcf9cc1fb12728d60b17e48cc87d9b6c40f6f48b04cff7d273b5eb24"],
    };
    const fixture = mkdtempSync(path.join(tmpdir(), "wts-appimage-tool-pin-"));
    const bin = path.join(fixture, "bin");
    const download = path.join(fixture, "download.AppImage");
    const curlArguments = path.join(fixture, "curl-arguments.txt");
    const validBytes = "verified test fixture; never executed\n";
    const fixtureDigest = createHash("sha256").update(validBytes).digest("hex");
    try {
      mkdirSync(bin);
      mkdirSync(path.join(fixture, "tools"));
      mkdirSync(path.join(fixture, "cache", "tauri"), { recursive: true });
      writeFileSync(path.join(bin, "sha256sum"), `#!/usr/bin/env node
const { createHash } = require("node:crypto");
const { readFileSync } = require("node:fs");
const file = process.argv[2];
process.stdout.write(createHash("sha256").update(readFileSync(file)).digest("hex") + "  " + file + "\\n");
`, { mode: 0o755 });
      writeFileSync(path.join(bin, "curl"), `#!/usr/bin/env bash
set -eu
printf '%s\\n' "$@" > "$WTS_TEST_CURL_ARGUMENTS"
output=""
while (( $# )); do
  if [[ "$1" == "--output" ]]; then output="$2"; shift 2; else shift; fi
done
cp "$WTS_TEST_DOWNLOAD_SOURCE" "$output"
`, { mode: 0o755 });
      const env = {
        ...process.env,
        PATH: `${bin}${path.delimiter}${process.env.PATH}`,
        TEMP_DIR: fixture,
        XDG_CACHE_HOME: path.join(fixture, "cache"),
        APPIMAGETOOL_PATH: "",
        WTS_TEST_DOWNLOAD_SOURCE: download,
        WTS_TEST_CURL_ARGUMENTS: curlArguments,
        WTS_TEST_EXPECTED_SHA256: fixtureDigest,
      };
      for (const [architecture, [assetID, digest]] of Object.entries(expectedPins)) {
        const architectureEnv = { ...env, RELEASE_ARCHITECTURE: architecture };
        const actualPins = execFileSync("bash", ["-c", `${pins}\nprintf '%s\\n' "$APPIMAGE_TOOL_ASSET_ID" "$APPIMAGE_TOOL_SHA256"`],
          { env: architectureEnv, encoding: "utf8" }).trim().split("\n");
        assert.deepEqual(actualPins, [assetID, digest]);
        // Exercise the production verification block with known fixture bytes, without network or executing an AppImage.
        const harness = `set -euo pipefail\n${pins}\nAPPIMAGE_TOOL_SHA256="$WTS_TEST_EXPECTED_SHA256"\n${fetchAndVerify}`;
        const run = (overrides = {}) => execFileSync("bash", ["-c", harness],
          { env: { ...architectureEnv, ...overrides }, encoding: "utf8", stdio: "pipe" });
        writeFileSync(download, validBytes);
        assert.doesNotThrow(() => run());
        const argumentsText = readFileSync(curlArguments, "utf8");
        assert.ok(argumentsText.includes("Accept: application/octet-stream"));
        assert.ok(argumentsText.includes(`https://api.github.com/repos/linuxdeploy/linuxdeploy-plugin-appimage/releases/assets/${assetID}`));
        writeFileSync(download, "unexpected replacement bytes\n");
        assert.throws(() => run(), (error) => /checksum does not match the pinned digest/.test(error.stderr));
        writeFileSync(curlArguments, "");
        assert.throws(() => run({ APPIMAGETOOL_PATH: download }),
          (error) => /checksum does not match the pinned digest/.test(error.stderr));
        assert.equal(readFileSync(curlArguments, "utf8"), "", "An explicit unverified tool must not trigger a replacement download");
        const cached = path.join(fixture, "cache", "tauri", `linuxdeploy-plugin-appimage-${architecture}.AppImage`);
        writeFileSync(cached, validBytes);
        assert.doesNotThrow(() => run());
        assert.equal(readFileSync(curlArguments, "utf8"), "", "A matching verified cache should be reused");
      }
    } finally {
      rmSync(fixture, { recursive: true, force: true });
    }
  },
);

test("desktop release packages verify all fixed public-data endpoints", () => {
  const linuxPackaging = readFileSync(
    path.join(root, "scripts", "linux-package.sh"),
    "utf8",
  );
  const windowsWorkflow = readFileSync(
    path.join(root, ".github", "workflows", "build-windows.yml"),
    "utf8",
  );
  const macosPackaging = readFileSync(
    path.join(root, "scripts", "macos-package.sh"),
    "utf8",
  );

  for (const source of [linuxPackaging, windowsWorkflow, macosPackaging]) {
    assert.match(source, /https:\/\/where-to-study\.cn\/api\/contest-events/);
    assert.match(source, /https:\/\/where-to-study\.cn\/api\/contest-notices/);
    assert.match(source, /https:\/\/where-to-study\.cn\/api\/shuttle-bus/);
    assert.match(source, /retired contest API host/);
  }
});

test("every graphical release package validates the fixed shuttle endpoint", () => {
  for (const filename of [
    "scripts/macos-package.sh",
    "scripts/native-ios-package.sh",
    "scripts/native-macos-package.sh",
    "scripts/native-apple-app-store.sh",
    "scripts/native-android-package.sh",
    "scripts/native-harmony-build.sh",
  ]) {
    const source = readFileSync(path.join(root, filename), "utf8");
    assert.match(source, /https:\/\/where-to-study\.cn\/api\/shuttle-bus/);
    assert.match(source, /required HTTPS public-data endpoint/);
  }
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
    ).replaceAll("\r\n", "\n");
    assert.match(workflow, /runner: ubuntu-22\.04/);
    assert.match(workflow, /runner: ubuntu-22\.04-arm/);
    assert.match(workflow, /arch: x86_64/);
    assert.match(workflow, /arch: aarch64/);
    assert.match(workflow, new RegExp(`${binary}-linux-\\$\\{\\{ matrix\\.arch \\}\\}\\.tar\\.gz`));
  }
});

test("Windows and Linux tag artifacts receive pinned keyless provenance attestations", () => {
  const expectedAttestAction =
    "actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6 # v4.2.2";
  const cases = [
    {
      workflowName: "build-windows.yml",
      expectedSubject: "subject-path: release-artifacts/*.exe",
      expectedCount: "Expected exactly one Windows installer",
    },
    {
      workflowName: "build-linux.yml",
      expectedSubject: "release-artifacts/*.AppImage",
      expectedCount: "Expected four Linux GUI packages",
    },
    {
      workflowName: "build-cli.yml",
      expectedSubject: "subject-path: release-artifacts/*.tar.gz",
      expectedCount: "Expected two Linux CLI archives",
    },
    {
      workflowName: "build-tui.yml",
      expectedSubject: "subject-path: release-artifacts/*.tar.gz",
      expectedCount: "Expected two Linux TUI archives",
    },
  ];

  for (const { workflowName, expectedSubject, expectedCount } of cases) {
    const workflow = readFileSync(
      path.join(root, ".github", "workflows", workflowName),
      "utf8",
    ).replaceAll("\r\n", "\n");

    assert.match(workflow, /if: startsWith\(github\.ref, 'refs\/tags\/v'\)/);
    assert.match(
      workflow,
      /permissions:\n      contents: read\n      id-token: write\n      attestations: write/,
    );
    assert.ok(workflow.includes(expectedAttestAction));
    assert.ok(workflow.includes(expectedSubject));
    assert.ok(workflow.includes(expectedCount));
    assert.ok(workflow.includes("scripts/verify-github-attestation.sh"));
    assert.match(workflow, /GH_TOKEN: \$\{\{ github\.token \}\}/);
  }
});

test("attestation verification pins repository, workflow, tag ref, and runner class", () => {
  const verifier = readFileSync(
    path.join(root, "scripts", "verify-github-attestation.sh"),
    "utf8",
  );

  assert.match(verifier, /--repo "\$repository"/);
  assert.match(verifier, /--signer-workflow "\$repository\/\$signer_workflow"/);
  assert.match(verifier, /--source-ref "\$GITHUB_REF"/);
  assert.match(verifier, /--deny-self-hosted-runners/);
  assert.match(verifier, /for attempt in 1 2 3 4 5/);
});
