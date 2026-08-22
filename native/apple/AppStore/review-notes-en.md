# App Review Notes (English)

Submitted builds: iOS and macOS `0.1.9 (49)`. Please review the latest build for each platform.

Where To Study is an independent, unofficial schedule and empty-classroom client for students of Beijing University of Posts and Telecommunications. It is not operated by or affiliated with the university. The app has no purchases, subscriptions, advertising, analytics, or tracking SDKs.

## Review without a school account

1. Open the app and select Settings.
2. Select “浏览内置示例数据” (Browse built-in sample data).
3. Review sample courses, classrooms, and the day/week/month/year calendar views.
4. Select “导入系统日历” (Import to System Calendar). The app displays a simulated result without requesting Calendar access or writing events.
5. In Settings, toggle the 07:30 course summary. The app displays a simulated state without requesting Notification access or scheduling a notification.
6. On macOS, add the “今日课程” (Today’s Courses) widget from the system widget gallery. Sample mode writes only its fictional schedule to the App Group for this review path.
7. Return to Settings and select “返回真实数据” (Return to live data) to leave sample mode.

Sample mode uses only fictional courses, classrooms, and holiday data bundled with the app. It does not connect to the school service or access/modify Keychain credentials, live user caches, Calendar, or Notifications. On iOS and macOS it writes only the fictional schedule to the Widget App Group; leaving sample mode immediately restores the locally cached live schedule snapshot.

## Live-data path

Live mode requires the user’s own BUPT academic-system credentials. Credentials are stored only in Apple Keychain and are sent over HTTPS to `https://jwglweixin.bupt.edu.cn` when the user requests a schedule or same-day classroom availability. After valid credentials are saved, classroom availability may also refresh automatically on launch, on returning to the foreground, or at approximately 07:00 China Standard Time where the platform permits a scheduled task. The project maintainer does not operate that service and cannot access credentials, schedules, or classroom data. A failed request never falls back to another data source.

Calendar import and the optional 07:30 daily course summary are initiated by the user. All other features remain available if Calendar or Notification permission is denied.

## macOS behavior

Closing the main window intentionally keeps the app in the menu bar. The main window can be reopened from the menu bar, and the Quit command exits the app completely. The “今日课程” (Today’s Courses) WidgetKit widget reads a local course snapshot shared by the main app through its App Group.

Privacy policy and source code:
https://github.com/Nemoyuzx/where_to_study

Reviewer contact name, phone number, and email are supplied in the private App Review Information fields in App Store Connect.
