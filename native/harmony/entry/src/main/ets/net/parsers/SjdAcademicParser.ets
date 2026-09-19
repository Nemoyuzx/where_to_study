import { AcademicTerm, AcademicTime, ExamArrangement, ExamSchedule,
  GradeItem, GradeOptions, GradeSnapshot } from '../../common/AcademicModels';
import { JsonUtil } from '../../common/JsonUtil';
import { Sha1 } from '../../common/Sha1';
import { StrictDates } from '../../common/StrictDates';
import { ScheduleClientError } from '../SjdErrors';

// 字段以学校公开前端为准；结构错误绝不降级为空数组。
export class SJDAcademicParser {
  static data(text: string): Object[] {
    const root: Record<string, Object> | null = JsonUtil.parseObject(text);
    if (root === null || JsonUtil.string(root['code']) !== '1' || !Array.isArray(root['data'])) {
      throw ScheduleClientError.invalidResponse('教务查询暂不可用，请稍后刷新。');
    }
    return JsonUtil.array(root['data']);
  }

  private static row(value: Object): Record<string, Object> {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw ScheduleClientError.invalidResponse('教务查询返回了无法识别的数据。');
    }
    return value as Record<string, Object>;
  }

  static options(currentText: string, termsText: string): GradeOptions {
    const current: Object[] = SJDAcademicParser.data(currentText);
    const currentID: string = current.length === 0 ? '' :
      JsonUtil.string(SJDAcademicParser.row(current[0])['semesterId']);
    if (currentID.length === 0) {
      throw ScheduleClientError.invalidResponse('教务未返回当前学期，请稍后刷新。');
    }
    const terms: AcademicTerm[] = [];
    const seen: Set<string> = new Set<string>();
    for (const value of SJDAcademicParser.data(termsText)) {
      const raw: Record<string, Object> = SJDAcademicParser.row(value);
      const id: string = JsonUtil.string(raw['semesterId']).trim();
      if (id.length === 0) {
        throw ScheduleClientError.invalidResponse('教务学期列表暂不可用。');
      }
      if (!seen.has(id)) {
        seen.add(id);
        terms.push(new AcademicTerm(id, JsonUtil.string(raw['semesterName']).trim() || id));
      }
    }
    return new GradeOptions(currentID, terms);
  }

  static grades(text: string, termID: string, recordType: string, fetchedAt: string): GradeSnapshot {
    const data: Object[] = SJDAcademicParser.data(text);
    if (data.length === 0) { return new GradeSnapshot(termID, recordType, fetchedAt, null, []); }
    const root: Record<string, Object> = SJDAcademicParser.row(data[0]);
    if (!Array.isArray(root['achievement'])) {
      throw ScheduleClientError.invalidResponse('成绩数据暂不可用，请稍后刷新。');
    }
    const items: GradeItem[] = [];
    const counts: Map<string, number> = new Map<string, number>();
    for (const value of JsonUtil.array(root['achievement'])) {
      const raw: Record<string, Object> = SJDAcademicParser.row(value);
      const name: string = JsonUtil.string(raw['courseName']).trim();
      if (name.length === 0) { throw ScheduleClientError.invalidResponse('成绩数据格式不正确。'); }
      const score: string | null = SJDAcademicParser.scalar(raw['fraction']);
      const credits: string | null = SJDAcademicParser.scalar(raw['credit']);
      const code: string = JsonUtil.string(raw['kcbh']);
      const attribute: string = JsonUtil.string(raw['curriculumAttributes']);
      const nature: string = JsonUtil.string(raw['courseNature']);
      const exam: string = JsonUtil.string(raw['examinationNature']);
      const semester: string = JsonUtil.string(raw['curSemesterName']);
      const status: string = JsonUtil.string(raw['cjbs']);
      const sourceID: string = JsonUtil.string(raw['cj0708id']);
      const key: string = Sha1.hexOfUtf8(sourceID.length > 0 ? sourceID :
        JSON.stringify([name, score, credits, code, attribute, nature, exam, semester, status]));
      const count: number = (counts.get(key) ?? 0) + 1;
      counts.set(key, count);
      items.push(new GradeItem(key + '.' + count.toString(), name, score, credits, code, attribute, nature,
        exam, semester, status));
    }
    return new GradeSnapshot(termID, recordType, fetchedAt, SJDAcademicParser.scalar(root['pjxfjd']), items);
  }

  private static scalar(value: Object | undefined): string | null {
    if (typeof value !== 'string' && typeof value !== 'number') { return null; }
    const result: string = JsonUtil.string(value).trim();
    return result.length > 0 ? result : null;
  }

  static exams(text: string, termID: string, accountKey: string, fetchedAt: string): ExamSchedule {
    const items: ExamArrangement[] = [];
    const seen: Set<string> = new Set<string>();
    for (const value of SJDAcademicParser.data(text)) {
      const raw: Record<string, Object> = SJDAcademicParser.row(value);
      const name: string = JsonUtil.string(raw['courseName']).trim();
      if (name.length === 0) { throw ScheduleClientError.invalidResponse('考试安排数据格式不正确。'); }
      const primary: string = JsonUtil.string(raw['time']).trim();
      const auxiliary: string = [JsonUtil.string(raw['ksqssj']),
        JsonUtil.string(raw['zssj1']), JsonUtil.string(raw['zssj2'])].filter(
        (part: string) => part.length > 0).join(' ');
      const timeText: string = primary.length > 0 ? primary : auxiliary;
      const dateMatch: RegExpMatchArray | null = timeText.match(/\b(\d{4})[-/](\d{1,2})[-/](\d{1,2})\b/);
      const dateMentions: RegExpMatchArray | null = timeText.match(/\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b/g);
      let date: string = '';
      if (dateMatch !== null && (dateMentions === null ||
        dateMentions.every((mention: string) => mention === dateMatch[0]))) {
        const candidate: string = dateMatch[1] + '-' + dateMatch[2].padStart(2, '0') + '-' +
          dateMatch[3].padStart(2, '0');
        if (StrictDates.parseDateString(candidate) !== null) { date = candidate; }
      }
      const times: RegExpMatchArray | null = timeText.match(/(?:^|\s|\()([0-2]?\d:[0-5]\d)\s*[-~～—–至]\s*([0-2]?\d:[0-5]\d)(?:\s|\)|$)/);
      let start: string = '';
      let end: string = '';
      if (times !== null) {
        const left: string = times[1].padStart(5, '0');
        const right: string = times[2].padStart(5, '0');
        if (AcademicTime.validInterval(left, right)) { start = left; end = right; }
      } else if (primary.length === 0) {
        const left: string = JsonUtil.string(raw['zssj1']).trim().padStart(5, '0');
        const right: string = JsonUtil.string(raw['zssj2']).trim().padStart(5, '0');
        if (AcademicTime.validInterval(left, right)) { start = left; end = right; }
      }
      const room: string = JsonUtil.string(raw['examinationPlace']).trim();
      const id: string = 'exam-' + Sha1.hexOfUtf8(JSON.stringify([name, date, start, end, room, timeText]));
      if (!seen.has(id)) {
        seen.add(id);
        items.push(new ExamArrangement(id, name, date, start, end, room, '', timeText));
      }
    }
    return new ExamSchedule(termID, accountKey, fetchedAt, 'fresh', '', items);
  }
}
