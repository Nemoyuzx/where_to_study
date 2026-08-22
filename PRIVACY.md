# Privacy Policy

Effective date: August 22, 2026

Where To Study is an independent, unofficial client for viewing BUPT schedules and empty classrooms. It is not operated by or affiliated with Beijing University of Posts and Telecommunications.

## Data handled by the app

- **School account credentials:** The account and password entered by the user are stored in the operating system's protected credential storage. They are sent to `jwglweixin.bupt.edu.cn` over HTTPS when the user asks the app to retrieve a schedule or classroom data. After valid credentials are saved, clients may also refresh the current day's classroom availability automatically when the app starts or returns to the foreground, and at approximately 07:00 China Standard Time where the platform permits a scheduled or background task. The Tauri settings API returns only whether a password is saved, never the saved password itself; leaving the password field empty preserves the existing protected value.
- **Schedule, classroom, and settings data:** Retrieved schedules, classroom availability, and app preferences are cached locally on the user's device so the app can work without repeating every request.
- **Holiday data:** Apple and Tauri clients retrieve the requested year's authoritative public-holiday and transfer-workday data over HTTPS from the pinned `holiday-calendar@1.3.3` dataset through unpkg. The Android client may read the device's OS-provided "Chinese holidays" calendar when calendar access has already been granted and supplements transfer-workdays from the same remote dataset. Remote requests contain only the `CN` region and year in the URL; credentials, schedules, and classroom data are never included. The upstream dataset is MIT-licensed and states that its Chinese data is compiled from annual State Council notices; attribution is recorded in `THIRD_PARTY_NOTICES.md`.
- **Weather and almanac data:** The app requests today's and tomorrow's weather for the selected campus district and base lunar-calendar information for the selected teaching-calendar date from UAPI over HTTPS. It may request the selected date's `宜`/`忌` text from the Timeless API over HTTPS. Weather requests contain only the public administrative division code for Haidian (Xitucheng) or Changping (Shahe); almanac requests contain only the selected date or its timestamp and the `Asia/Shanghai` timezone. These requests do not include school credentials, schedules, or classroom data. The corresponding settings switches are enabled by default and can be turned off individually.
- **Competition, summer-camp, and hackathon deadlines:** When at least one deadline category is enabled, the app downloads public event data from the Contest DDL GitHub Pages JSON endpoint over HTTPS and filters it locally to the selected date and enabled categories. If the primary endpoint is unavailable, supported clients may try the fixed backup endpoint at `http://101.201.29.29/api/contest-events`. The app also reads public BUPT competition notices and their extracted deadline nodes from `http://101.201.29.29/api/contest-notices`; item links point back to the corresponding HTTPS UCloud notice. These narrowly scoped cleartext requests are credential-free `GET` requests to that exact host, reject redirects, limit response size, and never include school credentials, cookies, tokens, schedules, classroom data, or assignment data. Each deadline category can be disabled separately in settings.
- **UCloud assignment deadlines:** When teaching-calendar date details request assignment deadlines, the app temporarily reads the school account and password already saved in protected credential storage and submits them only to `auth.bupt.edu.cn` over HTTPS for BUPT unified authentication. It exchanges the returned one-time ticket for an in-memory UCloud token, then retrieves the current course and assignment lists from `apiucloud.bupt.edu.cn`. The app does not read browser cookies or tokens, does not send the password to `ucloud.bupt.edu.cn` or `apiucloud.bupt.edu.cn`, and does not persist the authentication ticket, cookies, token, or assignment data. The full assignment result used for cross-date queries may be reused in memory for up to ten minutes; date results already displayed remain only in the current process. Both are invalidated when the account changes or local data is cleared.
- **Calendar export:** Calendar import or export occurs only after a user action and uses the operating system's calendar or file interfaces. Native clients request calendar access so they can find and update events previously created by Where To Study instead of creating duplicates. The Apple client searches events carrying the stable Where To Study marker within the teaching term plus a bounded one-year margin so user-moved app events can still be updated; the Android client queries marked app events through Calendar Provider to reconcile its own entries. Events without the app marker are not modified, and calendar data is never uploaded to the project.
- **Course notifications:** Clients create course-summary notifications locally only after the user explicitly enables them; platforms that expose notification authorization also require the applicable system permission. Notification content is derived from the locally cached schedule and is not uploaded to the project. Disabling notifications or clearing local data revokes future notification work. Account changes revoke old native scheduled summaries; desktop reminders continue only from the newly saved account settings. Previously delivered notifications are removed only where the operating system API used by that client supports removal and may otherwise need to be dismissed in the system notification center.

## Data not collected by the project

The project does not operate an application backend and does not collect analytics, advertising identifiers, diagnostics, location, contacts, or behavioral tracking data. The project maintainer cannot access credentials or locally cached app data.

The BUPT service, the holiday dataset's CDN, UAPI, Timeless, GitHub Pages, and the fixed Contest DDL and school-notice APIs may process ordinary network metadata such as IP address and request time under their own policies when the app connects to them.

## Retention and deletion

Credentials and cached data remain on the user's device until they are replaced, cleared from the app's settings, or removed by uninstalling the app. Clearing local data removes the app's saved credentials, schedule, classroom cache, local preferences, and app-managed course notification tasks; it does not delete records held by BUPT.

## Security

Security reports should follow [SECURITY.md](SECURITY.md). Do not include account credentials, tokens, personal schedules, or other sensitive data in a public issue.

## Questions

Privacy questions can be opened as a non-sensitive discussion or issue at <https://github.com/Nemoyuzx/where_to_study/issues>. Sensitive reports must use the private process documented in `SECURITY.md`.

Material changes to this policy will be published in this repository with an updated effective date.
