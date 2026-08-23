# App Review Notes (English)

Submitted builds: iOS `0.2.3 (58)` and macOS `0.2.3 (58)`. Please review the latest build for each platform.

Where To Study is an independent, unofficial schedule and empty-classroom client for students of Beijing University of Posts and Telecommunications. It is not operated by or affiliated with the university. The app has no purchases, subscriptions, advertising, analytics, or tracking SDKs.

## Review without a school account

1. Open the app and select Settings.
2. Select Browse Built-in Sample Data.
3. Switch the interface among System, Simplified Chinese, and English. Static UI updates immediately; sample API content intentionally remains in its original language.
4. Review sample courses, classrooms, and the day/week/month/year calendar views. Collapse the day/week course summary, and use an all-day `+N` button to open the full assignment and school-notice list. The same items are marked in month cells and year-date details.
5. On iPhone, select a date in Month view and keep swiping upward. After the sheet reaches Details Raised, it continues scrolling through assignments, almanac, and event deadlines.
6. Select Import to System Calendar. The app displays a simulated result without requesting Calendar access or writing events.
7. In Settings, review the bilingual reference notice and the separate Competition and School Notice switches, then toggle the 07:30 course summary. Sample mode requests no Notification access.
8. On iOS or macOS, add the Today’s Courses widget from the system widget gallery. Sample mode writes only its fictional schedule to the App Group for this review path.
9. Return to Settings and select Return to Live Data to leave sample mode.

Sample mode uses only fictional courses, classrooms, and holiday data bundled with the app. It does not connect to the school service or access/modify Keychain credentials, live user caches, Calendar, or Notifications. On iOS and macOS it writes only the fictional schedule to the Widget App Group; leaving sample mode immediately restores the locally cached live schedule snapshot.

## Live-data path

Live mode requires the user’s own BUPT academic-system credentials. Credentials are stored only in Apple Keychain and are sent over HTTPS to `https://jwglweixin.bupt.edu.cn` when the user requests a schedule or same-day classroom availability. After valid credentials are saved, classroom availability may also refresh automatically on launch, on returning to the foreground, or at approximately 07:00 China Standard Time where the platform permits a scheduled task. The project maintainer does not operate that service and cannot access credentials, schedules, or classroom data. A failed request never falls back to another data source.

Calendar import and the optional 07:30 daily course summary are initiated by the user. All other features remain available if Calendar or Notification permission is denied.

Teaching-calendar date details also retrieve public weather, almanac, and event-deadline data. Competition data comes from Contest DDL. School competition notices are separately extracted by a server-side script from public pages on the university's internal website and exposed through a fixed public endpoint. No academic credentials are attached to those requests. The assignment card uses the university's HTTPS authentication and UCloud APIs only after the user has saved credentials. Authentication tickets, cookies, access tokens, and assignment data are not persisted to disk.

## macOS behavior

Closing the main window intentionally keeps the app in the menu bar. The main window can be reopened from the menu bar, and the Quit command exits the app completely. The “今日课程” (Today’s Courses) WidgetKit widget reads a local course snapshot shared by the main app through its App Group.

Privacy policy and source code:
https://github.com/Nemoyuzx/where_to_study

Reviewer contact name, phone number, and email are supplied in the private App Review Information fields in App Store Connect.
