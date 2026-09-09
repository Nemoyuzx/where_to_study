import { AppModel } from '../model/AppModel';
import { AppTheme } from '../common/AppTheme';
import { AppLanguage } from '../common/AppLocalization';
import { ColorThemes, ColorThemeSeed, ColorThemeSelection } from '../common/ColorThemes';

@ComponentV2
export struct ColorThemeSettingsCard {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Local primaryDraft: string = '#166B5D';
  @Local accentDraft: string = '#E2BC62';
  @Local selectedDateDraft: string = '#2563EB';
  @Local editingCustom: boolean = false;
  @Local saveFailed: boolean = false;
  @Local cardWidth: number = 300;

  aboutToAppear(): void {
    this.restoreDrafts();
  }

  @Monitor('model.colorTheme.selection', 'model.runtimeMode')
  onSelectionChanged(): void {
    this.restoreDrafts();
  }

  private restoreDrafts(): void {
    this.primaryDraft = this.model.colorTheme.selection.primary;
    this.accentDraft = this.model.colorTheme.selection.accent;
    this.selectedDateDraft = this.model.colorTheme.selection.selectedDate;
    this.editingCustom = false;
  }

  private text(chinese: string, english: string): string {
    return this.model.resolvedLanguage() === AppLanguage.english ? english : chinese;
  }

  private allPresets(): ColorThemeSeed[] {
    const selection: ColorThemeSelection = this.model.colorTheme.selection;
    return ColorThemes.presets.concat([new ColorThemeSeed('custom', '自定义', 'Custom',
      selection.primary, selection.accent, selection.selectedDate)]);
  }

  private draftSelection(): ColorThemeSelection | null {
    return ColorThemes.custom(this.primaryDraft, this.accentDraft, this.selectedDateDraft);
  }

  private preview(): ColorThemeSeed {
    return ColorThemes.seeds(this.editingCustom ?
      this.draftSelection() ?? this.model.colorTheme.selection : this.model.colorTheme.selection);
  }

  private previewPrimary(): ResourceColor {
    return this.editingCustom && this.draftSelection() !== null ?
      ColorThemes.fill(this.preview().primary) : AppTheme.primaryFill();
  }

  private previewSelectedDate(): ResourceColor {
    return this.editingCustom && this.draftSelection() !== null ?
      ColorThemes.fill(this.preview().selectedDate) : AppTheme.selectedDate();
  }

  private previewAccent(): ResourceColor {
    return this.editingCustom && this.draftSelection() !== null ? this.preview().accent : AppTheme.accent();
  }

  private previewLayer(role: string): ResourceColor {
    const selection: ColorThemeSelection = this.editingCustom ?
      this.draftSelection() ?? this.model.colorTheme.selection : this.model.colorTheme.selection;
    if (selection.preset === 'default') {
      if (role === 'background') { return AppTheme.background(); }
      if (role === 'surface') { return AppTheme.surface(); }
      if (role === 'elevated') { return AppTheme.elevated(); }
      if (role === 'surfaceVariant') { return AppTheme.surfaceVariant(); }
      if (role === 'border') { return AppTheme.border(); }
      if (role === 'secondaryText') { return AppTheme.secondaryText(); }
      return AppTheme.text();
    }
    const surfaces = ColorThemes.surfaces(selection, this.model.colorTheme.dark);
    if (role === 'background') { return surfaces.background; }
    if (role === 'surface') { return surfaces.surface; }
    if (role === 'elevated') { return surfaces.elevated; }
    if (role === 'surfaceVariant') { return surfaces.surfaceVariant; }
    if (role === 'border') { return surfaces.border; }
    if (role === 'secondaryText') { return surfaces.secondaryText; }
    return surfaces.text;
  }

  private choosePreset(id: string): void {
    this.saveFailed = false;
    this.model.selectColorTheme(id).then((saved: boolean) => { this.saveFailed = !saved; });
  }

  private applyCustom(): void {
    this.saveFailed = false;
    this.model.setCustomColorTheme(this.primaryDraft, this.accentDraft, this.selectedDateDraft)
      .then((saved: boolean) => { this.saveFailed = !saved; });
  }

  @Builder
  swatch(color: ResourceColor) {
    Circle()
      .width(17)
      .height(17)
      .fill(color)
      .stroke(AppTheme.border())
      .strokeWidth(0.5)
  }

  @Builder
  colorField(chinese: string, english: string, value: string, identifier: string,
    onChange: (value: string) => void) {
    Column({ space: 6 }) {
      Text(this.text(chinese, english))
        .fontSize(14)
        .fontColor(AppTheme.text())
      TextInput({ text: value, placeholder: '#RRGGBB' })
        .id(identifier)
        .fontSize(16)
        .fontFamily('monospace')
        .fontColor(AppTheme.text())
        .backgroundColor(this.model.colorTheme.selection.preset === 'default' ?
          AppTheme.background() : AppTheme.inputSurface())
        .borderRadius(8)
        .constraintSize({ minHeight: 44 })
        .width('100%')
        .accessibilityText(this.text(chinese, english) + ' HEX RGB')
        .onChange((next: string) => {
          this.editingCustom = true;
          this.saveFailed = false;
          onChange(next);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 12 }) {
      Text(this.text('颜色主题', 'Color Theme'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
      Text(this.text('立即应用，深浅色跟随系统。', 'Applies immediately. Light and dark follow the system.'))
        .fontSize(13)
        .fontColor(AppTheme.secondaryText())
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(this.allPresets(), (seed: ColorThemeSeed) => {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 8 }) {
              Row({ space: 6 }) {
                this.swatch(seed.primary)
                this.swatch(seed.accent)
                this.swatch(seed.selectedDate)
                if (this.model.colorTheme.selection.preset === seed.id) {
                  Text('✓').fontColor(AppTheme.selectionText()).fontWeight(FontWeight.Bold)
                }
              }
              Text(this.text(seed.nameZh, seed.nameEn))
                .fontSize(14)
                .fontColor(AppTheme.text())
                .textAlign(TextAlign.Start)
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
          .id('color_theme_' + seed.id)
          .width(this.cardWidth < 280 ? '100%' : '48%')
          .padding(10)
          .margin({ bottom: 8 })
          .borderRadius(8)
          .backgroundColor(this.model.colorTheme.selection.preset === seed.id ?
            AppTheme.selectionSurface() : AppTheme.background())
          .border({ width: this.model.colorTheme.selection.preset === seed.id ? 2 : 1,
            color: this.model.colorTheme.selection.preset === seed.id ? AppTheme.primary() : AppTheme.border() })
          .accessibilityText(this.text(seed.nameZh, seed.nameEn) +
            (this.model.colorTheme.selection.preset === seed.id ? this.text('，已选中', ', selected') : ''))
          .onClick(() => { this.choosePreset(seed.id); })
        }, (seed: ColorThemeSeed) => seed.id + seed.primary + seed.accent + seed.selectedDate)
      }
      .width('100%')

      this.colorField('主色', 'Primary', this.primaryDraft, 'color_theme_primary',
        (value: string) => { this.primaryDraft = value; })
      this.colorField('强调色', 'Accent', this.accentDraft, 'color_theme_accent',
        (value: string) => { this.accentDraft = value; })
      this.colorField('选中日期', 'Selected Date', this.selectedDateDraft, 'color_theme_selected_date',
        (value: string) => { this.selectedDateDraft = value; })
      if (this.editingCustom && this.draftSelection() === null) {
        Text(this.text('请输入六位十六进制 RGB（例如 #166B5D），当前已保存主题保持不变。',
          'Enter six hexadecimal RGB digits, for example #166B5D. Your saved theme is unchanged.'))
          .fontSize(13)
          .fontColor(AppTheme.danger())
          .id('color_theme_validation_error')
      }
      Text(this.text('实时预览', 'Live Preview'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.text())
      Column({ space: 8 }) {
        Text(this.text('页面背景', 'Page Canvas')).fontSize(12)
          .fontColor(this.previewLayer('secondaryText'))
        Column({ space: 8 }) {
          Text(this.text('课程卡片', 'Course Card')).fontSize(14)
            .fontWeight(FontWeight.Medium).fontColor(this.previewLayer('text'))
          Text(this.text('课程 · 08:00–09:35', 'Course · 08:00–09:35'))
            .fontSize(14)
            .fontColor('#FFFFFF')
            .padding(10)
            .width('100%')
            .borderRadius(8)
            .backgroundColor(this.previewPrimary())
          Row({ space: 12 }) {
            Text('12').fontSize(15).fontColor('#FFFFFF').padding(10).borderRadius(8)
              .backgroundColor(this.previewSelectedDate())
            this.swatch(this.previewAccent())
            Text(this.text('选中日期', 'Selected Date')).fontSize(13)
              .fontColor(this.previewLayer('text')).layoutWeight(1)
          }
          .padding(8)
          .borderRadius(8)
          .backgroundColor(this.previewLayer('surfaceVariant'))
          .border({ width: 1, color: this.previewLayer('border') })
          .width('100%')
          Text(this.text('日程详情浮层', 'Event Details Panel')).fontSize(12)
            .fontColor(this.previewLayer('secondaryText')).padding(8).width('100%')
            .backgroundColor(this.previewLayer('elevated')).borderRadius(6)
        }
        .padding(10)
        .borderRadius(8)
        .backgroundColor(this.previewLayer('surface'))
        .width('100%')
      }
      .padding(12)
      .borderRadius(8)
      .backgroundColor(this.previewLayer('background'))
      .width('100%')
      Button({ type: ButtonType.Normal }) {
        Text(this.text('应用自定义颜色', 'Apply Custom Colors'))
          .fontSize(15)
          .fontColor(this.draftSelection() !== null ? AppTheme.onPrimary() : AppTheme.disabledText())
          .textAlign(TextAlign.Center)
          .width('100%')
      }
        .id('color_theme_apply')
        .backgroundColor(this.draftSelection() !== null ? AppTheme.primaryFill() : AppTheme.surfaceVariant())
        .padding(12)
        .borderRadius(8)
        .width('100%')
        .enabled(this.draftSelection() !== null)
        .onClick(() => { this.applyCustom(); })
      Button({ type: ButtonType.Normal }) {
        Text(this.text('恢复默认', 'Restore Default'))
          .fontSize(15)
          .fontColor(AppTheme.selectionText())
          .textAlign(TextAlign.Center)
          .width('100%')
      }
        .id('color_theme_restore')
        .backgroundColor(AppTheme.selection())
        .padding(12)
        .borderRadius(8)
        .width('100%')
        .onClick(() => { this.choosePreset('default'); })
      if (this.saveFailed) {
        Text(this.text('无法保存颜色主题，请重试。', 'Unable to save the color theme. Please retry.'))
          .fontSize(13)
          .fontColor(AppTheme.danger())
      }
    }
    .padding(16)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.cardWidth = Number(newArea.width) - 32;
    })
  }
}
