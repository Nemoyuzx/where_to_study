// 月视图日期详情中的共享卡片：课程作业、黄历宜忌、统一 DDL。
// Mobile 与 Expanded 教学日历复用，确保顺序、来源声明和开关语义一致。
import { AppTheme } from '../../common/AppTheme';
import { DateParts, StrictDates } from '../../common/StrictDates';
import { AppModel } from '../../model/AppModel';
import {
  AlmanacInfo, AssignmentDeadlineItem, CalendarDailyInfoSources, PublicDeadlineItem,
  PublicDeadlineKindInfo, PublicDeadlineSnapshot, PublicDeadlineSource
} from '../../net/CalendarDailyInfoClient';
import { AppContext } from '../../store/AppContext';
import { AppLanguage } from '../../common/AppLocalization';

@ComponentV2
export struct CalendarDailyInfoCards {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param day: DateParts = StrictDates.todayParts();

  private date(): string {
    return StrictDates.formatDateParts(this.day);
  }

  private open(url: string): void {
    try {
      AppContext.get().openLink(url);
    } catch (e) {
      // 系统无法打开链接时保持在当前页。
    }
  }

  private assignments(): AssignmentDeadlineItem[] {
    return this.model.assignmentDeadlinesByDate.get(this.date()) ?? [];
  }

  private almanac(): AlmanacInfo | null {
    return this.model.almanacByDate.get(this.date()) ?? null;
  }

  private deadlineSnapshot(): PublicDeadlineSnapshot | null {
    return this.model.publicDeadlinesByDate.get(this.date()) ?? null;
  }

  private enabledDeadlineItems(): PublicDeadlineItem[] {
    return this.model.deadlineItems(this.date());
  }

  private showsContestSource(): boolean {
    return this.model.competitionDeadlinesEnabled || this.model.summerCampDeadlinesEnabled ||
      this.model.hackathonDeadlinesEnabled || this.enabledDeadlineItems().some(
        (item: PublicDeadlineItem): boolean => item.source === PublicDeadlineSource.contestDDL);
  }

  private showsSchoolSource(): boolean {
    return this.model.schoolContestNoticesEnabled || this.enabledDeadlineItems().some(
      (item: PublicDeadlineItem): boolean => item.source === PublicDeadlineSource.schoolNotice);
  }

  private customSources(): PublicDeadlineItem[] {
    const result: PublicDeadlineItem[] = [];
    const seen: Set<string> = new Set<string>();
    for (const item of this.enabledDeadlineItems()) {
      if (item.source !== PublicDeadlineSource.custom) {
        continue;
      }
      const key: string = (item.sourceName ?? '') + '\u001f' + (item.sourceHomepage ?? '');
      if (!seen.has(key)) {
        seen.add(key);
        result.push(item);
      }
    }
    return result;
  }

  build() {
    Column({ space: 10 }) {
      this.assignmentCard()
      if (this.model.almanacEnabled) {
        this.almanacCard()
      }
      if (this.model.hasEnabledPublicDeadlines()) {
        this.publicDeadlineCard()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  assignmentCard() {
    Column({ space: 8 }) {
      this.cardTitle('课程作业 DDL')
      if (this.assignments().length > 0) {
        ForEach(this.assignments(), (item: AssignmentDeadlineItem) => {
          this.assignmentRow(item)
        }, (item: AssignmentDeadlineItem) => 'assignment.' + item.id)
      } else {
        Text(this.model.text(this.model.assignmentUnavailableByDate.get(this.date()) ??
          '当天暂无课程作业 DDL'))
          .fontSize(13)
          .fontColor(this.model.loadingAssignmentDates.has(this.date()) ?
            AppTheme.secondaryText() :
            (this.model.assignmentUnavailableByDate.has(this.date()) ? AppTheme.danger() :
              AppTheme.secondaryText()))
          .lineHeight(18)
          .width('100%')
          .onClick(() => {
            if (!this.model.loadingAssignmentDates.has(this.date()) &&
              this.model.assignmentUnavailableByDate.has(this.date())) {
              this.model.retryAssignments(this.date());
            }
          })
      }
      this.sourceLink('第三方来源：北京邮电大学云课堂', CalendarDailyInfoSources.assignments)
    }
    .padding(14)
    .width('100%')
    .borderRadius(10)
    .border({ width: 1, color: AppTheme.border() })
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  assignmentRow(item: AssignmentDeadlineItem) {
    Row({ space: 9 }) {
      Column()
        .width(4)
        .height(38)
        .borderRadius(2)
        .backgroundColor(AppTheme.primaryFill())
      Column({ space: 2 }) {
        Text(item.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.text())
          .maxLines(2)
        Text(this.assignmentSubtitle(item))
          .fontSize(11)
          .fontColor(AppTheme.secondaryText())
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  private assignmentSubtitle(item: AssignmentDeadlineItem): string {
    const parts: string[] = [];
    if (item.courseName !== null) {
      parts.push(item.courseName as string);
    }
    parts.push(this.deadlineTime(item.deadline));
    if (item.status !== null) {
      // The assignment status comes from UCloud and remains verbatim, just
      // like course, assignment, contest, weather, and almanac content.
      parts.push(item.status as string);
    }
    return parts.join(' · ');
  }

  @Builder
  almanacCard() {
    Column({ space: 8 }) {
      this.cardTitle('黄历信息')
      if (this.almanac() !== null) {
        this.almanacContent(this.almanac() as AlmanacInfo)
      } else if (this.model.loadingAlmanacDates.has(this.date())) {
        Text(this.model.text('正在获取黄历与宜忌…'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
      } else if (this.model.almanacErrors.has(this.date())) {
        Text(this.model.text(this.model.almanacErrors.get(this.date()) ??
          '黄历获取失败。') + ' ' + this.model.text('点击重试'))
          .fontSize(13)
          .fontColor(AppTheme.danger())
          .lineHeight(18)
          .onClick(() => {
            this.model.loadCalendarDailyInfo(this.date(), true, false);
          })
      } else {
        Text(this.model.text('暂无黄历信息'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
      }
      Row({ space: 8 }) {
        Text(this.model.text('民俗信息仅供参考 · 第三方来源：UAPI'))
          .fontSize(11)
          .fontColor(AppTheme.secondaryText())
          .onClick(() => {
            this.open(CalendarDailyInfoSources.uapiOrigin);
          })
        Text(this.model.text('宜忌：Timeless API'))
          .fontSize(11)
          .fontColor(AppTheme.primary())
          .onClick(() => {
            this.open(CalendarDailyInfoSources.timelessOrigin);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .padding(14)
    .width('100%')
    .borderRadius(10)
    .border({ width: 1, color: AppTheme.border() })
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  almanacContent(info: AlmanacInfo) {
    Text(this.model.resolvedLanguage() === AppLanguage.english ?
      info.weekday + ' · Lunar ' + info.lunarDate + ' · Zodiac ' + info.zodiac :
      info.weekday + ' · 农历' + info.lunarDate + ' · ' + info.zodiac + '年')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.text())
      .width('100%')
    Text(this.model.resolvedLanguage() === AppLanguage.english ?
      'Ganzhi: ' + info.ganzhiYear + ' / ' + info.ganzhiMonth + ' / ' + info.ganzhiDay :
      '干支：' + info.ganzhiYear + '年 ' + info.ganzhiMonth + '月 ' + info.ganzhiDay + '日')
      .fontSize(12)
      .fontColor(AppTheme.secondaryText())
      .width('100%')
    if (this.festivalText(info).length > 0) {
      Text(this.festivalText(info))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
    }
    if (info.yi !== null) {
      this.almanacAdviceRow('宜', info.yi as string, AppTheme.primary())
    }
    if (info.ji !== null) {
      this.almanacAdviceRow('忌', info.ji as string, AppTheme.danger())
    }
  }

  private festivalText(info: AlmanacInfo): string {
    const values: string[] = [];
    if (info.solarTerm !== null) {
      values.push(info.solarTerm as string);
    }
    if (info.lunarFestival !== null) {
      values.push(info.lunarFestival as string);
    }
    if (info.solarFestival !== null) {
      values.push(info.solarFestival as string);
    }
    return values.join(' · ');
  }

  @Builder
  almanacAdviceRow(label: string, value: string, color: ResourceColor) {
    Row({ space: 8 }) {
      Text(this.model.text(label))
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(24)
        .height(24)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor(color)
      Text(value)
        .fontSize(12)
        .fontColor(AppTheme.text())
        .lineHeight(17)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  publicDeadlineCard() {
    Column({ space: 8 }) {
      this.cardTitle('DDL · 竞赛 / 夏令营 / 黑客松')
      if (this.enabledDeadlineItems().length > 0) {
        ForEach(this.enabledDeadlineItems(), (item: PublicDeadlineItem) => {
          this.publicDeadlineRow(item)
        }, (item: PublicDeadlineItem) => 'public-deadline.' + this.model.favoriteDeadlineKey(item))
        if (this.deadlineSnapshot() !== null &&
          (this.deadlineSnapshot() as PublicDeadlineSnapshot).usedBackup) {
          Text(this.model.text('本次使用备用 API'))
            .fontSize(11)
            .fontColor(AppTheme.secondaryText())
        }
      } else if (this.deadlineSnapshot() !== null) {
          Text(this.model.text('当天暂无已启用类别的 DDL'))
            .fontSize(13)
            .fontColor(AppTheme.secondaryText())
      } else if (this.model.loadingPublicDeadlineDates.has(this.date())) {
        Text(this.model.text('正在获取当天 DDL…'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
      } else if (this.model.publicDeadlineErrors.has(this.date())) {
        Text(this.model.text(this.model.publicDeadlineErrors.get(this.date()) ??
          'DDL 获取失败。') + ' ' + this.model.text('点击重试'))
          .fontSize(13)
          .fontColor(AppTheme.danger())
          .lineHeight(18)
          .onClick(() => {
            this.model.loadCalendarDailyInfo(this.date(), false, true);
          })
      } else {
        Text(this.model.text('暂无 DDL 信息'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
      }
      if (this.showsContestSource() || this.showsSchoolSource()) {
        Row({ space: 10 }) {
          if (this.showsContestSource()) {
            Text(this.model.text('第三方来源：Contest DDL'))
              .fontSize(11)
              .fontColor(AppTheme.primary())
              .onClick(() => {
                this.open(CalendarDailyInfoSources.deadlinePrimaryPage);
              })
            Text(this.model.text('备用 API'))
              .fontSize(11)
              .fontColor(AppTheme.secondaryText())
              .onClick(() => {
                this.open(CalendarDailyInfoSources.deadlineBackup);
              })
          }
          if (this.showsSchoolSource()) {
            Text(this.model.text('校内竞赛通知'))
              .fontSize(11)
              .fontColor(AppTheme.secondaryText())
              .onClick(() => {
                this.open(CalendarDailyInfoSources.schoolContestNotices);
              })
          }
        }
        .width('100%')
      }
      if (this.showsSchoolSource()) {
        Text(this.model.text('校内竞赛通知由脚本从学校内部网站公开通知页提取整理，仅供参考。'))
          .fontSize(11)
          .fontColor(AppTheme.secondaryText())
          .lineHeight(16)
          .width('100%')
      }
      ForEach(this.customSources(), (item: PublicDeadlineItem) => {
        Text(this.model.text('自定义日程来源：') +
          (item.sourceName ?? this.model.text('自定义日程')))
          .fontSize(11)
          .fontColor(item.sourceHomepage !== null ? AppTheme.primary() : AppTheme.secondaryText())
          .maxLines(2)
          .width('100%')
          .onClick(() => {
            if (item.sourceHomepage !== null) {
              this.open(item.sourceHomepage as string);
            }
          })
      }, (item: PublicDeadlineItem) => 'custom-source.' +
        (item.sourceName ?? '') + '.' + (item.sourceHomepage ?? ''))
    }
    .padding(14)
    .width('100%')
    .borderRadius(10)
    .border({ width: 1, color: AppTheme.border() })
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  publicDeadlineRow(item: PublicDeadlineItem) {
    Row({ space: 9 }) {
      Text(this.model.text(item.source === PublicDeadlineSource.schoolNotice ?
        '校内竞赛通知' : PublicDeadlineKindInfo.title(item.kind)))
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.onPrimary())
        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
        .borderRadius(9)
        .backgroundColor(AppTheme.primaryFill())
      Column({ space: 2 }) {
        Text(item.name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.text())
          .maxLines(2)
        Text(this.deadlineSubtitle(item))
          .fontSize(11)
          .fontColor(AppTheme.secondaryText())
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        if (item.officialURL !== null) {
          this.open(item.officialURL as string);
        }
      })
      Button() {
        SymbolGlyph(this.model.isFavoriteDeadline(item) ?
          $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
          .fontSize(18)
          .fontColor([this.model.isFavoriteDeadline(item) ? AppTheme.assignment() :
            AppTheme.secondaryText()])
      }
      .type(ButtonType.Normal)
      .width(34)
      .height(34)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.model.text(this.model.isFavoriteDeadline(item) ? '取消收藏' : '收藏'))
      .onClick(() => {
        this.model.toggleFavoriteDeadline(item).catch(() => {
          this.model.statusMessage = '无法保存收藏';
        });
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  private deadlineSubtitle(item: PublicDeadlineItem): string {
    const values: string[] = [this.deadlineTime(item.deadline)];
    if (item.organizer !== null) {
      values.push(item.organizer as string);
    }
    return values.join(' · ');
  }

  private deadlineTime(value: string): string {
    if (value.length >= 16 && (value.charAt(10) === 'T' || value.charAt(10) === ' ')) {
      return value.substring(11, 16);
    }
    return value;
  }

  @Builder
  cardTitle(title: string) {
    Text(this.model.text(title))
      .fontSize(15)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.text())
      .width('100%')
  }

  @Builder
  sourceLink(label: string, url: string) {
    Text(this.model.text(label))
      .fontSize(11)
      .fontColor(AppTheme.primary())
      .width('100%')
      .onClick(() => {
        this.open(url);
      })
  }
}
