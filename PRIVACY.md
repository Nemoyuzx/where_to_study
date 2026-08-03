# Privacy Policy

Effective date: August 3, 2026

Where To Study is an independent, unofficial client for viewing BUPT schedules and empty classrooms. It is not operated by or affiliated with Beijing University of Posts and Telecommunications.

## Data handled by the app

- **School account credentials:** The account and password entered by the user are stored in the operating system's protected credential storage. They are sent only to `jwglweixin.bupt.edu.cn` over HTTPS when the user asks the app to retrieve a schedule or classroom data. The Tauri settings API returns only whether a password is saved, never the saved password itself; leaving the password field empty preserves the existing protected value.
- **Schedule, classroom, and settings data:** Retrieved schedules, classroom availability, and app preferences are cached locally on the user's device so the app can work without repeating every request.
- **Holiday data:** The app may retrieve public Chinese holiday data from the `bastengao/chinese-holidays-data` GitHub repository. Credentials and schedule data are never included in those requests.
- **Calendar export:** Calendar import or export occurs only after a user action and uses the operating system's calendar or file interfaces. Native clients request calendar access so they can find and update events previously created by Where To Study instead of creating duplicates; they inspect only the relevant teaching-term date range and stable app marker. Calendar data is not uploaded to the project.

## Data not collected by the project

The project does not operate an application backend and does not collect analytics, advertising identifiers, diagnostics, location, contacts, or behavioral tracking data. The project maintainer cannot access credentials or locally cached app data.

The BUPT service and GitHub may process ordinary network metadata such as IP address and request time under their own policies when the app connects to them.

## Retention and deletion

Credentials and cached data remain on the user's device until they are replaced, cleared from the app's settings, or removed by uninstalling the app. Clearing local data removes the app's saved credentials, schedule, classroom cache, and local preferences; it does not delete records held by BUPT.

## Security

Security reports should follow [SECURITY.md](SECURITY.md). Do not include account credentials, tokens, personal schedules, or other sensitive data in a public issue.

## Questions

Privacy questions can be opened as a non-sensitive discussion or issue at <https://github.com/Nemoyuzx/where_to_study/issues>. Sensitive reports must use the private process documented in `SECURITY.md`.

Material changes to this policy will be published in this repository with an updated effective date.
