import { GradeOptions, GradeSnapshot } from '../common/AcademicModels';
import { StrictDates } from '../common/StrictDates';
import { Credentials } from '../store/CredentialStore';
import { SJDAPIClient } from './SjdApi';
import { SJDAcademicParser } from './parsers/SjdAcademicParser';

export interface GradeFetching {
  options(credentials: Credentials): Promise<GradeOptions>;
  fetch(credentials: Credentials, termID: string, recordType: string): Promise<GradeSnapshot>;
}

export class SJDGradeClient implements GradeFetching {
  private readonly api: SJDAPIClient = new SJDAPIClient();

  async options(credentials: Credentials): Promise<GradeOptions> {
    const token: string = await this.api.login(credentials);
    const data: string[] = await Promise.all([this.api.academic(token, '/currentTerm'),
      this.api.academic(token, '/semesterList')]);
    return SJDAcademicParser.options(data[0], data[1]);
  }

  async fetch(credentials: Credentials, termID: string, recordType: string): Promise<GradeSnapshot> {
    const token: string = await this.api.login(credentials);
    const values: Map<string, string> = new Map<string, string>();
    values.set('semester', termID);
    values.set('type', recordType);
    return SJDAcademicParser.grades(await this.api.academic(token, '/student/termGPA', values),
      termID, recordType, StrictDates.formatFetchedAt(Date.now()));
  }
}
