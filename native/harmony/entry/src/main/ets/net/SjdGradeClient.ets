import { ExamSchedule, GradeOptions, GradeSnapshot } from '../common/AcademicModels';
import { CourseRemovalLogic } from '../common/CourseRemoval';
import { StrictDates } from '../common/StrictDates';
import { Credentials } from '../store/CredentialStore';
import { SJDAPIClient } from './SjdApi';
import { SJDAcademicParser } from './parsers/SjdAcademicParser';

export interface GradeFetching {
  options(credentials: Credentials): Promise<GradeOptions>;
  fetch(credentials: Credentials, termID: string, recordType: string): Promise<GradeSnapshot>;
}

export interface ExamFetching {
  fetch(credentials: Credentials, termID: string): Promise<ExamSchedule>;
}

export class SJDExamClient implements ExamFetching {
  private readonly api: SJDAPIClient = new SJDAPIClient();
  async fetch(credentials: Credentials, termID: string): Promise<ExamSchedule> {
    return await this.api.withSession(credentials, async (token: string): Promise<ExamSchedule> => {
      const values: Map<string, string> = new Map<string, string>();
      values.set('semester', termID);
      return SJDAcademicParser.exams(await this.api.academic(token, '/student/examinationArrangement', values),
        termID, CourseRemovalLogic.accountScope(credentials.account), StrictDates.formatFetchedAt(Date.now()));
    });
  }
}

export class SJDGradeClient implements GradeFetching {
  private readonly api: SJDAPIClient = new SJDAPIClient();

  async options(credentials: Credentials): Promise<GradeOptions> {
    return await this.api.withSession(credentials, async (token: string): Promise<GradeOptions> => {
      const data: string[] = await Promise.all([this.api.academic(token, '/currentTerm'),
        this.api.academic(token, '/semesterList')]);
      return SJDAcademicParser.options(data[0], data[1]);
    });
  }

  async fetch(credentials: Credentials, termID: string, recordType: string): Promise<GradeSnapshot> {
    return await this.api.withSession(credentials, async (token: string): Promise<GradeSnapshot> => {
      const values: Map<string, string> = new Map<string, string>();
      values.set('semester', termID);
      values.set('type', recordType);
      return SJDAcademicParser.grades(await this.api.academic(token, '/student/termGPA', values),
        termID, recordType, StrictDates.formatFetchedAt(Date.now()));
    });
  }
}
