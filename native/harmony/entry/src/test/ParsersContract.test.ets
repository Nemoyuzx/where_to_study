// 共享契约验证：同一份 contracts/v1 fixtures 在鸿蒙解析器上
// 产生与 Rust/Swift/Kotlin 一致的课表、空教室与节假日语义。
import { describe, it, expect } from '@ohos/hypium';
import { Course, ClassroomsCache, Classroom, CampusClassrooms, HolidayItem,
  HolidaysSnapshot, ScheduleSnapshot } from '../main/ets/common/Models';
import { SJDScheduleParser } from '../main/ets/net/parsers/SjdScheduleParser';
import { SJDClassroomParser } from '../main/ets/net/parsers/SjdClassroomParser';
import { HolidaySourceParser } from '../main/ets/net/parsers/HolidaySourceParser';
import { scheduleText } from './fixtures/schedule';
import { classroomsText } from './fixtures/classrooms';
import { holidaysText } from './fixtures/holidays';
import { holidaySourceText } from './fixtures/holiday-source';
import { sjdCurrentWeekText } from './fixtures/sjd-current-week';
import { sjdBeforeFirstWeekText } from './fixtures/sjd-before-first-week';
import { sjdCurriculumText } from './fixtures/sjd-curriculum';
import { sjdClassroomsXituchengText } from './fixtures/sjd-classrooms-xitucheng';
import { sjdClassroomsShaheText } from './fixtures/sjd-classrooms-shahe';

function assertCoursesEqual(actual: Course[], expected: Course[]): void {
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(actual[i].id).assertEqual(expected[i].id);
    expect(actual[i].name).assertEqual(expected[i].name);
    expect(actual[i].teacher).assertEqual(expected[i].teacher);
    expect(actual[i].room).assertEqual(expected[i].room);
    expect(actual[i].weekText).assertEqual(expected[i].weekText);
    expect(actual[i].weekNumbers.join(',')).assertEqual(expected[i].weekNumbers.join(','));
    expect(actual[i].examWeekNumbers.join(','))
      .assertEqual(expected[i].examWeekNumbers.join(','));
    expect(actual[i].weekday).assertEqual(expected[i].weekday);
    expect(actual[i].startSlot).assertEqual(expected[i].startSlot);
    expect(actual[i].endSlot).assertEqual(expected[i].endSlot);
    expect(actual[i].sectionText).assertEqual(expected[i].sectionText);
    expect(actual[i].timeRange).assertEqual(expected[i].timeRange);
  }
}

function assertRoomsEqual(actual: Classroom[], expected: Classroom[]): void {
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(actual[i].id).assertEqual(expected[i].id);
    expect(actual[i].building).assertEqual(expected[i].building);
    expect(actual[i].room).assertEqual(expected[i].room);
    expect(actual[i].name).assertEqual(expected[i].name);
    expect(actual[i].size).assertEqual(expected[i].size);
    expect(actual[i].availableSlots.join(',')).assertEqual(expected[i].availableSlots.join(','));
    expect(actual[i].source).assertEqual(expected[i].source);
  }
}

export default function parsersContractTest() {
  describe('ParsersContractTest', () => {
    it('shared_sjd_fixtures_produce_contract_schedule', 0, () => {
      const expected: ScheduleSnapshot = ScheduleSnapshot.fromJson(
        JSON.parse(scheduleText) as Record<string, Object>);
      const parsed: ScheduleSnapshot = SJDScheduleParser.parse(
        sjdCurrentWeekText, sjdCurriculumText, 'fallback', '2000-01-03', expected.fetchedAt);
      expect(parsed.termID).assertEqual(expected.termID);
      expect(parsed.termStartDate).assertEqual(expected.termStartDate);
      expect(parsed.fetchedAt).assertEqual(expected.fetchedAt);
      assertCoursesEqual(parsed.courses, expected.courses);
    });

    it('schedule_parser_uses_fallback_only_when_current_week_metadata_is_missing', 0, () => {
      const parsed: ScheduleSnapshot = SJDScheduleParser.parse(
        '{"code":1,"data":[{}]}', sjdCurriculumText,
        '2026-2027-1', '2026-08-31', '2026-08-24T12:00:00+08:00');
      expect(parsed.termID).assertEqual('2026-2027-1');
      expect(parsed.termStartDate).assertEqual('2026-08-31');
    });

    it('schedule_parser_reads_top_info_and_infers_start_from_week_zero', 0, () => {
      const parsed: ScheduleSnapshot = SJDScheduleParser.parse(
        sjdBeforeFirstWeekText, sjdCurriculumText,
        'fallback-term', '2000-01-03', '2026-08-24T12:00:00+08:00');
      expect(parsed.termID).assertEqual('2026-2027-1');
      expect(parsed.termStartDate).assertEqual('2026-08-31');
    });

    it('schedule_parser_prefers_date_week_and_normalizes_sunday_zero', 0, () => {
      const current: string = '{"code":1,"data":[{' +
        '"week":"9","topInfo":[{"semesterId":"2026-2027-1","week":"9"}],' +
        '"date":[{"mxrq":"2026-08-30","xqid":"0","zc":"0"}]}]}';
      const parsed: ScheduleSnapshot = SJDScheduleParser.parse(
        current, sjdCurriculumText,
        'fallback-term', '2000-01-03', '2026-08-24T12:00:00+08:00');
      expect(parsed.termID).assertEqual('2026-2027-1');
      expect(parsed.termStartDate).assertEqual('2026-08-31');
    });

    it('schedule_room_normalization_keeps_dual_door_rooms', 0, () => {
      expect(SJDScheduleParser.normalizeCourseRoom('3-335')).assertEqual('335');
      expect(SJDScheduleParser.normalizeCourseRoom('教1-101')).assertEqual('101');
      expect(SJDScheduleParser.normalizeCourseRoom('202-203')).assertEqual('202-203');
      expect(SJDScheduleParser.normalizeCourseRoom('217-218')).assertEqual('217-218');
    });

    it('shared_sjd_classroom_fixtures_produce_contract_cache', 0, () => {
      const expected: ClassroomsCache = ClassroomsCache.fromJson(
        JSON.parse(classroomsText) as Record<string, Object>);
      const payloads: Map<string, string> = new Map<string, string>();
      payloads.set('01', sjdClassroomsXituchengText);
      payloads.set('04', sjdClassroomsShaheText);
      const parsed: ClassroomsCache = SJDClassroomParser.parse(
        payloads, expected.targetDate, expected.fetchedAt);
      expect(parsed.cacheVersion).assertEqual(expected.cacheVersion);
      expect(parsed.targetDate).assertEqual(expected.targetDate);
      expect(parsed.realtime).assertEqual(expected.realtime);
      expect(parsed.provider).assertEqual(expected.provider);
      expect(parsed.campuses.length).assertEqual(expected.campuses.length);
      for (let i = 0; i < expected.campuses.length; i++) {
        expect(parsed.campuses[i].campusID).assertEqual(expected.campuses[i].campusID);
        expect(parsed.campuses[i].campusName).assertEqual(expected.campuses[i].campusName);
        assertRoomsEqual(parsed.campuses[i].rooms, expected.campuses[i].rooms);
      }
    });

    it('shared_holiday_fixture_matches_contract', 0, () => {
      const expected: HolidaysSnapshot = HolidaysSnapshot.fromJson(
        JSON.parse(holidaysText) as Record<string, Object>);
      const actual: HolidaysSnapshot = HolidaySourceParser.parse(
        holidaySourceText, expected.year, expected.source, expected.fetchedAt);
      expect(actual.year).assertEqual(expected.year);
      expect(actual.source).assertEqual(expected.source);
      expect(actual.items.length).assertEqual(expected.items.length);
      for (let i = 0; i < expected.items.length; i++) {
        expect(actual.items[i].date).assertEqual(expected.items[i].date);
        expect(actual.items[i].name).assertEqual(expected.items[i].name);
        expect(actual.items[i].type).assertEqual(expected.items[i].type);
      }
    });

    it('holiday_parser_rejects_mismatched_or_malformed_data', 0, () => {
      const mismatchedYear: string =
        '{"year":2026,"region":"CN","dates":[{"date":"2025-12-31","name":"跨年假期","type":"public_holiday"}]}';
      let threw: boolean = false;
      try {
        HolidaySourceParser.parse(mismatchedYear, 2026, 'https://unpkg.com/holiday-calendar@1.3.3/data/CN',
          '2026-01-01T00:00:00+08:00');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();

      const malformedDate: string =
        '{"year":2026,"region":"CN","dates":[{"date":"2026-1-01","name":"测试","type":"public_holiday"}]}';
      threw = false;
      try {
        HolidaySourceParser.parse(malformedDate, 2026, 'https://unpkg.com/holiday-calendar@1.3.3/data/CN',
          '2026-01-01T00:00:00+08:00');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();

      const malformedEnvelope: string = '{"year":2026,"region":"CN","dates":{}}';
      threw = false;
      try {
        HolidaySourceParser.parse(malformedEnvelope, 2026, 'https://unpkg.com/holiday-calendar@1.3.3/data/CN',
          '2026-01-01T00:00:00+08:00');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();

      const wrongRegion: string =
        '{"year":2026,"region":"US","dates":[{"date":"2026-01-01","name":"测试","type":"public_holiday"}]}';
      threw = false;
      try {
        HolidaySourceParser.parse(wrongRegion, 2026, 'https://unpkg.com/holiday-calendar@1.3.3/data/CN',
          '2026-01-01T00:00:00+08:00');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();

      let oversized: string = '';
      for (let i = 0; i < 256 * 1024 + 1; i++) {
        oversized += ' ';
      }
      threw = false;
      try {
        HolidaySourceParser.parse(oversized, 2026, 'https://unpkg.com/holiday-calendar@1.3.3/data/CN',
          '2026-01-01T00:00:00+08:00');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('holiday_parser_skips_unknown_types', 0, () => {
      const source: string =
        '{"year":2026,"region":"CN","dates":[{"date":"2026-01-01","name":"元旦","type":"public_holiday"},' +
        '{"date":"2026-01-02","name":"未知类型","type":"custom_type"}]}';
      const parsed: HolidaysSnapshot = HolidaySourceParser.parse(
        source, 2026, 'https://unpkg.com/holiday-calendar@1.3.3/data/CN',
        '2026-01-01T00:00:00+08:00');
      expect(parsed.items.length).assertEqual(1);
      expect(parsed.items[0].name).assertEqual('元旦');
      expect(parsed.items[0].type).assertEqual('holiday');
    });
  });
}
