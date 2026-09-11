import { describe, it, expect } from '@ohos/hypium';
import { Course, ScheduleSnapshot } from '../main/ets/common/Models';
import { CourseRemovalLogic, CourseRemovalRecord } from '../main/ets/common/CourseRemoval';
import { DateParts } from '../main/ets/common/StrictDates';
import { ScheduleLogic } from '../main/ets/common/ScheduleLogic';
import { CalendarImportLogic } from '../main/ets/calendar/CalendarImportLogic';

function removalCourse(id: string, weekday: number = 1, room: string = 'A',
  sourceID: string = 'source-one', teacher: string = 'Teacher', startSlot: number = 0): Course {
  return new Course(id, 'Course', teacher, room, '1-3', [1, 2, 3], [], weekday,
    startSlot, startSlot + 1, '1-2', '08:00-09:35', sourceID);
}

function removalSchedule(courses: Course[], termID: string = '2026-2027-1'): ScheduleSnapshot {
  return new ScheduleSnapshot(termID, '2026-08-31', '2026-09-01T00:00:00+08:00', courses);
}

export default function courseRemovalTest() {
  describe('CourseRemovalTest', () => {
    it('whole_course_removal_groups_source_rows_and_survives_refresh_changes', 0, () => {
      const first: Course = removalCourse('one');
      const snapshot: ScheduleSnapshot = removalSchedule([first, removalCourse('two', 3),
        removalCourse('other', 1, 'B', 'source-two')]);
      const record: CourseRemovalRecord = CourseRemovalLogic.create('student', snapshot, first,
        new DateParts(2026, 8, 31), true);
      const restoredRecord: CourseRemovalRecord = CourseRemovalRecord.fromJson(record.toJson());
      expect(CourseRemovalLogic.apply(snapshot, 'student', [restoredRecord]).courses.length).assertEqual(1);
      const refreshed: ScheduleSnapshot = removalSchedule([removalCourse('changed-row', 5, 'new-room')]);
      expect(CourseRemovalLogic.apply(refreshed, 'student', [restoredRecord]).courses.length).assertEqual(0);
      expect(CourseRemovalLogic.apply(snapshot, 'student', []).courses.length).assertEqual(3);
      expect(snapshot.courses.length).assertEqual(3);
    });

    it('single_occurrence_preserves_other_weeks_days_and_periods', 0, () => {
      const first: Course = removalCourse('one');
      const snapshot: ScheduleSnapshot = removalSchedule([first, removalCourse('other-day', 3),
        removalCourse('other-period', 1, 'B', 'source-one', 'Teacher', 4)]);
      const record: CourseRemovalRecord = CourseRemovalLogic.create('student', snapshot, first,
        new DateParts(2026, 9, 7), false);
      const filtered: ScheduleSnapshot = CourseRemovalLogic.apply(snapshot, 'student', [record]);
      expect(filtered.courses[0].weekNumbers.join(',')).assertEqual('1,3');
      expect(filtered.courses[1].weekNumbers.join(',')).assertEqual('1,2,3');
      expect(filtered.courses[2].weekNumbers.join(',')).assertEqual('1,2,3');
      expect(ScheduleLogic.busySlots(new DateParts(2026, 9, 7), new DateParts(2026, 8, 31),
        filtered.courses).has(0)).assertFalse();
      expect(CalendarImportLogic.eventDrafts(filtered).length)
        .assertEqual(CalendarImportLogic.eventDrafts(snapshot).length - 1);
      expect(first.weekNumbers.join(',')).assertEqual('1,2,3');
    });

    it('records_are_account_term_scoped_and_legacy_identity_uses_name_teacher', 0, () => {
      const legacy: Course = removalCourse('legacy', 1, 'A', '');
      const snapshot: ScheduleSnapshot = removalSchedule([legacy]);
      const record: CourseRemovalRecord = CourseRemovalLogic.create('student', snapshot, legacy,
        new DateParts(2026, 8, 31), true);
      expect(CourseRemovalLogic.apply(snapshot, 'other', [record]).courses.length).assertEqual(1);
      expect(CourseRemovalLogic.apply(removalSchedule([legacy], '2026-2027-2'),
        'student', [record]).courses.length).assertEqual(1);
      expect(record.matchesCourse(removalCourse('new', 3, 'B', 'new-source'))).assertTrue();
      expect(record.matchesCourse(removalCourse('new', 3, 'B', 'new-source', 'Other'))).assertFalse();
      expect(Course.fromJson(legacy.toJson()).sourceCourseID).assertEqual('');
      expect(Course.fromJson(removalCourse('new').toJson()).sourceCourseID).assertEqual('source-one');
    });

    it('whole_and_occurrence_records_restore_independently', 0, () => {
      const course: Course = removalCourse('one');
      const snapshot: ScheduleSnapshot = removalSchedule([course]);
      const whole: CourseRemovalRecord = CourseRemovalLogic.create('student', snapshot, course,
        new DateParts(2026, 9, 7), true);
      const once: CourseRemovalRecord = CourseRemovalLogic.create('student', snapshot, course,
        new DateParts(2026, 9, 7), false);
      expect(CourseRemovalLogic.apply(snapshot, 'student', [whole, once]).courses.length).assertEqual(0);
      expect(CourseRemovalLogic.apply(snapshot, 'student', [once]).courses[0].weekNumbers.join(','))
        .assertEqual('1,3');
    });
  });
}
