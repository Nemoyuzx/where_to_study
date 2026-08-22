// 本地测试聚合入口（模板默认入口），串行运行全部测试套件。
import strictDatesTest from './StrictDates.test';
import semesterLogicTest from './SemesterLogic.test';
import scheduleLogicTest from './ScheduleLogic.test';
import sjdEncodingTest from './SjdEncoding.test';
import parsersContractTest from './ParsersContract.test';
import teachingCalendarLogicTest from './TeachingCalendarLogic.test';
import calendarImportLogicTest from './CalendarImportLogic.test';
import dailyCoursePlanningTest from './DailyCoursePlanning.test';
import adaptivePolicyTest from './AdaptivePolicy.test';
import robustnessTest from './Robustness.test';
import credentialStoreTest from './CredentialStore.test';
import todayCourseWidgetDataTest from './TodayCourseWidgetData.test';
import dailyInfoClientTest from './DailyInfoClient.test';
import calendarDailyInfoClientTest from './CalendarDailyInfoClient.test';

export default function testsuite() {
  strictDatesTest();
  semesterLogicTest();
  scheduleLogicTest();
  sjdEncodingTest();
  parsersContractTest();
  teachingCalendarLogicTest();
  calendarImportLogicTest();
  dailyCoursePlanningTest();
  adaptivePolicyTest();
  robustnessTest();
  credentialStoreTest();
  todayCourseWidgetDataTest();
  dailyInfoClientTest();
  calendarDailyInfoClientTest();
}
