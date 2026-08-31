import {
  FavoriteDeadlineCodec, PublicDeadlineItem, PublicDeadlineKind, PublicDeadlineKindInfo,
  PublicDeadlineSource
} from '../net/CalendarDailyInfoClient';

export enum QueryPageTab {
  shuttle = 'shuttle',
  events = 'events'
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
  static readonly tabs: QueryPageTab[] = [QueryPageTab.shuttle, QueryPageTab.events];
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
    return tab === QueryPageTab.shuttle ? '班车查询' : '重要事件';
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
