# 代码安全性与逻辑性检查清单

> 分支：`security-logic-review`（基于 `main` @ 09d93af）
> 范围：Web 前端、Tauri/Rust 后端、Android 原生客户端、Apple 原生客户端、构建脚本与 CI。
> 方式：5 路并行深度审查（每路逐文件通读）+ 主线程逐条人工复核。共 36 项。
> 修复状态：未修复 / 已修复（附提交号）。

| # | 严重程度 | 类别 | 位置 | 问题描述 | 状态 |
|---|---------|------|------|---------|------|
| AND-1 | medium | security | AndroidManifest.xml + ScheduleClient.kt:124-137,232 | 无 networkSecurityConfig，信任用户安装的 CA，登录流量可被 MITM | 已修复 8161538 |
| AND-2 | low | security | SecureCredentialStore.kt:100-111 | 凭据加密密钥未绑定设备解锁（复核：绑定会破坏锁屏时的后台任务，补充注释说明） | 已复核(不采用) 0871bb6 |
| AND-3 | low | security | DailyCourseSummaryNotification.kt:538-567,576-585 | 课程摘要通知锁屏完全可见，泄露个人课表 | 已修复 eb2756b |
| AND-4 | low | security | HolidayClient.kt:79-87 | 节假日请求自动跟随重定向到任意主机 | 已修复 21bc463 |
| AND-5 | low | security | native/android/app/build.gradle.kts:45 | minSdk 24 无需 V1(JAR) 签名，保留削弱 APK 完整性校验 | 已修复 87dbe45 |
| AND-6 | low | logic | AppModels.kt:136-143 | 考试周判定硬编码取第 17/18 个周次（复核：接口无考试周字段，补充前提说明注释） | 已复核(注明前提) 478cb5b |
| AND-7 | low | robustness | ClassroomClient.kt:23-25 + ClassroomRepository.kt:127-128 | 两次取“今天”存在跨午夜竞态，刷新断言失败 | 已修复 916de8d |
| CI-1 | medium | security | scripts/native-android-signing-init.sh:49-68 | 签名口令经命令行传参且先以默认 umask 写盘再 chmod，有本地明文暴露窗口 | 已修复 9e74292 |
| CI-2 | low | logic | scripts/native-android-signing-init.sh:27-66 | 仅 keystore 存在而 properties 丢失时，写入新随机口令导致签名必失败 | 已修复 9e74292 |
| CI-3 | low | security | build-legacy-tauri-ios.yml:60,72-76 + build-native.yml:276,304-317 | CI 密钥口令走命令行传参；import -A 放开任意应用访问私钥 | 已修复(去除 -A) bab25b9 |
| CI-4 | low | logic | .github/workflows/build-windows.yml:96-103 | PowerShell 未校验 release label，tag 名可致路径穿越/构建失败 | 已修复 bf6ce89 |
| CI-5 | low | security | .gitignore vs native-android-signing-init.sh | 自定义 signing 文件名不受 .gitignore 覆盖，有误提交凭据风险 | 已修复 0746f56 |
| CI-6 | low | robustness | scripts/native-android-ui-test.sh:59 | 固定 /tmp 日志路径存在符号链接跟随风险 | 已修复 8f65062 |
| CI-7 | low | robustness | .github/workflows/build-native.yml:71 | runs-on 依赖可能尚不存在的 macos-26 runner 标签（复核：系有意固定 Xcode 26，不改） | 已复核(有意为之) |
| APL-1 | medium | robustness | ScheduleClient.swift:498-518 | 服务端返回倒置周次区间（如 8-3）时构造 Range 直接崩溃 | 已修复 b105c24 |
| APL-2 | medium | data-integrity | CalendarImporter.swift:144-199 | 同步计划会回写/删除用户在窗口外手动移动或复制的日历事件 | 已修复 67f5d3b |
| APL-3 | low | data-integrity | HolidayClient.swift:41-83 | 节假日数据源跟随任意重定向、无固定校验 | 已修复 4f2fa5f |
| APL-4 | low | logic | native/apple/project.yml:126 | iOS target bundle id 复制粘贴错误，与 macOS 相同且带 .macos 后缀 | 已修复 894e8d2 |
| APL-5 | low | logic | AppModel.swift:509-570 vs 744-761 | 清除本地数据后未取消每日教室刷新任务，每天 07:00 仍空跑报错 | 已修复 36618f9 |
| APL-6 | low | security | native/apple/project.yml:42-52 | macOS 发布未显式启用 Hardened Runtime | 已修复 894e8d2 |
| APL-7 | low | security | TodayCourseWidgetData.swift:100-117 | 预览构建把课表 JSON 写到用户主目录固定路径（越出沙箱容器） | 已修复 1505d4a |
| RST-1 | medium | security | src-tauri/src/credential_store.rs:200 | Windows 凭据持久级别复查（见修复说明：判定为误报，仅补充文档） | 已复核(误报) cc5328e |
| RST-2 | low | security | src-tauri/src/holidays.rs:408-421 | 节假日请求未配置重定向策略，可降级到 http 或跳转第三方主机 | 已修复 88a7455 |
| RST-3 | low | logic | src-tauri/src/schedule.rs:116-129 | classWeekDetails 提取到数字后完全忽略 classWeek 的区间/单双周语义 | 已修复 c513414 |
| RST-4 | low | logic | src-tauri/src/lib.rs:1751-1760,1816-1834 | 07:30 后启动应用会跳过当天 07:00/07:30 的后台任务 | 已修复 82d6c31 |
| RST-5 | low | robustness | schedule_store.rs:28-32 + classrooms_store.rs:31-35 | 读取本地缓存无大小上限，损坏文件会整文件读入内存 | 已修复 4d95114 |
| RST-6 | low | robustness | src-tauri/src/schedule.rs:155-173 | 对服务端 JSON 无深度限制的递归下降，深嵌套可致栈溢出 | 已修复 2e42228 |
| WEB-1 | medium | logic | App.jsx:551,1448 + planner-domain.js:64-69 | 本地“今天”与后端 Asia/Shanghai 今天不一致，非 UTC+8 用户空教室查询必然失败 | 已修复 910316a,734fdfd |
| WEB-2 | medium | robustness | App.jsx:1786-1790,1049-1053 | 清空日期输入产生 Invalid Date，日历渲染 NaN 且 React key 重复 | 已修复 734fdfd |
| WEB-3 | low | logic | planner-domain.js:368-379 | 考试周判定为位置启发式（第 17/18 个周次），与后端标注重复 | 已修复 910316a |
| WEB-4 | low | robustness | planner-domain.js:396 | getWeekState 假定 week_numbers 为数组，损坏缓存会白屏 | 已修复 910316a |
| WEB-5 | low | robustness | planner-domain.js:414-431 | slotsToRanges 无越界检查，slot 索引超表直接抛异常 | 已修复 910316a |
| WEB-6 | low | logic | App.jsx:325 | 课程全部结束后小组件“下一节课”回退显示当天第一节课 | 已修复 734fdfd |
| WEB-7 | low | data-integrity | App.jsx:1470-1494 | 清除本地数据失败时前端状态已被重置，界面与磁盘不一致 | 已修复 734fdfd |
| WEB-8 | low | robustness | App.jsx:1412-1422 | 单字符串 loading 状态在并发任务下误清空，按钮可重复触发请求 | 已修复 734fdfd |
| WEB-9 | low | security | vite.config.js (dev-only) | 浏览器预览路径无 CSP（仅 Tauri 生产包有） | 已修复 cc133eb |

## 修复说明

### Rust 后端（RST）
- **RST-1（复核判定为误报，未改行为）**：Microsoft 文档明确 CRED_PERSIST_LOCAL_MACHINE 仅对保存用户自己的登录会话可见（not visible to logon sessions for other users）；CRED_PERSIST_ENTERPRISE 反而会随域漫游凭据，扩大暴露面；CredReadW 也会按安全上下文校验读取权限。因此保留行业标准做法（keyring-rs、Git Credential Manager 同款），仅在代码中补充注释说明理由（cc5328e）。
- **RST-2（88a7455）**：新增 validate_holiday_redirect_target + holiday_redirect_policy，节假日请求只允许 https、同主机（unpkg.com）、无 userinfo 的重定向，并限制重定向次数；新增 1 个测试。cargo test 通过。
- **RST-3（c513414）**：parse_sjd_week_numbers 改为优先 expand_week_numbers(classWeek)（支持区间与单/双周后缀），其次结构化解析 classWeekDetails，最后才是纯数字兜底；新增 3 个测试。
- **RST-4（82d6c31）**：桌面调度器改为把每日任务完成日期持久化到 scheduler-state.json（原子写入，清数据时一并删除），启动时重载。修复 07:00/07:30 后才启动当天任务被跳过 的问题，同时避免每次重启重复通知。新增 2 个测试，cargo test 97→99 全绿，clippy 无告警。
- **RST-5（4d95114）**：课表与空教室缓存读取前用 fs::metadata().len() 限制 8 MiB（服务端响应上限 4 MiB + JSON 膨胀余量），超限直接报缓存过大；新增 2 个测试。
- **RST-6（2e42228）**：collect_sjd_course_items 增加 64 层递归深度上限；新增 1 个测试。

### Web 前端（WEB）
- **WEB-1（910316a + 734fdfd）**：新增 shanghaiDateString / msUntilNextShanghaiMidnight，todayDate 与后端 Asia/Shanghai 一致；跨午夜定时器改为对准上海午夜。修复非 UTC+8 设备空教室查询必失败问题。
- **WEB-2（734fdfd）**：日期输入改为 chooseCalendarDateFromInput，空值/非法日期拒绝并回填，避免 NaN 渲染与重复 key。
- **WEB-3（910316a）**：删除前端第 17/18 周位置启发式。后端 parse_sjd_courses 与缓存加载均已标注 exam_week_numbers，前端保留猜测会与权威数据叠加。
- **WEB-4（910316a）**：getWeekState 对 week_numbers 做 Array.isArray 守卫。
- **WEB-5（910316a）**：slotsToRanges 过滤越界 slot；busySlots 生成夹在 14 节表范围内。
- **WEB-6（734fdfd）**：小组件课程全部结束后不再回退显示当天第一节。
- **WEB-7（734fdfd）**：clearAllLocalData 仅在命令成功后重置界面状态，失败时恢复 savedCredentialState 并抛错。
- **WEB-8（734fdfd）**：loading 由单字符串改为 loadingTasks 数组派生，并发任务不再互相清空加载态。
- **WEB-9（cc133eb）**：vite.config.js 新增 serve-only 插件注入与生产对齐的 CSP meta，仅开发/预览生效。

### Android（AND）
- **AND-1（8161538）**：新增 network_security_config.xml（system-only 信任锚、禁明文），并在 manifest 引用。
- **AND-2（0871bb6）**：复核后不绑定设备解锁——07:00 教室刷新/07:30 课程摘要任务常在锁屏时运行，绑定会导致解密失败；密钥本身已 Keystore-only 且备份排除。已加注释说明取舍。
- **AND-3（eb2756b）**：课程摘要通知渠道锁屏可见性降为 VISIBILITY_PRIVATE。
- **AND-4（21bc463）**：HolidayClient 关闭自动重定向（fail-closed）。
- **AND-5（87dbe45）**：发布签名去掉 V1(JAR)，保留 V2 并启用 V3。
- **AND-6（478cb5b）**：考试周位置启发式（16 教学周+2 考试周的北邮学期结构）补充前提注释；教务接口无显式考试周字段。
- **AND-7（916de8d）**：新增 fetchAt(credentials, targetDate, now) 单时刻变体，targetDate/fetchedAt/当天校验共用同一 Date，消除跨午夜竞态。

### Apple（APL）
- **APL-1（b105c24）**：weekNumbers(from:) 对倒置区间取 min/max，并限制 1...53 防超大展开。
- **APL-2（67f5d3b）**：CalendarImporter.syncPlan 的匹配与去重仅限窗口内事件，用户移出/复制到窗口外的编辑不再被回写或删除。
- **APL-3（4f2fa5f）**：HolidayClient 默认会话改用拒绝一切重定向的 delegate（fail-closed）。
- **APL-4（894e8d2）**：iOS target bundle id 改为 com.nemoyu.wheretostudy.native.ios（需在 App Store Connect 注册对应 App ID 后重新配 profile）。
- **APL-5（36618f9）**：clearLocalData 同时取消 dailyClassroomRefreshTask。
- **APL-6（894e8d2，与 APL-4 同提交）**：macOS Release 配置启用 ENABLE_HARDENED_RUNTIME。
- **APL-7（1505d4a）**：预览构建的课表归档改写到应用自身 Application Support 容器，不再落到用户主目录固定路径。
- 验证：Xcode 工具链对 macOS 目标全量 swiftc -typecheck，与基线同为 1 个既有并发告警（AppModel.swift:197 主 actor 隔离，非本次引入）。

### 脚本与 CI（CI）
- **CI-1 + CI-2（9e74292）**：签名初始化脚本加 umask 077；keytool 口令改经环境变量（-storepass:env / -keypass:env）；keystore 与 properties 不一致时显式报错退出，不再生成无法使用的新口令。
- **CI-3（bab25b9）**：两处 iOS 签名工作流去掉 import -A，仅保留 codesign/productbuild/security 白名单。
- **CI-4（bf6ce89）**：Windows 打包步骤校验 release label（^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$）。
- **CI-5（0746f56）**：.gitignore 增加 native/android/keystore/；脚本在自定义路径位于仓库内时输出警告。
- **CI-6（8f65062）**：模拟器日志改写到 mktemp 私有文件。
- **CI-7**：复核判定为有意固定（工作流强制要求 Xcode 26/iOS 26 SDK），不改动。

## 验证汇总
- Rust：cargo test --lib 100/100 通过，clippy 0 告警。
- 前端：node --test 39/39 通过，vite build 成功；dev server 实测 CSP meta 注入。
- Swift：macOS 目标 swiftc -typecheck 通过（仅 1 个基线已有的并发告警）。
- Android：本机无 Android SDK，未做编译验证；改动均为小范围、语法经人工核对（Kotlin/XML/Gradle）。