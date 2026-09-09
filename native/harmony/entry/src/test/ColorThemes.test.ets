import { describe, it, expect, afterEach } from '@ohos/hypium';
import { AppTheme } from '../main/ets/common/AppTheme';
import { ColorThemes, ColorThemeSeed, ColorThemeSelection, ColorThemeState } from '../main/ets/common/ColorThemes';
import { ColorThemePreferences, ColorThemeStore } from '../main/ets/store/ColorThemeStore';
import { WidgetSync } from '../main/ets/widget/WidgetSync';
import { AppModel } from '../main/ets/model/AppModel';
import { AppLaunchConfiguration } from '../main/ets/model/LaunchSupport';
import { AppSection } from '../main/ets/common/AppSection';
import { SampleData } from '../main/ets/model/SampleData';

class ThemeMemoryPreferences implements ColorThemePreferences {
  stored: string | null = null;
  writes: string[] = [];
  reads: number = 0;
  failNextWrite: boolean = false;

  async getString(key: string): Promise<string | null> {
    expect(key).assertEqual(ColorThemeStore.key);
    this.reads++;
    return this.stored;
  }

  async setString(key: string, value: string): Promise<void> {
    expect(key).assertEqual(ColorThemeStore.key);
    if (this.failNextWrite) {
      this.failNextWrite = false;
      throw new Error('storage unavailable');
    }
    this.writes.push(value);
    this.stored = value;
  }
}

function resourceEqual(actual: ResourceColor, expected: Resource): void {
  expect(JSON.stringify(actual)).assertEqual(JSON.stringify(expected));
}

export default function colorThemesTest() {
  describe('ColorThemesTest', () => {
    afterEach(() => {
      AppTheme.state.selection = new ColorThemeSelection();
      AppTheme.state.dark = false;
    });

    it('hex_accepts_only_six_rgb_digits_and_normalizes', 0, () => {
      expect(ColorThemes.normalizeHex('  aB09fF ')).assertEqual('#AB09FF');
      expect(ColorThemes.normalizeHex(' #00ff00 ')).assertEqual('#00FF00');
      for (const invalid of ['', '#FFF', '#12345678', '0x112233', '#12GG00', '#12345Z',
        '1234567', '##123456', 'rgb(0,0,0)', '#12 3456']) {
        expect(ColorThemes.normalizeHex(invalid)).assertNull();
      }
      expect(ColorThemes.custom('#000000', 'bad', '#FFFFFF')).assertNull();
    });

    it('presets_have_the_shared_identifiers_and_seeds', 0, () => {
      expect(ColorThemes.presets.map((seed: ColorThemeSeed) => seed.id).join(','))
        .assertEqual('default,ocean,violet,amber,rose');
      expect(ColorThemes.seeds(new ColorThemeSelection('ocean')).selectedDate).assertEqual('#7C3AED');
      expect(ColorThemes.seeds(new ColorThemeSelection('violet')).selectedDate).assertEqual('#00796B');
      expect(ColorThemes.seeds(new ColorThemeSelection('amber')).primary).assertEqual('#A65300');
      expect(ColorThemes.seeds(new ColorThemeSelection('rose')).accent).assertEqual('#8C6A35');
    });

    it('corrupt_persistence_recovers_each_field_independently', 0, () => {
      const decoded = ColorThemes.decode(
        '{"preset":"future-theme","primary":"bad","accent":"26a69a","selectedDate":42}');
      expect(decoded.preset).assertEqual('default');
      expect(decoded.primary).assertEqual('#166B5D');
      expect(decoded.accent).assertEqual('#26A69A');
      expect(decoded.selectedDate).assertEqual('#2563EB');
      for (const invalid of ['{', 'null', '[]', '42', '"custom"']) {
        expect(ColorThemes.encode(ColorThemes.decode(invalid)))
          .assertEqual(ColorThemes.encode(new ColorThemeSelection()));
      }
    });

    it('default_returns_exact_existing_system_color_resources', 0, () => {
      for (const dark of [false, true]) {
        AppTheme.state.dark = dark;
        resourceEqual(AppTheme.primary(), $r('app.color.app_primary'));
        resourceEqual(AppTheme.primaryFill(), $r('app.color.app_primary_fill'));
        resourceEqual(AppTheme.primaryDark(), $r('app.color.app_primary_dark'));
        resourceEqual(AppTheme.accent(), $r('app.color.app_accent'));
        resourceEqual(AppTheme.selectedDate(), $r('app.color.app_selected_date'));
        resourceEqual(AppTheme.selectedDateStrong(), $r('app.color.app_selected_date_strong'));
        resourceEqual(AppTheme.selectedDateSurface(), $r('app.color.app_selected_date_surface'));
        resourceEqual(AppTheme.selection(), $r('app.color.app_selection'));
        resourceEqual(AppTheme.selectionSurface(), $r('app.color.app_selection_surface'));
        resourceEqual(AppTheme.segmentedSelection(), $r('app.color.app_segmented_selection'));
      }
      expect(AppTheme.primaryWithAlpha(1, false)).assertEqual('#166B5D');
      expect(AppTheme.primaryWithAlpha(1, true)).assertEqual('#5AD2B8');
      expect(AppTheme.primaryWithAlpha(0, false)).assertEqual('#F2F2F7');
      expect(AppTheme.primaryWithAlpha(0, true)).assertEqual('#000000');
    });

    it('accessible_colors_meet_4_point_5_for_presets_and_extreme_custom_seeds', 0, () => {
      const colors: string[] = ['#FFFFFF', '#FFFFEE', '#000000', '#000001', '#777777', '#00FF00'];
      for (const seed of ColorThemes.presets) {
        colors.push(seed.primary, seed.accent, seed.selectedDate);
      }
      for (const seed of colors) {
        expect(ColorThemes.contrast(ColorThemes.fill(seed), '#FFFFFF') >= 4.5).assertTrue();
        expect(ColorThemes.contrast(ColorThemes.text(seed, true), '#282828') >= 4.5).assertTrue();
      }
      expect(ColorThemes.contrast('#000000', '#FFFFFF')).assertEqual(21);
      // 白色变暗的首个合格步是 54%：#757575；前一步 #7A7A7A 未达标。
      expect(ColorThemes.fill('#FFFFFF')).assertEqual('#757575');
      expect(ColorThemes.contrast('#7A7A7A', '#FFFFFF') < 4.5).assertTrue();
      expect(ColorThemes.fill('#1565C0')).assertEqual('#1565C0');
    });

    it('theme_changes_heatmap_and_selection_but_keeps_deadline_and_warning_semantics', 0, () => {
      const original: string = AppTheme.primaryWithAlpha(0.4, false);
      const key: string = AppTheme.colorKey();
      AppTheme.state.selection = new ColorThemeSelection('violet');
      expect(AppTheme.primaryWithAlpha(0.4, false) !== original).assertTrue();
      expect(AppTheme.colorKey() !== key).assertTrue();
      expect(AppTheme.selectedDate()).assertEqual('#00796B');
      expect(AppTheme.selectedDateSurface()).assertEqual('#1A00796B');
      AppTheme.state.dark = true;
      expect(AppTheme.selectedDateSurface()).assertEqual('#4000796B');
      resourceEqual(AppTheme.assignment(), $r('app.color.app_assignment'));
      resourceEqual(AppTheme.schoolNotice(), $r('app.color.app_school_notice'));
      resourceEqual(AppTheme.competitionDeadline(), $r('app.color.app_competition_deadline'));
      resourceEqual(AppTheme.conferenceDeadline(), $r('app.color.app_conference_deadline'));
      resourceEqual(AppTheme.summerCampDeadline(), $r('app.color.app_summer_camp_deadline'));
      resourceEqual(AppTheme.hackathonDeadline(), $r('app.color.app_hackathon_deadline'));
      resourceEqual(AppTheme.customDeadline(), $r('app.color.app_custom_deadline'));
      resourceEqual(AppTheme.nowIndicator(), $r('app.color.app_now_indicator'));
      resourceEqual(AppTheme.danger(), $r('app.color.app_danger'));
    });

    it('custom_colors_survive_presets_restore_default_and_relaunch', 0, async () => {
      const prefs = new ThemeMemoryPreferences();
      const state = new ColorThemeState();
      const store = new ColorThemeStore(state, prefs);
      const custom = ColorThemes.custom('123456', 'ABCDEF', '3399CC') as ColorThemeSelection;
      await store.save(custom, false);
      await store.save(state.selection.selecting('ocean'), false);
      await store.save(state.selection.selecting('default'), false);
      const nextState = new ColorThemeState();
      await new ColorThemeStore(nextState, prefs).restore(false);
      expect(nextState.selection.preset).assertEqual('default');
      expect(nextState.selection.primary).assertEqual('#123456');
      expect(nextState.selection.accent).assertEqual('#ABCDEF');
      expect(nextState.selection.selectedDate).assertEqual('#3399CC');
      expect(ColorThemes.encode(nextState.selection.selecting('custom')))
        .assertEqual(ColorThemes.encode(custom));
    });

    it('sample_choices_never_overwrite_real_preferences_and_exit_restores_real_theme', 0, async () => {
      const prefs = new ThemeMemoryPreferences();
      const state = new ColorThemeState();
      const store = new ColorThemeStore(state, prefs);
      await store.save(new ColorThemeSelection('ocean'), false);
      await store.save(new ColorThemeSelection('rose'), true);
      expect(state.selection.preset).assertEqual('rose');
      expect(prefs.writes.length).assertEqual(1);
      await store.restore(false);
      expect(state.selection.preset).assertEqual('ocean');
      const readCount: number = prefs.reads;
      await store.restore(true);
      expect(prefs.reads).assertEqual(readCount);
      expect(state.selection.preset).assertEqual('default');
    });

    it('rapid_saves_are_ordered_and_a_failed_save_does_not_poison_later_writes', 0, async () => {
      const prefs = new ThemeMemoryPreferences();
      const state = new ColorThemeState();
      const store = new ColorThemeStore(state, prefs);
      prefs.failNextWrite = true;
      const failed = store.save(new ColorThemeSelection('ocean'), false).catch(() => {});
      const latest = store.save(new ColorThemeSelection('rose'), false);
      expect(state.selection.preset).assertEqual('rose');
      await Promise.all([failed, latest]);
      expect(ColorThemes.decode(prefs.stored).preset).assertEqual('rose');
      const first = store.save(new ColorThemeSelection('amber'), false);
      const last = store.save(new ColorThemeSelection('violet'), false);
      await Promise.all([first, last]);
      expect(ColorThemes.decode(prefs.writes[prefs.writes.length - 2]).preset).assertEqual('amber');
      expect(ColorThemes.decode(prefs.stored).preset).assertEqual('violet');
    });

    it('widgets_share_selected_theme_even_for_empty_cards_and_default_uses_resources', 0, () => {
      const defaults = WidgetSync.themeBinding({}, new ColorThemeSelection(), false);
      expect(defaults['themeCustomized']).assertFalse();
      const themed = WidgetSync.themeBinding({}, new ColorThemeSelection('ocean'), false);
      expect(themed['themeCustomized']).assertTrue();
      expect(themed['themePrimaryFill']).assertEqual('#1565C0');
      expect(themed['themeAccent']).assertEqual('#26A69A');
      const dark = WidgetSync.themeBinding({}, new ColorThemeSelection('ocean'), true);
      expect(ColorThemes.contrast(dark['themePrimary'] as string, '#282828') >= 4.5).assertTrue();
    });

    it('model_theme_updates_preserve_calendar_data_and_navigation_and_reject_bad_edits', 0, async () => {
      const previousReview: boolean = AppLaunchConfiguration.reviewDemo;
      AppLaunchConfiguration.reviewDemo = true;
      const model: AppModel = AppLaunchConfiguration.makeModel();
      AppLaunchConfiguration.reviewDemo = previousReview;
      model.selectedSection = AppSection.calendar;
      const schedule = SampleData.schedule();
      model.schedule = schedule;
      expect(await model.setCustomColorTheme('123456', 'ABCDEF', '336699')).assertTrue();
      const valid: string = ColorThemes.encode(model.colorTheme.selection);
      expect(await model.setCustomColorTheme('#FFF', 'ABCDEF', '336699')).assertFalse();
      expect(ColorThemes.encode(model.colorTheme.selection)).assertEqual(valid);
      expect(await model.selectColorTheme('rose')).assertTrue();
      expect(model.colorTheme.selection.preset).assertEqual('rose');
      expect(model.colorTheme.selection.primary).assertEqual('#123456');
      expect(model.schedule === schedule).assertTrue();
      expect(model.selectedSection).assertEqual(AppSection.calendar);
      expect(model.isSampleMode()).assertTrue();
    });

    it('year_heatmap_labels_remain_readable_on_the_actual_blended_surface', 0, () => {
      for (const seed of ['#FFFFFF', '#000000', '#777777', '#00FF00', '#0000FF']) {
        AppTheme.state.selection = new ColorThemeSelection('custom', seed, '#ABCDEF', '#123456');
        for (const dark of [false, true]) {
          for (const opacity of [0, 0.3, 0.48, 0.7, 0.84]) {
            const background = AppTheme.primaryWithAlpha(opacity, dark);
            const foreground = AppTheme.textOnPrimaryBlend(opacity, dark) as string;
            expect(ColorThemes.contrast(foreground, background) >= 4.5).assertTrue();
          }
        }
      }
    });

    it('selected_date_outline_is_visible_for_extreme_seeds_without_changing_fill', 0, () => {
      for (const seed of ['#000000', '#000001', '#111111', '#FFFFFF', '#FFFFEE']) {
        AppTheme.state.selection = new ColorThemeSelection('custom', '#166B5D', '#E2BC62', seed);
        for (const dark of [false, true]) {
          AppTheme.state.dark = dark;
          const outline: string = AppTheme.selectedDateOutline() as string;
          expect(ColorThemes.contrast(outline, dark ? '#000000' : '#F2F2F7') >= 3).assertTrue();
          expect(ColorThemes.contrast(outline, dark ? '#1C1C1E' : '#FFFFFF') >= 3).assertTrue();
          expect(AppTheme.selectedDate()).assertEqual(ColorThemes.fill(seed));
        }
      }
    });

    it('selected_date_outline_only_fills_missing_nondefault_selection_borders', 0, () => {
      expect(AppTheme.shouldOutlineSelectedDate(true, false)).assertFalse();
      resourceEqual(AppTheme.selectedDateOutline(), $r('app.color.app_selected_date_strong'));
      AppTheme.state.selection = new ColorThemeSelection('custom', '#166B5D', '#E2BC62', '#000000');
      expect(AppTheme.shouldOutlineSelectedDate(true, false)).assertTrue();
      expect(AppTheme.shouldOutlineSelectedDate(false, false)).assertFalse();
      expect(AppTheme.shouldOutlineSelectedDate(true, true)).assertFalse();
      resourceEqual(AppTheme.nowIndicator(), $r('app.color.app_now_indicator'));
      resourceEqual(AppTheme.assignment(), $r('app.color.app_assignment'));
    });
  });
}
