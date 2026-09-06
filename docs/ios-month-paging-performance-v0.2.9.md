# iOS month paging follow-up / iOS 月视图翻页优化

## Scope / 范围

This follow-up targets the mobile Apple month grid. It does not change API endpoints, event filtering, deadline colors, the three vertical month positions, or the macOS desktop calendar layout.

本次针对 iPhone/iPad 使用的移动月历实现，不更改数据接口、事件筛选、DDL 颜色、纵向三档位置或 macOS 桌面日历布局。

## Implementation / 实现

- Keep three mounted pages in fixed rotating slots. The incoming month's native view survives recentering; distant jumps also use an incoming slot without duplicate IDs.
- Build immutable month projections on a worker actor. Cache up to six month projections and prepare two months ahead/behind as data only; the mounted view count stays at three. No network fetch is added to the swipe handler.
- Use reusable UIKit date controls and event labels instead of destroying and rebuilding a rich SwiftUI grid at each transition. Existing date/event colors, borders, text sizes, whole-cell taps and overflow actions remain intact.
- Wait for prepared data and a real layout acknowledgement before translating pages. Freeze page content and the previous day's details during movement; settle/recenter without animation, then update details. Queue/coalesce repeated directional requests and reject stale completions.
- Prepare a recycled, offscreen page one row at a time. If it becomes active before warmup finishes, synchronously finish the remaining cells before it is interactive. Delayed work is generation-checked and does not retain the view.
- Reject zero/invalid geometry before building border paths. CPU sampling exposed Core Graphics error logging from a negative inset rectangle; the invalid path is no longer constructed.
- Account/local-data ownership revisions and model/store identity are part of cache keys. Account changes, clearing local data and runtime-mode changes cancel page work and discard frozen content. Late data/layout results cannot reactivate an older transition.

月份页面使用三个固定循环槽位和可复用原生控件；翻页只移动已准备好的页面，离屏月份分行预热。数据整理在后台 actor 执行，网络获取仍沿用原有独立服务。保留原有视觉样式、日期整块点击、连续反向翻页、跨月选日和纵向折叠行为；切换账号或清空数据时立即废弃旧快照。

## Measurement method / 测量方法

Local Xcode, the same iPhone 16e simulator, Debug configuration, built-in review-demo data, and the same six-direction replay (`+1, -1, +1, +1, -1, -1`) were used. The baseline is source commit `06a26c3` with only the diagnostic overlay/replay added. The XCTest runner waits without querying accessibility between replayed transitions, and reads the diagnostic records afterward. Runs are serial, without another build or CPU sampler during timing.

The opt-in `MobileMonthFrameProbe` uses `CADisplayLink` and records relative callback times and intervals. It is compiled only under `DEBUG` and activated only by explicit UI-test launch arguments. It does not publish SwiftUI state every frame. The replay is likewise DEBUG-only.

These intervals measure simulator main-thread callback availability, **not physical-device FPS, render-server/GPU utilization, or a calibrated Core Animation hitch metric**. The first interval can begin before recording starts, so it must not be interpreted as a complete post-start frame. Report first-callback latency separately, and compare complete intervals inside the probe-relative windows. An improvement during movement does not imply zero remaining work after completion.

本地模拟器采样只反映主线程回调间隔，不能换算成实机帧率，也不能用来声称 GPU 利用率提高或所有设备绝不掉帧。首回调等待、动画前段及收尾开销分别记录，不将收尾卡顿从统计中隐藏。此次优化降低了主线程布局/创建成本，页面合成由系统正常完成，并非强行提高 GPU 占用。

### Recorded comparison / 本次记录

| Probe-relative metric, six page changes | Baseline | Row warmup | Final LRU recheck |
| --- | ---: | ---: | ---: |
| Mean wait to first callback after recording starts | 42.28 ms | 7.02 ms | 6.41 ms |
| Longest complete interval in 0–240 ms | 67.09 ms | 28.83 ms | 17.25 ms |
| Complete intervals over 25 ms in 0–240 ms | 4 | 1 | 0 |
| Longest complete interval after 240 ms | 16.74 ms | 25.36 ms | 33.35 ms |
| Complete intervals over 25 ms after 240 ms | 0 | 1 | 5 |

The initial reusable-native candidate exposed a new 66.97–90.16 ms completion-time stall. Invalid-geometry checks reduced it to 50.42–74.37 ms; fixed slots/data lookahead reduced it to 31.91–42.36 ms. Row-wise offscreen warmup removed that concentrated stall. The final recheck also makes prepared-page hits refresh LRU recency, so lookahead cannot evict a just-used month. Residual late intervals up to 33.35 ms remain in that replay: this is a measured improvement, not a zero-hitch guarantee. Intermediate runs are retained locally rather than selectively reporting only the best phase.

最后一次复测中，首回调平均等待由基线 42.28 ms 降到 6.41 ms，前段完整回调间隔最大 17.25 ms；此前原生复用方案引入的 67–90 ms 收尾停顿，经有效尺寸检查、固定槽位和分行预热逐步消除。不同复测仍记录到约 25–33 ms 的收尾间隔，不宣称完全零掉帧。

### Validation / 验证

- Final iOS unit suite: 292 executed, 1 opt-in live-network skip, 0 failures. Includes 16 paging-window tests, 6 background-projection tests, 9 native-grid reuse/geometry/warmup tests, and account-reset ownership assertions.
- Final warmup build: gesture reversals with exactly 42 active accessible date buttons, unobserved six-direction frame replay, and animated out-of-month date selection passed (3/3 UI tests).
- Four further UI flows passed on the warmup build: month expansion/year jumps, landscape expanded/raised stops and detail scrolling, centered week agendas with inline month details, and English controls. After the final cache-hit recency adjustment, all 292 unit tests and the unobserved replay passed again.
- Shared-code macOS suite: 276 executed, 1 opt-in live-network skip, 0 failures. No macOS upload is part of this iOS-only follow-up.
- Repository contracts: 142/142 passed.
- Final reversal screenshot was inspected: date alignment, selected-day/today marks, colored double borders, event/overflow labels and bottom navigation remain visible. The DEBUG-only probe label is not part of the shipping configuration.

Source-level review also checked queued requests, stale completion rejection, same-month day selection, month-end anchors, Reduce Motion, iOS 16 fallback, account/runtime cancellation and store-replacement isolation.

Ignored local evidence is kept under `release-artifacts/ios-month-paging-029/`; screenshots use built-in sample data and are not added to the README.

## 2026-09-06 follow-up: holiday status and year paging

The month transition now freezes its status-banner messages until horizontal motion settles. A holiday failure or unsupported-year message can therefore change the calendar viewport height only after the page finishes moving. Width changes still cancel/rebase the page window for rotation; status-only height changes do not. A deterministic DEBUG-only UI fixture crosses from November 2026 to a December grid containing 2027 and verifies two distinct intermediate x positions before the unavailable-holiday message appears.

Mobile year view now supports horizontal paging with the same direction and queue/coalescing rules as the month pager. Its implementation deliberately differs from the month grid:

- Project 365/366 real dates once on a worker actor instead of constructing twelve overlapping 42-day rich snapshots on the UI actor.
- Render each mini month on one reusable UIKit drawing surface, while preserving the existing course-density fill, selected color, two deadline borders, today dot, taps and VoiceOver date actions.
- Keep a five-year data-only LRU window, but mount at most the current and just-departed rendered year. The incoming year is prepared before motion; the old page remains available for a rapid reversal. This avoids laying out a third complete year when recentering.
- Keep one outer vertical ScrollView across page slots, so paging from September/October does not jump to January. Inactive pages expose no accessibility elements and dirty backing layers are drawn before they start moving; a valid content/size/theme backing is reused for A-B-A navigation.
- Owner and cache generations guard every asynchronous result and layout acknowledgement. Mode changes, rotation, Reduce Motion, account changes and local-data clearing cancel stale completions.
- Review/sample-mode full-year DDL and assignment fixtures are constructed on a utility task rather than in a main-actor loop. Production network clients retain their existing independent cache/service boundary.

The wide iPad layout also accepts horizontal year swipes, while retaining its existing single cached 365/366-day tree and in-place update. macOS gesture behavior is unchanged by this iOS-focused follow-up.

### Year pager simulator sample

The final DEBUG-only replay uses the same six directions as the month test and the same caveats above. Only complete callback intervals whose start and end are inside the probe-relative window are used; a first gap that starts before the probe is excluded. Two measurements are kept distinct: the functional full-fixture run includes locally generated DDL/assignment publication, while the renderer-only run suppresses that DEBUG fixture so it can isolate mounted-page and recentering work. Full-fixture UI behavior is covered separately by the functional tests below.

| Six year changes | Initial full-fixture prototype | Background-built full fixture | Final renderer-only |
| --- | ---: | ---: | ---: |
| Longest complete interval in 0–240 ms | 33.34 ms | 32.83 ms | 32.76 ms |
| Complete intervals over 25 ms in 0–240 ms | 3 | 4 | 1 |
| Longest complete interval in 70–240 ms | 16.70 ms | 32.83 ms | 17.30 ms |
| Complete intervals over 25 ms in 70–240 ms | 0 | 1 | 0 |
| Complete intervals over 25 ms after 240 ms | 15 | 4 | 6 |
| Longest complete interval after 240 ms | 66.67 ms | 50.27 ms | 34.67 ms |

This is a simulator main-thread callback sample, not physical-device FPS or a GPU-utilization claim. CPU sampling was used to locate synchronous Core Graphics text/border drawing, repeated trait-triggered raster generation, accessibility setup and sample-fixture generation. Year projection and fixture construction now run off the main thread; mini-month backing images are regenerated only for changed data, size or resolved palette. Intermediate regressions and profiling runs are retained locally rather than omitted from the audit. The final isolated run still contains roughly 33–35 ms completion/recentering intervals and is not presented as zero-hitch.

月视图在横移动画期间冻结“节假日数据暂不可用”等状态提示，提示只在动画完成后改变布局。手机年视图新增可反向、可排队的左右切年；全年数据在后台一次生成，月份使用原生绘制面和位图 backing 复用，并保留一个共享纵向滚动位置。最终隔离回放的实际横移动画区间最大完整间隔约 17.30 ms，收尾仍有约 34.67 ms 的模拟器间隔；这比原型的 66.67 ms 峰值低，但不等同于实机帧率保证。

### Follow-up validation / 后续验证

- iPhone unit suite: 325 executed, 1 opt-in network skip, 0 failures.
- Full-fixture iPhone UI: unavailable-holiday month animation, year paging with preserved vertical position, and year DDL-border/detail behavior passed in separate simulator runs.
- 13-inch iPad: expanded-layout horizontal year paging and reverse navigation passed.
- Shared macOS suite: 298 executed, 1 opt-in network skip, 0 failures. The macOS year gesture was deliberately not changed.
- Repository contracts: 142/142 passed. Unsigned generic-device Release compilation succeeded with strict concurrency and warnings-as-errors; the Release executable contains none of the DEBUG fixture/probe labels.
- The final full-fixture year screenshot was inspected for month alignment, selected/today marks, double DDL borders, vertical position and bottom navigation clearance. It remains an ignored local test artifact and is not added to the README.

## First year-date detail presentation / 年视图首次详情弹窗

A date tap previously updated the session date and sheet selection together, leaving the year window on its old date. The date observer then rebased the window with `disablesAnimations`, suppressing the sheet animation in the same update. Reopening the same date did not require that rebase. The tap now uses the existing year selection path to synchronize the window before presenting the sheet. No artificial delay or separate presentation controller is introduced, and Reduce Motion continues to use the existing policy.

Local Xcode regression evidence: before the fix, the first sheet's UIKit transition coordinator reported `isAnimated=false` and duration `0`. After the fix, first opening, reopening the same date and opening a different date each reported `isAnimated=true`, duration `0.4` seconds and an animated completed appearance. A DEBUG-only, opt-in child controller records these actual UIKit transition values; it is excluded from the release build. The child can receive a nonanimated initial `viewWillAppear` when attached, so that callback alone is not used as the sheet-animation assertion.

Validation: 24 year-window/native-grid unit tests and 3 iPhone UI flows passed, covering the three presentation cases, full DDL/date details and horizontal year paging with retained vertical position. The test log is retained locally as `release-artifacts/ios-calendar-paging-029/year-detail-presentation-regression.log`.

首次点日期时先同步年份窗口和选中日期，再打开详情，避免日历的无动画重置影响弹窗。首次、同日重开和更换日期的系统呈现动画均已通过本地 Xcode 验证。
