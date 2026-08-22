// 与 iOS 端 UITestSupport.swift 的 SampleData 对应的内置示例数据。
import { Classroom, CampusClassrooms, ClassroomsCache, ClassroomDefaults, Course,
  HolidaysSnapshot, ScheduleSnapshot, SlotMetadata } from '../common/Models';
import { StrictDates, DateParts } from '../common/StrictDates';
import { HolidayOfflineFallback } from '../net/parsers/HolidaySourceParser';
import { CampusWeather, CampusWeatherDay, CampusWeatherTarget,
  WeatherSourceParser } from '../net/DailyInfoClient';

export class SampleData {
  static readonly timestamp: string = '2026-01-01T00:00:00+08:00';

  static schedule(): ScheduleSnapshot {
    const now: DateParts = StrictDates.todayParts();
    const weekday: number = StrictDates.weekdayMonday1(now);
    const weekStart: DateParts = StrictDates.addDays(now, 1 - weekday);
    const adjacentWeekday: number = weekday === 7 ? 1 : weekday + 1;
    return new ScheduleSnapshot(
      'review-demo',
      StrictDates.formatDateParts(weekStart),
      SampleData.timestamp,
      [
        new Course(
          'sample-data-mining', '数据挖掘', '示例教师', '教3-335', '1-2', [1, 2], [],
          weekday, 2, 4, '3-5节', '09:50-12:15'),
        new Course(
          'sample-neural-network', '神经网络与深度学习', '示例教师', '教3-539', '1-2', [1, 2], [],
          adjacentWeekday, 7, 8, '8-9节', '14:45-16:25')
      ]
    );
  }

  static classrooms(): ClassroomsCache {
    const targetDate: string = StrictDates.formatDateParts(StrictDates.todayParts());
    return new ClassroomsCache(
      ClassroomDefaults.cacheVersion,
      targetDate,
      SampleData.timestamp,
      false,
      'review-demo',
      [
        new CampusClassrooms(
          '01', '西土城', targetDate, SampleData.timestamp, false, 'review-demo',
          [
            SampleData.room('教1', '101', 80, SampleData.allSlots()),
            SampleData.room('教2', '201', 64, [0, 1, 5, 6, 9, 10, 11]),
            SampleData.room('主楼', '217-218', 60, [0, 1, 7, 8, 9, 10, 11, 12, 13])
          ]
        ),
        new CampusClassrooms(
          '04', '沙河', targetDate, SampleData.timestamp, false, 'review-demo',
          [
            SampleData.room('综合教学楼N', '101', 90, SampleData.allSlots()),
            SampleData.room('智慧教学楼', '305-306', 60, [0, 1, 2, 3, 8, 9])
          ]
        )
      ]
    );
  }

  static holidaysOrNull(year: number): HolidaysSnapshot | null {
    return HolidayOfflineFallback.snapshot(year);
  }

  static weather(campusID: string): CampusWeather {
    const target: CampusWeatherTarget = WeatherSourceParser.target(campusID);
    const today: DateParts = StrictDates.todayParts();
    const tomorrow: DateParts = StrictDates.addDays(today, 1);
    return new CampusWeather(
      target.campusID,
      target.campusName,
      target.campusID === '01' ? '海淀区' : '昌平区',
      '多云',
      27,
      '示例数据',
      [
        new CampusWeatherDay(
          StrictDates.formatDateParts(today), '今天', '多云', '雷阵雨', 32, 23, 40),
        new CampusWeatherDay(
          StrictDates.formatDateParts(tomorrow), '明天', '晴', '多云', 33, 22, 10)
      ]
    );
  }

  private static room(building: string, number: string, size: number, slots: number[]): Classroom {
    return new Classroom(
      building + '-' + number, building, number, building + '-' + number, size, '', slots, 'review-demo');
  }

  private static allSlots(): number[] {
    const result: number[] = [];
    for (let i = 0; i < SlotMetadata.defaults.length; i++) {
      result.push(i);
    }
    return result;
  }
}
