# Android visual alignment — 2026-09-09

Scope: align Android's overall hierarchy, navigation and cards with the current
iOS 0.2.9 (91) implementation. This is a UI-only change, not a release.

## Presentation changes

- Shared compact-page title, card radius, control radius and spacing tokens.
- A lighter 56 dp navigation capsule with 20 dp side margins, 48 dp item touch
  targets and one translating selection background. Labels/icons do not scale.
- Selection animation survives content layout; RTL uses physical child coordinates.
  At large font sizes, actual localized glyph height determines whether captions
  fit. Icon-only navigation retains centered icons and full accessibility labels.
- Reselecting Settings preserves its current page and inputs. Other destinations
  keep their existing refresh/cache-check behavior on reselection.
- Settings cards have semantic section icons, restrained secondary actions and
  adaptive two-column theme presets. Language stays above privacy/local data.
- Planner controls share card edges; period titles and monospaced times preserve
  their styling after localization. Buttons grow with content when necessary.
- Shuttle departures use an adaptive grid. Event filters share one card, and
  deadline colors emphasize dates without replacing the existing semantic palette.
  Query mode initialization uses the live selection even when a switch arrives
  before first layout; only the active mode/tab remains bold.

Unchanged: Apple sources, Android's 0.92 app font multiplier, calendar gestures,
network clients/request timing/caches, credentials, privacy content, reminders,
widgets, DDL colors and user-selected theme seeds. Native iOS glass rendering is
not emulated; Android retains native touch/accessibility behavior.

## Verification and evidence

Use the added `NavigationVisualPolishUiTest`, `QueryCardsVisualUiTest` and
`SettingsVisualLayoutUiTest`, plus the existing navigation/theme/reminder tests.
The navigation test samples intermediate frames (not just the endpoint), forces
layout during animation and verifies RTL geometry. Card tests check nonzero
content height, minimum touch targets, localization, footer clearance and theme
changes without losing unsaved fields.

Local evidence lives under the ignored `release-artifacts/android-ios-polish/`:

- `reference-ios/REFERENCE.md`: current iOS source constants and simulator captures.
- `before/visual-polish/`: preserved Android baseline captures.
- `after/visual-polish/`: updated real emulator captures, including events/themes.
- `build-final.log`, `repository-tests.log`, `*-tests.log`, `navigation-frames.log`.

All captures use isolated UI-test/review-demo data, not a real account. An isolated
Android API 36.1 emulator was used; the user's installed app and existing AVDs were
not overwritten. iOS reference captures also use a dedicated simulator. Screenshots
are not added to README or the Git index.

Standard local verification command:

```sh
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
  ./native/android/gradlew --project-dir native/android \
  assembleDebug assembleDebugAndroidTest testDebugUnitTest lintDebug
npm test
```

No version numbers, signing configuration, remote refs, release assets or store
submissions are changed by this work. The resulting local debug APK is not a
replacement for a signed store release.

## Results and limits

- Android build, 224 JVM unit tests and lint complete successfully (lint retains
  existing warnings; this is not a claim of zero warnings).
- All 181 repository tests pass.
- The 12-test phone regression batch passes, including primary-page navigation,
  language round trip, settings/theme drafts and reminder-time editing. The final
  navigation rerun also checks that only the selected label remains bold.
- The final eight-test cards/navigation batch passes, including real intermediate
  animation frames, RTL, theme drafts and nonzero shuttle departure heights.
- The 130% font batch passes all five navigation/settings/query tests in dark
  mode; the 200% font navigation check passes. Card tests exercise both Chinese
  and English. 200% is not a claim that every full page has been exhaustively tested.
- Chinese/light and English/dark phone captures were visually reviewed, including
  Planner, calendar, shuttle, events, Settings and theme presets. Wide 1920×1200
  (240 dpi) captures were also reviewed for sidebar and card layout.
- **Known pre-existing wide-calendar test failure:** the long primary-page smoke
  test reaches a month-sheet assertion requiring a 69 px, single-week viewport,
  but the wide layout shows its full 414 px grid. The preserved original APK and
  original test APK reproduce the exact same failure under the same configuration
  (`baseline-tablet-regression.log` versus `tablet-ui-tests.log`). This turn does
  not change calendar gestures or claim the entire tablet regression suite passes.

These are emulator/source-based checks, not testing on the user's physical
Android handset or an assertion of pixel-identical native iOS rendering.
