// DDL 的统一视觉语义：设置图例、查询列表、教学日历全天条目、月/年边框
// 与日期详情必须使用同一映射，避免同一来源在不同页面呈现为不同颜色。
import { AppTheme } from './AppTheme';
import {
  PublicDeadlineItem, PublicDeadlineKind, PublicDeadlineSource
} from '../net/CalendarDailyInfoClient';

export enum DeadlineVisualKind {
  assignment = 'assignment',
  schoolNotice = 'school_notice',
  competition = 'competition',
  conferenceOrJournal = 'conference_or_journal',
  summerCampOrPreAdmission = 'summer_camp_or_pre_admission',
  hackathon = 'hackathon',
  custom = 'custom'
}

export class DeadlineVisual {
  static kind(item: PublicDeadlineItem): DeadlineVisualKind {
    // 来源语义优先于事件类型，保证校内与自定义源不会被其兼容 kind 覆盖。
    if (item.source === PublicDeadlineSource.schoolNotice) {
      return DeadlineVisualKind.schoolNotice;
    }
    if (item.source === PublicDeadlineSource.custom || item.kind === PublicDeadlineKind.custom) {
      return DeadlineVisualKind.custom;
    }
    if (item.kind === PublicDeadlineKind.competition) {
      return DeadlineVisualKind.competition;
    }
    if (item.kind === PublicDeadlineKind.conference ||
      item.kind === PublicDeadlineKind.journalSpecialIssue) {
      return DeadlineVisualKind.conferenceOrJournal;
    }
    if (item.kind === PublicDeadlineKind.summerCamp ||
      item.kind === PublicDeadlineKind.preAdmission) {
      return DeadlineVisualKind.summerCampOrPreAdmission;
    }
    if (item.kind === PublicDeadlineKind.hackathon) {
      return DeadlineVisualKind.hackathon;
    }
    return DeadlineVisualKind.custom;
  }

  static colorForItem(item: PublicDeadlineItem): Resource {
    return DeadlineVisual.color(DeadlineVisual.kind(item));
  }

  static surfaceForItem(item: PublicDeadlineItem): Resource {
    return DeadlineVisual.surface(DeadlineVisual.kind(item));
  }

  static color(kind: DeadlineVisualKind): Resource {
    if (kind === DeadlineVisualKind.assignment) {
      return AppTheme.assignment();
    }
    if (kind === DeadlineVisualKind.schoolNotice) {
      return AppTheme.schoolNotice();
    }
    if (kind === DeadlineVisualKind.competition) {
      return AppTheme.competitionDeadline();
    }
    if (kind === DeadlineVisualKind.conferenceOrJournal) {
      return AppTheme.conferenceDeadline();
    }
    if (kind === DeadlineVisualKind.summerCampOrPreAdmission) {
      return AppTheme.summerCampDeadline();
    }
    if (kind === DeadlineVisualKind.hackathon) {
      return AppTheme.hackathonDeadline();
    }
    return AppTheme.customDeadline();
  }

  static surface(kind: DeadlineVisualKind): Resource {
    if (kind === DeadlineVisualKind.assignment) {
      return AppTheme.assignmentSurface();
    }
    if (kind === DeadlineVisualKind.schoolNotice) {
      return AppTheme.schoolNoticeSurface();
    }
    if (kind === DeadlineVisualKind.competition) {
      return AppTheme.competitionDeadlineSurface();
    }
    if (kind === DeadlineVisualKind.conferenceOrJournal) {
      return AppTheme.conferenceDeadlineSurface();
    }
    if (kind === DeadlineVisualKind.summerCampOrPreAdmission) {
      return AppTheme.summerCampDeadlineSurface();
    }
    if (kind === DeadlineVisualKind.hackathon) {
      return AppTheme.hackathonDeadlineSurface();
    }
    return AppTheme.customDeadlineSurface();
  }

  // 月/年格最多画两层。类型优先级严格保持：作业 > 校内 > 其它；
  // “其它”内部只为结果稳定而按开关排列，不提升其业务优先级。
  static borderKinds(assignmentCount: number,
    items: PublicDeadlineItem[]): DeadlineVisualKind[] {
    const present: Set<DeadlineVisualKind> = new Set<DeadlineVisualKind>();
    for (const item of items) {
      present.add(DeadlineVisual.kind(item));
    }
    const ordered: DeadlineVisualKind[] = [];
    if (assignmentCount > 0) {
      ordered.push(DeadlineVisualKind.assignment);
    }
    const candidates: DeadlineVisualKind[] = [
      DeadlineVisualKind.schoolNotice,
      DeadlineVisualKind.competition,
      DeadlineVisualKind.conferenceOrJournal,
      DeadlineVisualKind.summerCampOrPreAdmission,
      DeadlineVisualKind.hackathon,
      DeadlineVisualKind.custom
    ];
    for (const kind of candidates) {
      if (ordered.length >= 2) {
        break;
      }
      if (present.has(kind)) {
        ordered.push(kind);
      }
    }
    return ordered;
  }
}
