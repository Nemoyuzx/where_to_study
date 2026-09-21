import {
  FavoriteDeadlineCodec, PublicDeadlineItem, PublicDeadlineKind, PublicDeadlineKindInfo,
  PublicDeadlineSource
} from '../net/CalendarDailyInfoClient';

export enum QueryPageTab {
  shuttle = 'shuttle',
  events = 'events',
  grades = 'grades',
  exams = 'exams',
  assignments = 'assignments'
}

export enum ImportantEventFilter {
  all = 'all',
  competition = 'competition',
  conference = 'conference',
  journalSpecialIssue = 'journal_special_issue',
  summerCamp = 'summer_camp',
  hackathon = 'hackathon',
  preAdmission = 'pre_admission',
  schoolNotice = 'school_notice'
}

export class QueryPageContract {
  static readonly tabs: QueryPageTab[] = [QueryPageTab.shuttle, QueryPageTab.events, QueryPageTab.grades,
    QueryPageTab.exams, QueryPageTab.assignments];
  static readonly filters: ImportantEventFilter[] = [
    ImportantEventFilter.all,
    ImportantEventFilter.competition,
    ImportantEventFilter.conference,
    ImportantEventFilter.journalSpecialIssue,
    ImportantEventFilter.summerCamp,
    ImportantEventFilter.hackathon,
    ImportantEventFilter.preAdmission,
    ImportantEventFilter.schoolNotice
  ];

  static tabTitle(tab: QueryPageTab): string {
    if (tab === QueryPageTab.exams) { return '考试查询'; }
    if (tab === QueryPageTab.assignments) { return '作业 DDL'; }
    return tab === QueryPageTab.shuttle ? '班车查询' : tab === QueryPageTab.grades ? '成绩查询' : '重要事件';
  }

  static compactTabTitle(tab: QueryPageTab): string {
    if (tab === QueryPageTab.shuttle) { return '班车'; }
    if (tab === QueryPageTab.events) { return '事件'; }
    if (tab === QueryPageTab.grades) { return '成绩'; }
    return tab === QueryPageTab.exams ? '考试' : '作业';
  }

  // 原生 Symbol 与一级导航 AppSectionInfo 保持同一图标体系。
  static tabSymbol(tab: QueryPageTab): Resource {
    if (tab === QueryPageTab.shuttle) { return $r('sys.symbol.bus_fill'); }
    if (tab === QueryPageTab.events) { return $r('sys.symbol.calendar'); }
    if (tab === QueryPageTab.grades) { return $r('sys.symbol.graduationcap'); }
    return tab === QueryPageTab.exams ? $r('sys.symbol.doc_text') : $r('sys.symbol.list_bullet');
  }

  // 使用实际文本测量宽度（包含系统字体缩放），五段始终保持等宽单行。
  // pickerWidth 包含两侧 3vp 内边距；标签两侧各 6vp，图标为 20vp + 4vp 间距。
  static iconOnlyTabs(pickerWidth: number, maximumLabelWidth: number, includesIcons: boolean): boolean {
    if (!Number.isFinite(pickerWidth) || pickerWidth <= 0 ||
      !Number.isFinite(maximumLabelWidth) || maximumLabelWidth <= 0) {
      return true;
    }
    const segmentWidth: number = Math.max(0, pickerWidth - 6) / QueryPageContract.tabs.length;
    return Math.ceil(maximumLabelWidth) + 12 + (includesIcons ? 24 : 0) > segmentWidth;
  }

  static filterTitle(filter: ImportantEventFilter): string {
    if (filter === ImportantEventFilter.all) {
      return '全部';
    }
    if (filter === ImportantEventFilter.schoolNotice) {
      return '校内竞赛';
    }
    const kind: PublicDeadlineKind | null = PublicDeadlineKindInfo.fromWireValue(filter);
    return kind === null ? '全部' : PublicDeadlineKindInfo.title(kind);
  }

  static tabAccessibilityID(tab: QueryPageTab): string {
    return 'query.tab.' + tab;
  }
}

export class ImportantEventQueryLogic {
  static readonly pageSize: number = 20;
  static readonly preloadThreshold: number = 4;

  static initialRequestedCount(): number {
    return ImportantEventQueryLogic.pageSize;
  }

  static visibleCount(totalCount: number, requestedCount: number): number {
    return Math.min(Math.max(0, Math.trunc(requestedCount)),
      Math.max(0, Math.trunc(totalCount)));
  }

  static visiblePage(items: PublicDeadlineItem[], requestedCount: number): PublicDeadlineItem[] {
    return items.slice(0, ImportantEventQueryLogic.visibleCount(items.length, requestedCount));
  }

  static shouldAppend(endingIndex: number, visibleCount: number, totalCount: number): boolean {
    if (visibleCount <= 0 || visibleCount >= totalCount) {
      return false;
    }
    return endingIndex >= Math.max(0,
      visibleCount - ImportantEventQueryLogic.preloadThreshold);
  }

  static nextRequestedCount(currentCount: number, totalCount: number): number {
    return Math.min(Math.max(0, Math.trunc(totalCount)),
      Math.max(ImportantEventQueryLogic.pageSize,
        Math.max(0, Math.trunc(currentCount)) + ImportantEventQueryLogic.pageSize));
  }

  static mergeCatalog(remote: PublicDeadlineItem[], favorites: PublicDeadlineItem[]):
    PublicDeadlineItem[] {
    const result: PublicDeadlineItem[] = [];
    const seen: Set<string> = new Set<string>();
    for (const group of [remote, favorites]) {
      for (const item of group) {
        // 查询页只展示内置公开活动与校内竞赛；作业并非 PublicDeadlineItem，
        // 自定义来源也不属于本页的两个固定接口。
        if (item.source === PublicDeadlineSource.custom) {
          continue;
        }
        const key: string = FavoriteDeadlineCodec.key(item);
        if (!seen.has(key)) {
          seen.add(key);
          result.push(item);
        }
      }
    }
    return ImportantEventQueryLogic.sorted(result);
  }

  static filter(items: PublicDeadlineItem[], query: string,
    typeFilter: ImportantEventFilter, category: string = '',
    showEnded: boolean = false, nowMs: number = Date.now()): PublicDeadlineItem[] {
    const normalizedQuery: string = query.trim().toLowerCase();
    const normalizedCategory: string = category.trim();
    const filtered: PublicDeadlineItem[] = [];
    for (const item of items) {
      if (!ImportantEventQueryLogic.matchesType(item, typeFilter) ||
        (normalizedCategory.length > 0 && item.categories.indexOf(normalizedCategory) < 0) ||
        (!showEnded && ImportantEventQueryLogic.isEnded(item, nowMs))) {
        continue;
      }
      if (normalizedQuery.length > 0) {
        const haystack: string = (item.name + '\n' + (item.organizer ?? '') + '\n' +
          PublicDeadlineKindInfo.title(item.kind) + '\n' + item.deadline + '\n' +
          (item.source === PublicDeadlineSource.schoolNotice ? '校内竞赛通知' : '公开活动') + '\n' +
          item.categories.join('\n') + '\n' + item.tags.join('\n') + '\n' +
          (item.level ?? '') + '\n' + (item.location ?? '') + '\n' +
          (item.description ?? '') + '\n' + (item.eligibility ?? '') + '\n' +
          (item.notes ?? '') + '\n' + (item.sourceName ?? '') + '\n' +
          (item.sourceHomepage ?? '') + '\n' + (item.upstreamSourceType ?? '') + '\n' +
          (item.sourceAuthority?.toString() ?? ''))
          .toLowerCase();
        if (haystack.indexOf(normalizedQuery) < 0) {
          continue;
        }
      }
      filtered.push(item);
    }
    return ImportantEventQueryLogic.sorted(filtered);
  }

  static availableFilters(items: PublicDeadlineItem[]): ImportantEventFilter[] {
    const result: ImportantEventFilter[] = [ImportantEventFilter.all];
    for (const filter of QueryPageContract.filters) {
      if (filter === ImportantEventFilter.all) {
        continue;
      }
      if (items.some((item: PublicDeadlineItem): boolean =>
        ImportantEventQueryLogic.matchesType(item, filter))) {
        result.push(filter);
      }
    }
    return result;
  }

  static availableCategories(items: PublicDeadlineItem[],
    typeFilter: ImportantEventFilter, showEnded: boolean = false,
    nowMs: number = Date.now()): string[] {
    const result: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (const item of items) {
      if (!ImportantEventQueryLogic.matchesType(item, typeFilter) ||
        (!showEnded && ImportantEventQueryLogic.isEnded(item, nowMs))) {
        continue;
      }
      for (const category of item.categories) {
        if (!seen.has(category)) {
          seen.add(category);
          result.push(category);
        }
      }
    }
    result.sort((left: string, right: string): number =>
      left < right ? -1 : (left > right ? 1 : 0));
    return result;
  }

  static matchesType(item: PublicDeadlineItem, typeFilter: ImportantEventFilter): boolean {
    if (typeFilter === ImportantEventFilter.all) {
      return true;
    }
    if (typeFilter === ImportantEventFilter.schoolNotice) {
      return item.source === PublicDeadlineSource.schoolNotice;
    }
    if (item.source === PublicDeadlineSource.schoolNotice) {
      return false;
    }
    return item.kind === PublicDeadlineKindInfo.fromWireValue(typeFilter);
  }

  static isEnded(item: PublicDeadlineItem, nowMs: number = Date.now()): boolean {
    if (item.archived) {
      return true;
    }
    const deadlineMs: number = new Date(item.deadline).getTime();
    return Number.isFinite(deadlineMs) && deadlineMs < nowMs;
  }

  private static sorted(items: PublicDeadlineItem[]): PublicDeadlineItem[] {
    const result: PublicDeadlineItem[] = items.slice();
    result.sort((left: PublicDeadlineItem, right: PublicDeadlineItem): number => {
      if (left.deadline !== right.deadline) {
        return left.deadline < right.deadline ? -1 : 1;
      }
      return left.name < right.name ? -1 : (left.name > right.name ? 1 : 0);
    });
    return result;
  }
}
