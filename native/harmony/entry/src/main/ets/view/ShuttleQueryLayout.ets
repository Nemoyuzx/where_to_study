// 班车页的纯布局/展示投影；数据有效期与当日班次仍由 ShuttleBusLogic 判定。
import {
  ShuttleBusDailyView, ShuttleBusLogic, ShuttleBusPeriodState, ShuttleBusStop
} from '../net/ShuttleBusClient';

export class ShuttleQueryLayout {
  static readonly maximumPageWidthVp: number = 1180;
  static readonly pagePaddingVp: number = 16;
  static readonly cardPaddingVp: number = 16;
  static readonly routeGapVp: number = 16;
  static readonly departureGapVp: number = 8;
  static readonly minimumRouteWidthVp: number = 280;
  static readonly minimumDepartureWidthVp: number = 86;

  static fontScale(value: number): number {
    return Number.isFinite(value) && value > 0 ? Math.max(1, value) : 1;
  }

  static contentWidth(viewportWidth: number): number {
    const width: number = Number.isFinite(viewportWidth) && viewportWidth > 0 ? viewportWidth : 390;
    return Math.max(1, Math.min(width, ShuttleQueryLayout.maximumPageWidthVp) -
      ShuttleQueryLayout.pagePaddingVp * 2);
  }

  static routeColumns(viewportWidth: number, fontScale: number = 1): number {
    return Math.max(1, Math.floor((ShuttleQueryLayout.contentWidth(viewportWidth) +
      ShuttleQueryLayout.routeGapVp) /
      (ShuttleQueryLayout.minimumRouteWidthVp * ShuttleQueryLayout.fontScale(fontScale) +
        ShuttleQueryLayout.routeGapVp)));
  }

  static routeWidth(viewportWidth: number, fontScale: number = 1): number {
    const columns: number = ShuttleQueryLayout.routeColumns(viewportWidth, fontScale);
    return (ShuttleQueryLayout.contentWidth(viewportWidth) -
      ShuttleQueryLayout.routeGapVp * (columns - 1)) / columns;
  }

  static departureColumns(viewportWidth: number, fontScale: number = 1): number {
    const width: number = Math.max(1, ShuttleQueryLayout.routeWidth(viewportWidth, fontScale) -
      ShuttleQueryLayout.cardPaddingVp * 2);
    return Math.max(1, Math.floor((width + ShuttleQueryLayout.departureGapVp) /
      (ShuttleQueryLayout.minimumDepartureWidthVp * ShuttleQueryLayout.fontScale(fontScale) +
        ShuttleQueryLayout.departureGapVp)));
  }

  static columnIndices(columns: number): number[] {
    const count: number = Number.isFinite(columns) && columns > 0 ? Math.max(1, Math.floor(columns)) : 1;
    const tracks: number[] = [];
    for (let index: number = 0; index < count; index += 1) {
      tracks.push(index);
    }
    return tracks;
  }

  static rows<T>(items: T[], columns: number): T[][] {
    const count: number = ShuttleQueryLayout.columnIndices(columns).length;
    const rows: T[][] = [];
    for (let index: number = 0; index < items.length; index += count) {
      rows.push(items.slice(index, index + count));
    }
    return rows;
  }

  static departureCount(daily: ShuttleBusDailyView): number {
    if (daily.state !== ShuttleBusPeriodState.active) {
      return 0;
    }
    let count: number = 0;
    for (const schedule of daily.schedules) {
      count += ShuttleBusLogic.servicesForToday(schedule, daily.weekdayKey).length;
    }
    return count;
  }

  static statusTitle(daily: ShuttleBusDailyView): string {
    if (daily.state !== ShuttleBusPeriodState.active || daily.schedules.length === 0) {
      return '今日暂无生效的班车时刻表';
    }
    return ShuttleQueryLayout.departureCount(daily) === 0 ?
      '今日没有计划班次' : '今日班车按时刻表运行';
  }

  static unmatchedStops(daily: ShuttleBusDailyView): ShuttleBusStop[] {
    if (daily.scheduleNotice === null) {
      return [];
    }
    return daily.scheduleNotice.stops.filter((stop: ShuttleBusStop): boolean =>
      !daily.schedules.some((schedule): boolean => schedule.from === stop.campus));
  }
}
