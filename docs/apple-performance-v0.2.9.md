# Apple loading and rendering audit — 0.2.9

## Scope / 范围

This follow-up covers both native iOS and macOS. It extends the earlier iOS-only build 80; Android, HarmonyOS and Tauri release artifacts are unchanged.

本轮依据代码、确定性并发测试和本机运行采样优化，不将“使用 async”或“增加 GPU 使用率”本身视为性能结论。

## Changes / 改动

- Production `AppModel` creation defers schedule/classroom file reads and JSON decoding. Initial network refresh waits for that restoration, avoiding redundant classroom fetches before today's cache arrives. Holiday-cache reads and refresh persistence also run outside the main actor. Existing semester validation and offline fallback logic remain in place.
- Generation checks protect delayed restoration and persistence against account changes, clearing data, switching demo mode and editing semester settings. Persistence invalidation serializes with an already-started write so cleared account data cannot be resurrected.
- Primary navigation has its own observable state on both Apple platforms. macOS menu, sidebar and keyboard commands no longer publish tab-only changes through the whole application data model.
- Query services are retained at the root on macOS as well as iOS. Live/demo weather, almanac, deadlines, shuttle and event-query stores are separate. Query tasks include runtime mode in their identity.
- Important-event deduplication, sorting, deadline parsing and search indexing run on a worker actor. Scrolling only increases the visible prefix; it does not repeat whole-feed parsing. Cached-search returns invalidate newer in-flight work as well, covering A → B → A selection.
- Calendar content subscriptions are stable and coalesce data batches. First binding invalidates a snapshot built before subscription, fixing the empty all-day header race reproduced by the iPhone favorite-flow UI test.
- Expanded calendars keep bounded month/timeline/formatter caches in the session, not a hidden view. Data, language, semester and source changes invalidate them even while the calendar is hidden. Mobile day/week layouts also reuse bounded projections.
- Course overlap placement is computed with the day projection. Minute ticks update the current-time overlay and today header instead of rebuilding every course block. Date formatters are reused per language/format. Cancelled initial-scroll tasks do not issue a late scroll; Reduce Motion disables view-transition animation.

## Evidence / 验证证据

- Local Xcode 26.6 (17F113), complete Swift concurrency checking and Swift warnings treated as errors.
- macOS complete unit run: **254 executed, 1 opt-in live-network skip, 0 failures**. Includes eight loading/persistence tests, four calendar cache/rendering tests and four event-query/navigation tests.
- Repository contracts: **142/142 passed**. The query-navigation contract now checks injected shared services instead of requiring the obsolete parameterless initializer.
- iPhone full run: **261 unit tests + 28 UI tests executed, 6 total conditional skips, 0 failures**. Xcode reported a result-bundle import error when two device runs shared its log directory; the full text log is retained, and final targeted device reruns use explicit, separate result-bundle paths.
- iPad final targeted run: **4/4 passed**, covering English calendar controls, aligned all-day events and whole-header selection, rotation/sidebar state retention, and all primary pages. The initial corner-tap failure was a test coordinate outside the clipped horizontal viewport; the test now scrolls the last column fully into view before asserting its corner is clickable. No header rendering workaround was retained.
- macOS 1,000-event microbenchmark: first worker index approximately **56 ms**; ten warm filters approximately **16 ms total**. This is a local CPU microbenchmark, not a device FPS claim.
- The 20-second final Debug macOS sample during live public-event searches and calendar switching shows `ImportantEventQueryWorker.query` on `com.apple.root.user-initiated-qos.cooperative`, not the main thread. It does not establish all-device hitch rates.
- Visual checks exercised live public queries, search/clear, day/week/month/year keyboard switching, forward/reverse month paging, whole-date header selection and the anchored year-detail panel. Sample courses were checked separately from live public data.
- A separate Animation Hitches trace did not complete normally and grew to approximately 16 GB. It was stopped and moved to Trash; it is **not** used as verification evidence. The smaller text sample is retained under ignored `release-artifacts/apple-performance-029/`.

## Limits / 边界

Keychain lookup and small preference/favorite restoration remain synchronous. Account clearing can wait for an already-running persistence operation. First-time calendar projections and SwiftUI layout still require main-thread work; this change reduces repeated work rather than claiming all UI work has moved off-thread. No custom Metal renderer or blanket rasterization was added, and no physical-iPhone FPS/GPU guarantee is made.

Apple distinguishes asynchronous scheduling from moving costly work off the main actor; UI updates still belong to that actor. See [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness) and [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance).

Final iOS test totals and signed-upload receipts are recorded in [the 0.2.9 release record](release-v0.2.9.md).
