import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')
const harmony = 'native/harmony/entry/src/main/ets/'

test('Apple settings presentations and drafts survive replacement of the entire navigation branch', () => {
  const root = read('native/apple/Sources/Shared/RootView.swift')
  const session = read('native/apple/Sources/Shared/SettingsViewSession.swift')
  const settings = read('native/apple/Sources/Shared/SettingsView.swift')
  assert.match(root, /@State private var settingsSession = SettingsViewSession\(\)/)
  assert.match(root, /case \.settings: SettingsView\(session: settingsSession\)/)
  assert.match(root, /SettingsPresentationHost\(session: settingsSession\)[\s\S]{0,120}?\.environmentObject\(dailyInfo\)[\s\S]{0,80}?\.environmentObject\(calendarDeadlines\)/)
  assert.match(session, /let reminderDraft = SettingsPreClassReminderDraft\(\)/)
  assert.match(session, /let colorThemeDraft = SettingsColorThemeDraft\(\)/)
  assert.match(session, /InAppFullScreenPresentationHost\(presentation: session\.favoritePresentation\)/)
  assert.doesNotMatch(settings, /@State[^\n]*(?:reminderDraft|colorThemeDraft|showingAppSupport|showingFavoriteManagement)/)
})

test('Harmony privacy presentation has a stable root owner and preserves settings drafts', () => {
  const root = read(`${harmony}view/RootView.ets`)
  const settings = read(`${harmony}view/SettingsView.ets`)
  const session = read(`${harmony}view/SettingsSession.ets`)

  assert.match(root, /@Local settingsSession: SettingsSession = new SettingsSession\(\)/)
  assert.match(root, /if \(this\.settingsSession\.showingPrivacyPolicy\) \{\s*PrivacyPolicyView\(/)
  assert.ok((root.match(/session: this\.settingsSession/g) || []).length >= 3)
  assert.match(settings, /@Param session: SettingsSession = new SettingsSession\(\)/)
  assert.match(settings, /build\(\) \{\s*if \(this\.favoriteManagerOnly\) \{[\s\S]*?this\.settingsContent\(\)/)
  assert.doesNotMatch(settings, /@Local (?:showingPrivacyPolicy|customDeadlineURLDraft|editingPreClassReminders|preClassLeadDrafts)/)
  assert.match(session, /editCustomDeadlineURL\(value: string\): void \{[\s\S]*?this\.customDeadlineURLDirty = true/)
  assert.match(session, /syncCustomDeadlineURL\(savedURL: string\): void \{\s*if \(!this\.customDeadlineURLDirty\)/)
  assert.match(session, /savedCustomDeadlineURL\(submitted: string, saved: string\): void \{[\s\S]*?if \(this\.customDeadlineURLDraft !== submitted\) \{\s*return;/)
  assert.match(settings, /this\.session\.preClassLeadDrafts/)
  assert.match(settings, /'settings_custom_deadline_url', true/)
  assert.match(settings, /无法保存自定义日程地址';[\s\S]{0,100}?\}, !this\.model\.isSampleMode\(\)\)/)
})

test('Harmony fixed draft seed is DEBUG review-only and physical IME test is opt-in', () => {
  const launch = read(`${harmony}model/LaunchSupport.ets`)
  const ability = read(`${harmony}entryability/EntryAbility.ets`)
  const root = read(`${harmony}view/RootView.ets`)
  const session = read(`${harmony}view/SettingsSession.ets`)
  const device = read('native/harmony/entry/src/ohosTest/ets/test/SettingsPresentationDevice.test.ets')
  assert.match(launch, /return debugBuild && reviewDemo && requested/)
  assert.match(launch, /settingsPresentationSeedPending = SettingsPresentationSeedPolicy\.allows\(\s*DEBUG, AppLaunchConfiguration\.reviewDemo/)
  assert.match(launch, /consumeSettingsPresentationSeedForTesting\(\): boolean \{[\s\S]*?settingsPresentationSeedPending = false/)
  assert.match(launch, /hasPendingSettingsPresentationSeedForTesting\(\): boolean \{\s*return AppLaunchConfiguration\.settingsPresentationSeedPending/)
  assert.match(ability, /if \(!seededTest && this\.settingsTestOriginalOrientation === null\) \{[\s\S]*?this\.loadRootContent\(windowStage\);\s*return;/)
  assert.match(ability, /this\.settingsTestOriginalOrientation = mainWindow\.getPreferredOrientation\(\)/)
  assert.match(ability, /seededTest \? window\.Orientation\.AUTO_ROTATION/)
  assert.match(ability, /mainWindow\.setPreferredOrientation\(requested\)\.then\([\s\S]*?this\.loadRootContent\(windowStage\)/)
  assert.match(root, /if \(AppLaunchConfiguration\.consumeSettingsPresentationSeedForTesting\(\)\) \{\s*this\.settingsSession\.seedReviewPresentationDraftsOnce\(\)/)
  assert.match(session, /seedReviewPresentationDraftsOnce\(\): boolean \{[\s\S]*?if \(this\.presentationSeeded\) \{ return false; \}/)
  assert.match(session, /seedOnlyScene: boolean = false/)
  assert.match(session, /seedReviewPresentationDraftsOnce\(\): boolean \{[\s\S]*?this\.seedOnlyScene = true/)
  assert.match(read(`${harmony}view/SettingsView.ets`), /enableKeyboardOnFocus\(!\(this\.session\.seedOnlyScene && accessibilityID === 'settings_custom_deadline_url'\)\)/)
  assert.match(read(`${harmony}view/SettingsView.ets`), /TextInput\(\{ text: value, placeholder: '1–1440' \}\)[\s\S]{0,400}?enableKeyboardOnFocus\(!this\.session\.seedOnlyScene\)/)
  assert.match(read(`${harmony}view/ColorThemeSettingsCard.ets`), /@Param seedOnlyScene: boolean = false/)
  assert.match(read(`${harmony}view/ColorThemeSettingsCard.ets`), /TextInput\(\{ text: value, placeholder: '#RRGGBB' \}\)[\s\S]{0,500}?enableKeyboardOnFocus\(!this\.seedOnlyScene\)/)
  assert.equal((read(`${harmony}view/SettingsView.ets`).match(/ColorThemeSettingsCard\(\{ seedOnlyScene: this\.session\.seedOnlyScene \}\)/g) || []).length, 2)
  assert.match(device, /seeded_unsaved_drafts_survive_real_phone_sidebar_rotation_both_ways/)
  assert.match(device, /display\.getDefaultDisplaySync\(\)\.densityPixels/)
  assert.match(device, /getArguments\(\)\.parameters\['runSettingsKeyboardInput'\] === 'true'/)
  assert.match(device, /describe\('SettingsKeyboardInputDevice'/)
})

test('Harmony language segments have stable IDs and local writes are serialized without account refresh', () => {
  const settings = read(`${harmony}view/SettingsView.ets`)
  const model = read(`${harmony}model/AppModel.ets`)
  const device = read('native/harmony/entry/src/ohosTest/ets/test/SettingsPresentationDevice.test.ets')
  assert.match(settings, /\}, \(label: string, index: number\) => idPrefix \+ '\.' \+ index\.toString\(\)\)/)
  assert.match(settings, /Text\(idPrefix === 'settings\.language' \?\s*AppLanguageInfo\.label\(AppLanguageInfo\.all\[index\], this\.model\.resolvedLanguage\(\)\)/)
  assert.match(settings, /idPrefix === 'settings\.campus' \? this\.model\.text\(index === 0 \? '西土城' : '沙河'\)/)
  assert.match(settings, /Scroll\(this\.settingsScroller\)/)
  assert.match(settings, /selectLanguageAtCurrentPosition\(target: AppLanguage\): void \{[\s\S]*?new SettingsLanguageAnchor\(revision, this\.languageCardGlobalY, offset\)/)
  assert.match(settings, /preserveLanguageAnchorAfterLayout\(area: Area\): void \{[\s\S]*?this\.pendingLanguageAnchor = null;[\s\S]*?this\.settingsScroller\.scrollTo\(\{ xOffset: 0, yOffset: Math\.max\(0, offset \+ delta\), animation: false \}\)/)
  assert.match(settings, /aboutToDisappear\(\): void \{[\s\S]*?this\.pendingLanguageAnchor = null;[\s\S]*?clearTimeout\(this\.languageAnchorCleanupTimer\)/)
  assert.match(settings, /'settings\.language', true\)/)
  assert.match(model, /private languagePreferenceWrite: Promise<void> = Promise\.resolve\(\)/)
  assert.match(model, /setLanguageSetting\(value: AppLanguage\): Promise<void> \{[\s\S]*?if \(this\.isSampleMode\(\)\) \{ return; \}[\s\S]*?this\.languagePreferenceWrite\.catch\(\(\) => \{\}\)/)
  assert.match(model, /await this\.languagePreferenceWrite\.catch\(\(\) => \{\}\);\s*await this\.preferences\.remove\('appLanguage'\)/)
  assert.match(model, /languageGeneration === this\.languageClearGeneration &&\s*languageRevision === this\.languageSettingRevision && this\.localDataClearWork === null/)
  assert.doesNotMatch(model.slice(model.indexOf('async setLanguageSetting('), model.indexOf('async setWidgetShowsTeacher(')), /refreshSchedule|fetchSchedule|loadClassrooms|credentialsForRequest/)
  assert.match(device, /language_switch_keeps_the_visible_settings_anchor_in_place/)
  assert.match(read('native/harmony/entry/src/test/LanguageSettingTransaction.test.ets'), /rapid_zh_en_zh_writes_are_serial/)
  assert.match(read('native/harmony/entry/src/test/LanguageSettingTransaction.test.ets'), /clear_waits_for_pending_write_and_old_language_read_cannot_repopulate_it/)
})

test('Harmony favorites reject the 501st item before memory changes and render in pages', () => {
  const model = read(`${harmony}model/AppModel.ets`)
  const settings = read(`${harmony}view/SettingsView.ets`)
  const update = model.slice(model.indexOf('private async enqueueFavoriteDeadlineUpdate('), model.indexOf('deadlineItems('))

  assert.match(update, /next\.length >= FavoriteDeadlineCodec\.maximumFavorites[\s\S]*?setStatusMessage\(AppModel\.favoriteDeadlineLimitMessage, true\)[\s\S]*?return false;[\s\S]*?next\.push\(item\)/)
  assert.match(update, /favoriteDeadlinePreferenceWrite\.catch\(\(\) => \{\}\)[\s\S]*?await this\.preferences\.setString\('favoriteDeadlinesV1',[\s\S]*?this\.favoriteDeadlines = next;[\s\S]*?return true;/)
  assert.match(model, /async removeFavoriteDeadline\(item: PublicDeadlineItem\): Promise<void> \{\s*await this\.enqueueFavoriteDeadlineUpdate\(item, false\)/)
  assert.match(model, /favoriteDeadlineClearInProgress = true;[\s\S]*?favoriteDeadlineClearGeneration\+\+;[\s\S]*?clearLocalDataAfterFavoriteWrites\(\)/)
  assert.match(model, /private async clearLocalDataAfterFavoriteWrites\(\): Promise<void> \{[\s\S]*?await this\.favoriteDeadlinePreferenceWrite\.catch\(\(\) => \{\}\);\s*await this\.preferences\.remove\('favoriteDeadlinesV1'\);\s*this\.favoriteDeadlines = \[\]/)
  assert.match(settings, /favoriteDeadlines\.slice\(0, this\.requestedFavoriteCount\)/)
  assert.match(settings, /\.onScrollIndex\([\s\S]*?this\.appendFavoritePage\(end\)/)
  assert.match(settings, /this\.linkButton\('加载更多'/)
  assert.match(read('native/harmony/entry/src/test/FavoriteDeadlineLimit.test.ets'), /rejects_501_without_memory_or_disk_write/)
  assert.match(read('native/harmony/entry/src/test/FavoriteDeadlineLimit.test.ets'), /failed_storage_write_does_not_publish/)
  assert.match(read('native/harmony/entry/src/test/FavoriteDeadlineLimit.test.ets'), /two_rapid_additions_are_serial/)
  assert.match(read('native/harmony/entry/src/test/FavoriteDeadlineLimit.test.ets'), /two_rapid_management_cancels_are_idempotent/)
  assert.match(read('native/harmony/entry/src/test/FavoriteDeadlineLimit.test.ets'), /clear_removes_favorite_key_after_inflight_write/)
})

test('every Harmony favorite-add entry shows the specific limit reason in a toast', () => {
  const entries = [
    'view/QueryView.ets',
    'view/calendar/CalendarDailyInfoCards.ets',
    'view/calendar/MobileTeachingCalendarView.ets',
    'view/calendar/ExpandedTeachingCalendarView.ets',
  ]
  for (const entry of entries) {
    const source = read(`${harmony}${entry}`)
    const toggleAt = source.indexOf('toggleFavoriteDeadline(')
    const feedbackAt = source.lastIndexOf('const showFeedback =', toggleAt)
    const callback = source.slice(feedbackAt, toggleAt + 500)
    assert.ok(feedbackAt >= 0 && toggleAt > feedbackAt, entry)
    assert.match(callback, /owner\w+ !== this\./, entry)
    assert.match(callback, /uiContext\.getPromptAction\(\)\.showToast\(\{ message: this\.model\.text\(message\) \}\)/, entry)
    assert.match(callback, /if \(!changed\) \{\s*showFeedback\(AppModel\.favoriteDeadlineLimitMessage\)/, entry)
    assert.match(callback, /\}, \(\): void => \{\s*this\.model\.statusMessage = '无法保存收藏';\s*showFeedback\('无法保存收藏'\)/, entry)
  }
  assert.match(read(`${harmony}view/QueryView.ets`), /aboutToDisappear\(\): void \{\s*this\.saveCurrentTabScroll\(\);\s*this\.session\.detachView\(\);\s*this\.tabMotionGeneration\+\+/)
  assert.match(read(`${harmony}view/calendar/CalendarDailyInfoCards.ets`), /aboutToDisappear\(\): void \{\s*this\.favoriteFeedbackRevision\+\+/)
  assert.match(read(`${harmony}view/calendar/MobileTeachingCalendarView.ets`), /aboutToDisappear\(\): void \{[\s\S]*?this\.presentedDayMotionGeneration\+\+/)
  assert.match(read(`${harmony}view/calendar/ExpandedTeachingCalendarView.ets`), /aboutToDisappear\(\): void \{[\s\S]*?this\.yearPopupMotionRevision\+\+/)
  assert.match(read(`${harmony}common/AppLocalization.ets`), /收藏已达 500 条上限，请先取消部分收藏。/)
})

test('Tauri privacy dialog keeps keyboard listeners and initial focus stable across app data refreshes', () => {
  const app = read('src/App.jsx')
  const dialog = app.slice(app.indexOf('function PrivacyPolicyDialog('), app.indexOf('function hasTauriRuntime()'))

  assert.match(dialog, /const onCloseRef = useRef\(onClose\)/)
  assert.match(dialog, /onCloseRef\.current = onClose/)
  assert.match(dialog, /if \(event\.key === 'Escape'\) onCloseRef\.current\(\)/)
  assert.match(dialog, /closeButtonRef\.current\?\.focus\(\)/)
  assert.match(dialog, /window\.removeEventListener\('keydown', closeOnEscape\)/)
  assert.match(dialog, /\}, \[\]\)/)
  assert.doesNotMatch(dialog, /\}, \[onClose\]\)/)
  assert.match(app, /setPrivacyPolicyOpen\(false\)\s*privacyTriggerRef\.current\?\.focus\(\)/)
})
