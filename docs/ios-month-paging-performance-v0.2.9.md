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
