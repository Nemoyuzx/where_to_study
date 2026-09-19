// 合成数据；不包含真实账户、成绩、考试或学校会话。
import { describe, it, expect } from '@ohos/hypium';
import { AcademicTerm, ExamArrangement, ExamSchedule, GradeOptions, GradeSnapshot } from '../main/ets/common/AcademicModels';
import { Course, ScheduleSnapshot } from '../main/ets/common/Models';
import { ScheduleLogic } from '../main/ets/common/ScheduleLogic';
import { StrictDates, DateParts } from '../main/ets/common/StrictDates';
import { CourseRemovalLogic } from '../main/ets/common/CourseRemoval';
import { SJDAcademicParser } from '../main/ets/net/parsers/SjdAcademicParser';
import { CalendarImportLogic, CalendarEventDraft } from '../main/ets/calendar/CalendarImportLogic';
import { DailyCourseNotificationPlanner } from '../main/ets/notify/DailyCoursePlanning';
import { TodayCourseWidgetData, CoursePhase } from '../main/ets/widget/TodayCourseWidgetData';
import { QueryPageContract } from '../main/ets/common/QueryLogic';
import { MobileCalendarTimelineLayout, MobileCalendarTimelineView } from '../main/ets/view/calendar/MobileCalendarTimelineView';
import { CalendarTimelineDay } from '../main/ets/view/calendar/CalendarLogic';
import { AppModel } from '../main/ets/model/AppModel';
import { AppRuntimeMode } from '../main/ets/model/AppRuntimeMode';
import { FileScheduleStore } from '../main/ets/store/ScheduleStore';
import { FileClassroomStore } from '../main/ets/store/ClassroomStore';
import { FileHolidayStore } from '../main/ets/store/HolidayStore';
import { Credentials, CredentialStoring } from '../main/ets/store/CredentialStore';
import { GradeFetching } from '../main/ets/net/SjdGradeClient';

const term: string = '2026-2027-1';
const start: string = '2026-08-31';
const fetched: string = '2026-09-01T00:00:00+08:00';
const owner: string = CourseRemovalLogic.accountScope('synthetic-account');

function exam(id: string, date: string, left: string, right: string): ExamArrangement {
  return new ExamArrangement(id, '合成考试 ' + id, date, left, right, '示例考场', '',
    date + ' ' + left + '-' + right);
}

function snapshot(items: ExamArrangement[]): ScheduleSnapshot {
  return new ScheduleSnapshot(term, start, fetched, [
    new Course('normal', '合成普通课程', '', '', '', [1, 2], [], 1, 0, 1, '1-2', '08:00-09:35'),
    new Course('later', '合成后续课程', '', '', '', [1, 2], [], 1, 2, 3, '3-4', '09:50-11:25')
  ], new ExamSchedule(term, owner, fetched, 'fresh', '', items));
}

class AcademicCredentials implements CredentialStoring {
  async load(): Promise<Credentials | null> { return new Credentials('synthetic-account', 'fixture-only'); }
  async save(credentials: Credentials): Promise<void> {}
  async clear(): Promise<void> {}
}

class AcademicClient implements GradeFetching {
  count: number = 0;
  delay: boolean = false;
  private signalStarted: () => void = () => {};
  private finishDelayed: () => void = () => {};
  readonly started: Promise<void> = new Promise<void>((resolve) => { this.signalStarted = resolve; });
  async options(credentials: Credentials): Promise<GradeOptions> {
    return new GradeOptions(term, [new AcademicTerm(term, term), new AcademicTerm('previous', '合成旧学期')]);
  }
  async fetch(credentials: Credentials, termID: string, recordType: string): Promise<GradeSnapshot> {
    this.count++;
    if (this.delay && termID === term) {
      const wait: Promise<void> = new Promise<void>((resolve) => { this.finishDelayed = resolve; });
      this.signalStarted();
      await wait;
    }
    return new GradeSnapshot(termID, recordType, fetched, null, []);
  }
  finish(): void { this.finishDelayed(); }
}

function modelFor(client: AcademicClient): AppModel {
  const model: AppModel = new AppModel(AppRuntimeMode.live(), new AcademicCredentials(),
    new FileScheduleStore('unused-academic-schedule'), undefined,
    new FileClassroomStore('unused-academic-classrooms'), undefined,
    new FileHolidayStore('unused-academic-holidays'), undefined, undefined, undefined,
    'academic-unit-tests', undefined, undefined, undefined, undefined, client);
  model.account = 'synthetic-account';
  model.hasSavedPassword = true;
  return model;
}

export default function academicQueryTest() {
  describe('AcademicQueryTest', () => {
    it('official_grade_fields_preserve_zero_text_missing_and_semester', 0, () => {
      const result = SJDAcademicParser.grades('{"code":"1","data":[{"pjxfjd":0,"achievement":[' +
        '{"courseName":"合成零分","fraction":0,"credit":0,"cj0708id":"synthetic-id","curSemesterName":"合成学期","cjbs":"合成标识"},' +
        '{"courseName":"合成文字","fraction":"优秀","credit":"2.5"},' +
        '{"courseName":"合成未公布"}]}]}', '', '1', fetched);
      expect(result.items[0].score).assertEqual('0');
      expect(result.items[0].credits).assertEqual('0');
      expect(result.averageGradePoint).assertEqual('0');
      expect(result.items[1].score).assertEqual('优秀');
      expect(result.items[2].score).assertNull();
      expect(result.items[0].semesterName).assertEqual('合成学期');
      expect(result.items[0].gradeStatus).assertEqual('合成标识');
    });

    it('empty_is_distinct_from_malformed_and_failed_responses', 0, () => {
      expect(SJDAcademicParser.grades('{"code":1,"data":[]}', term, '1', fetched).items.length).assertEqual(0);
      expect(SJDAcademicParser.exams('{"code":1,"data":[]}', term, owner, fetched).items.length).assertEqual(0);
      for (const payload of ['<html>login</html>', '{"code":0,"data":[]}',
        '{"code":1}', '{"code":1,"data":{}}', '{"code":1,"data":[{}]}']) {
        let rejected: boolean = false;
        try { SJDAcademicParser.grades(payload, term, '1', fetched); } catch (e) { rejected = true; }
        expect(rejected).assertTrue();
      }
    });

    it('school_term_list_and_current_selection_are_not_generated', 0, () => {
      const options = SJDAcademicParser.options('{"code":1,"data":[{"semesterId":"school-current"}]}',
        '{"code":1,"data":[{"semesterId":"school-old","semesterName":"学校原始学期"}]}');
      expect(options.currentTermID).assertEqual('school-current');
      expect(options.terms.length).assertEqual(1);
      expect(options.terms[0].name).assertEqual('学校原始学期');
    });

    it('exam_parser_keeps_unknown_time_and_uses_verified_location_field', 0, () => {
      const value = SJDAcademicParser.exams('{"code":1,"data":[' +
        '{"courseName":"合成明确考试","time":"2026-08-31 09:20-09:50","examinationPlace":"合成考场","examAddress":"错误字段"},' +
        '{"courseName":"合成未定考试","time":"2026-08-31 时间待定"},' +
        '{"courseName":"合成待定日期","time":"另行通知"},' +
        '{"courseName":"合成错误区间","time":"2026-08-31 12:00-10:00"}]}', term, owner, fetched);
      expect(value.items[0].room).assertEqual('合成考场');
      expect(value.items[0].startTime).assertEqual('09:20');
      expect(value.items[1].date).assertEqual(start);
      expect(value.items[1].startTime).assertEqual('');
      expect(value.items[2].date).assertEqual('');
      expect(value.items[3].endTime).assertEqual('');
    });

    it('actual_overlap_hides_only_that_occurrence_and_touching_boundary_keeps_course', 0, () => {
      const schedule = snapshot([exam('one', start, '09:20', '09:50')]);
      const day = new DateParts(2026, 8, 31);
      const result = ScheduleLogic.effectiveCoursesOn(day, schedule);
      expect(result.map((item: Course) => item.id).join(',')).assertEqual('one,later');
      expect(schedule.courses.length).assertEqual(2);
      expect(schedule.courses[0].weekNumbers.length).assertEqual(2);
      expect(ScheduleLogic.effectiveCoursesOn(StrictDates.addDays(day, 7), schedule).length).assertEqual(2);
      const slots = ScheduleLogic.effectiveBusySlots(day, schedule);
      expect(slots.has(0)).assertFalse();
      expect(slots.has(1)).assertTrue();
      expect(slots.has(2)).assertTrue();
    });

    it('pending_exams_do_not_hide_courses_or_create_time_blocks', 0, () => {
      const schedule = snapshot([exam('pending', start, '', ''), exam('undated', '', '', '')]);
      const result = ScheduleLogic.effectiveCoursesOn(new DateParts(2026, 8, 31), schedule);
      expect(result.length).assertEqual(3);
      expect(MobileCalendarTimelineView.placeCourses(result).length).assertEqual(2);
      expect(ScheduleLogic.effectiveBusySlots(new DateParts(2026, 8, 31), schedule).size).assertEqual(4);
    });

    it('exam_dates_outside_teaching_weeks_do_not_extend_teaching_week_numbers', 0, () => {
      const schedule = snapshot([exam('late-exam', '2027-01-25', '07:00', '08:00')]);
      const result = ScheduleLogic.effectiveCoursesOn(new DateParts(2027, 1, 25), schedule);
      expect(result.length).assertEqual(1);
      expect(result[0].weekNumbers.length).assertEqual(0);
      expect(ScheduleLogic.startMinute(result[0])).assertEqual(420);
      expect(ScheduleLogic.endMinute(result[0])).assertEqual(480);
      const late = ScheduleLogic.examCourse(exam('late', '2027-01-25', '22:05', '22:50'),
        new DateParts(2026, 8, 31));
      if (late !== null) { result.push(late); }
      const bounds = MobileCalendarTimelineLayout.timeBounds([
        new CalendarTimelineDay(new DateParts(2027, 1, 25), result, [])]);
      expect(bounds[0]).assertEqual(420);
      expect(bounds[1]).assertEqual(1380);
    });

    it('failed_exam_refresh_can_only_retain_same_owner_and_term', 0, () => {
      const previous = snapshot([exam('one', start, '09:20', '09:50')]).examSchedule;
      const failed = new ExamSchedule(term, owner, '', 'failed', '合成失败', []);
      expect(ExamSchedule.resolveRefresh(failed, previous, term, owner)?.status).assertEqual('stale');
      expect(ExamSchedule.resolveRefresh(failed, previous, term, 'another-owner')?.items.length).assertEqual(0);
      expect(ExamSchedule.resolveRefresh(failed, previous, 'other-term', owner)?.items.length).assertEqual(0);
      const empty = new ExamSchedule(term, owner, fetched, 'fresh', '', []);
      expect(ExamSchedule.resolveRefresh(empty, previous, term, owner)?.items.length).assertEqual(0);
    });

    it('old_cache_and_exam_cache_round_trip_without_mixing_raw_courses', 0, () => {
      const original = snapshot([exam('one', start, '09:20', '09:50')]);
      const copy = ScheduleSnapshot.fromJson(original.toJson());
      expect(copy.courses.length).assertEqual(2);
      expect(copy.examSchedule?.items.length).assertEqual(1);
      const old = new ScheduleSnapshot(term, start, fetched, original.courses);
      expect(ScheduleSnapshot.fromJson(old.toJson()).examSchedule).assertNull();
      const raw: Record<string, Object> = original.toJson();
      const invalid: Record<string, Object> = { 'term_id': term, 'account_key': '', 'status': 'fresh', 'items': [] };
      raw['exam_schedule'] = invalid;
      expect(ScheduleSnapshot.fromJson(raw).examSchedule).assertNull();
    });

    it('calendar_export_preserves_exact_minutes_and_pending_all_day_semantics', 0, () => {
      const schedule = snapshot([exam('one', start, '09:20', '09:50'), exam('pending', '2027-01-25', '', '')]);
      const drafts = CalendarImportLogic.eventDrafts(schedule);
      expect(drafts.length).assertEqual(5);
      const timed = drafts.find((draft: CalendarEventDraft) => draft.title === '考试 · 合成考试 one');
      expect((timed?.endEpochMs ?? 0) - (timed?.startEpochMs ?? 0)).assertEqual(30 * 60000);
      const pending = drafts.find((draft: CalendarEventDraft) => draft.allDay);
      expect(pending !== undefined).assertTrue();
      expect((pending?.endEpochMs ?? 0) - (pending?.startEpochMs ?? 0)).assertEqual(86400000);
      expect(CalendarImportLogic.schedulePlan(schedule).scope.endEpochMs >= (pending?.endEpochMs ?? 0)).assertTrue();
    });

    it('widget_and_morning_summary_use_the_same_exam_projection', 0, () => {
      const day = new DateParts(2026, 8, 31);
      const schedule = snapshot([exam('one', start, '09:20', '09:50'), exam('pending', start, '', '')]);
      const courses = TodayCourseWidgetData.coursesOn(day, TodayCourseWidgetData.scheduleToArchive(schedule));
      expect(courses.length).assertEqual(3);
      expect(courses.some((course) => course.id === 'normal')).assertFalse();
      const pending = courses.find((course) => course.id === 'pending');
      expect(pending !== undefined).assertTrue();
      if (pending !== undefined) {
        expect(TodayCourseWidgetData.coursePhase(pending, day, 600)).assertEqual(CoursePhase.timePending);
      }
      const requests = DailyCourseNotificationPlanner.requests(schedule,
        new Date('2026-08-31T06:00:00+08:00').getTime(), 1);
      expect(requests.length).assertEqual(1);
      expect(requests[0].body.includes('合成普通课程')).assertFalse();
      expect(requests[0].body.includes('考试 · 时间待定')).assertTrue();
    });

    it('three_query_tabs_fit_phone_tablet_and_large_text_policy', 0, () => {
      expect(QueryPageContract.verticalTabs(390, 1)).assertFalse();
      expect(QueryPageContract.verticalTabs(320, 2)).assertTrue();
      expect(QueryPageContract.verticalTabs(1024, 2)).assertFalse();
    });

    it('grade_cache_separates_term_type_and_explicit_refresh', 0, async () => {
      const client = new AcademicClient();
      const model = modelFor(client);
      await model.loadGrades();
      await model.selectGradeTerm('previous');
      await model.selectGradeTerm(term);
      expect(client.count).assertEqual(2);
      await model.loadGrades(true);
      expect(client.count).assertEqual(3);
      await model.selectGradeRecordType('0');
      expect(client.count).assertEqual(4);
      expect(model.gradeSnapshot?.recordType).assertEqual('0');
      model.resetGradeState();
      expect(model.gradeSnapshot).assertNull();
      await model.loadGrades();
      expect(client.count).assertEqual(5);
    });

    it('late_grade_response_cannot_overwrite_new_term_or_cleared_owner_state', 0, async () => {
      const client = new AcademicClient();
      client.delay = true;
      const model = modelFor(client);
      const old = model.loadGrades();
      await client.started;
      await model.selectGradeTerm('previous');
      client.finish();
      await old;
      expect(model.gradeSnapshot?.termID).assertEqual('previous');
      const other = new AcademicClient();
      other.delay = true;
      const resetModel = modelFor(other);
      const pending = resetModel.loadGrades();
      await other.started;
      resetModel.resetGradeState();
      other.finish();
      await pending;
      expect(resetModel.gradeSnapshot).assertNull();
      expect(resetModel.gradeLoading).assertFalse();
    });
  });
}
