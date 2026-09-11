# 0.2.9 — Local course management and teaching cloud credentials

本轮为源码更新，不创建 Git tag、GitHub Release、TestFlight 或 AppGallery 构建，不替换现有商店版本。

## 使用方式 / Usage

各图形客户端的课程详情提供两种删除范围，并在执行前确认：

- **仅删除本次**：只移除所选上海日期、起止节次的那一次课，其他周和当天其他时段不受影响。
- **删除本学期整门课程**：移除该课程在本学期的全部排课。
- 在设置的个人账户／课程管理区域查看删除记录，逐条恢复。

Course details on Apple, Android, HarmonyOS and Tauri support removing either one
dated occurrence or all meetings of a course in the current semester. Settings
provides restoration. CLI offers `courses`, `course-delete`, `course-deletions`
and `course-restore`; TUI's `m` course manager supports date navigation, both
scopes and restoration. See the terminal clients' own READMEs for exact keys.

删除只修改本地视图，**不会退选学校课程、删除学校作业，也不会自动改动已独立导出的系统日历事件**。
应用保留原始课表，另存删除记录；刷新后仍会应用记录。恢复以最近获取的原始课表为准，
不能恢复学校已撤销、且最新课表中已经没有的排课。相互重叠的删除记录各自生效，恢复整课记录不会自动删除其他单次记录。

Edits are account- and semester-scoped. They are applied centrally to timetable
consumers, including free-period calculations and supported widgets/reminders.
They do not modify university data or previously exported calendar events. A
refresh retains the local edits; restoration uses the latest raw timetable.
Clients have separate local stores; edits are not synchronized between apps or
devices. Logging out or replacing a terminal/Tauri account scope does not carry
its old edits into a new credential scope.

## 教学云平台密码 / Teaching cloud password

- 学号仍使用同一字段；可在个人账户另填“教学云平台密码”，仅用于作业 DDL 认证。
- 未单独设置时使用教务密码。相同账号编辑时留空，保留已保存的独立密码；只有显式选择“改用教务密码”并保存才清除覆盖。
- 换学号不继承旧账号的云密码。密码框不回填已保存秘密；修改学期、提醒或主题不会暗中提交未保存的云密码草稿。
- 有效凭据改变（包括保存事务结果不确定）会失效旧作业缓存。旧请求的结果不能覆盖新凭据的数据。
- 原生客户端与 Tauri 沿用各系统已有安全凭据存储。CLI/TUI 沿用当前用户专属的权限保护文件，**不是钥匙串加密**；不提供明文密码命令行参数。

The optional password uses the same student ID and only changes UCloud assignment
authentication. Academic timetable/classroom requests keep using the academic
password. Blank same-account edits retain the override; an explicit saved reset
restores fallback. CLI adds `assignments --date` using the effective password.
TUI can configure its terminal credential record but still has no separate
assignment page; this update does not claim otherwise.

## Implementation contracts

- A course's optional `source_course_id` preserves upstream `jx0408id`. It is
  stable across recurring rows and classroom changes. If either side lacks it,
  deletion matching falls back to trimmed course name and teacher.
- A single-occurrence rule also matches the Shanghai date and start/end slots.
  Its corresponding week is removed from the effective recurring row, not from
  the raw snapshot. Other dates and semester identities remain intact.
- Atomic rule persistence must succeed before updated state is published. Rules
  are restored from raw data, not reconstructed from filtered rows.
- Tauri account gates and course-edit revisions reject stale notification/tray
  publications; even manual tray refreshes reapply local edits. Cloud result
  cache namespaces use an account-scoped credential revision, not a password
  fingerprint, and never expose secrets through settings responses or persisted
  preference files. The security follow-up is documented in
  [the security/quality record](security-quality-2026-09-11.md).
- Clearing local data removes deletion rules and both stored password values.

## Verification / 验证

All credentials and course data used for tests are fictional. No live university
authentication or university-side mutation was performed.

| Area | Local result |
| --- | --- |
| Apple | Strict Swift 6 macOS 178 and iOS 55 tests passed in the main batch. Final read-failure/bounds hardening was followed by macOS 63 and iOS 36 targeted tests, all passing. Credential fallback, deletion/restore, isolation, clear-data, widgets and reminders are covered. |
| Android | 238 JVM tests, debug app/test APK and lint pass; real emulator bilingual feature/storage flow (4 tests) and persistence/130% font checks (2 tests) pass. |
| HarmonyOS | 189 Hypium tests and ArkTS `assembleHap` pass. No connected device; real ASSET, IME or device visual checks were not run. |
| Tauri/React | 186 repository/domain tests and Vite build pass; Edge preview exercised single/whole deletion, refresh persistence, recovery and bilingual month/year entries. Preview uses demo data, not the actual Rust credential store. |
| Rust/terminal | Tauri backend 177 tests pass (3 live-service tests intentionally ignored); shared core 74, CLI 18 and TUI 40 tests pass, plus locked dependency checks. CLI help was invoked; TUI rendering and keyboard manager tests use Ratatui's test backend. |

Apple result copies are retained under ignored `release-artifacts/v0.2.9-course-management/apple/`:
`mac-final-63.xcresult`, `ios-final-targeted.xcresult` (36 tests), and `ios-baseline-55.xcresult`.
Android screenshots, logs and validation details are retained under ignored
`release-artifacts/v0.2.9-course-management/android/`.
Portable test logs, repository tests and the redacted secret scan (no leaks found)
are retained in the same artifact root. License verification also passes.

Windows/Ubuntu use the same Tauri source, but local macOS/Edge checks are not
Windows/Ubuntu native visual checks. No screenshots are added to README. No
successful build is described as a store upload or review approval.
