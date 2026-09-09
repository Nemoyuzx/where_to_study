import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const root = fileURLToPath(new URL("../", import.meta.url));
const validator = path.join(
  root,
  "native/apple/scripts/validate-privacy-bundles.sh",
);
const manifests = {
  app: readFileSync(
    path.join(root, "native/apple/Resources/PrivacyInfo.xcprivacy"),
    "utf8",
  ),
  widget: readFileSync(
    path.join(root, "native/apple/Resources/Widget/PrivacyInfo.xcprivacy"),
    "utf8",
  ),
};

function fixture(t, platform) {
  const directory = mkdtempSync(path.join(tmpdir(), "wts-apple-privacy-test-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const app = path.join(directory, "Where To Study.app");
  const resources =
    platform === "macos" ? path.join(app, "Contents/Resources") : app;
  const widget =
    platform === "macos"
      ? path.join(
          app,
          "Contents/PlugIns/WhereToStudyWidget.appex/Contents/Resources",
        )
      : path.join(app, "PlugIns/WhereToStudyiOSWidget.appex");
  mkdirSync(resources, { recursive: true });
  mkdirSync(widget, { recursive: true });
  const files = {
    app: path.join(resources, "PrivacyInfo.xcprivacy"),
    widget: path.join(widget, "PrivacyInfo.xcprivacy"),
  };
  writeFileSync(files.app, manifests.app);
  writeFileSync(files.widget, manifests.widget);
  return { app, files };
}

for (const platform of ["ios", "macos"]) {
  test(
    `${platform} packaged app and extension declare their actual defaults access`,
    {
      skip:
        process.platform !== "darwin" &&
        "Apple plutil and PlistBuddy require macOS",
    },
    (t) => {
      const { app } = fixture(t, platform);
      const output = execFileSync("bash", [validator, platform, app], {
        encoding: "utf8",
      });
      assert.match(output, /Validated packaged/);
    },
  );

  for (const [name, mutation, expected] of [
    [
      "missing extension manifest",
      ({ files }) => rmSync(files.widget),
      /Missing packaged privacy manifest/,
    ],
    [
      "incorrect extension resource name",
      ({ files }) => {
        writeFileSync(
          path.join(path.dirname(files.widget), "WidgetPrivacyInfo.xcprivacy"),
          manifests.widget,
        );
        rmSync(files.widget);
      },
      /Missing packaged privacy manifest/,
    ],
    [
      "app missing App Group reason",
      ({ files }) => {
        writeFileSync(
          files.app,
          manifests.app.replace("<string>1C8F.1</string>", ""),
        );
      },
      /missing 1C8F\.1/,
    ],
    [
      "extension using only app-local reason",
      ({ files }) => {
        writeFileSync(
          files.widget,
          manifests.widget.replace("1C8F.1", "CA92.1"),
        );
      },
      /missing 1C8F\.1/,
    ],
    [
      "app missing local preferences reason",
      ({ files }) => {
        writeFileSync(
          files.app,
          manifests.app.replace("<string>CA92.1</string>", ""),
        );
      },
      /missing CA92\.1/,
    ],
    [
      "malformed extension manifest",
      ({ files }) => writeFileSync(files.widget, "invalid plist"),
      null,
    ],
  ]) {
    test(
      `${platform} refuses ${name} before distribution`,
      {
        skip:
          process.platform !== "darwin" &&
          "Apple plutil and PlistBuddy require macOS",
      },
      (t) => {
        const bundle = fixture(t, platform);
        mutation(bundle);
        const result = spawnSync("bash", [validator, platform, bundle.app], {
          encoding: "utf8",
        });
        assert.notEqual(result.status, 0, result.stdout);
        if (expected) assert.match(result.stderr, expected);
      },
    );
  }
}
