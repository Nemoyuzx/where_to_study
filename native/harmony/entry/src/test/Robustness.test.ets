// 健壮性回归测试（BUG-018/019/049/062 修复验证）。
import { describe, it, expect } from '@ohos/hypium';
import { Course, ScheduleSnapshot } from '../main/ets/common/Models';
import { JsonUtil } from '../main/ets/common/JsonUtil';
import { Utf8 } from '../main/ets/common/Utf8';
import { SJDFormURLEncoder } from '../main/ets/net/SjdEncoding';
import { HolidaySourceParser } from '../main/ets/net/parsers/HolidaySourceParser';
import {
  SchedulePersistenceCoordinator, ScheduleStoring
} from '../main/ets/store/ScheduleStore';

class ControlledScheduleStore implements ScheduleStoring {
  stored: ScheduleSnapshot | null = null;
  clearCount: number = 0;
  readonly firstSaveStarted: Promise<void>;
  private readonly firstSaveGate: Promise<void>;
  private markFirstSaveStarted: (() => void) | null = null;
  private releaseFirstSave: (() => void) | null = null;
  private delayNextSave: boolean = true;

  constructor() {
    this.firstSaveStarted = new Promise<void>((resolve) => {
      this.markFirstSaveStarted = (): void => resolve();
    });
    this.firstSaveGate = new Promise<void>((resolve) => {
      this.releaseFirstSave = (): void => resolve();
    });
  }

  async load(): Promise<ScheduleSnapshot | null> {
    return this.stored;
  }

  async save(schedule: ScheduleSnapshot): Promise<void> {
    if (this.delayNextSave) {
      this.delayNextSave = false;
      const markStarted: (() => void) | null = this.markFirstSaveStarted;
      if (markStarted !== null) {
        markStarted();
      }
      await this.firstSaveGate;
    }
    this.stored = schedule;
  }

  async clear(): Promise<void> {
    this.clearCount++;
    this.stored = null;
  }

  resumeFirstSave(): void {
    const release: (() => void) | null = this.releaseFirstSave;
    if (release !== null) {
      release();
    }
  }
}

function persistenceSchedule(termID: string): ScheduleSnapshot {
  return new ScheduleSnapshot(termID, '2026-08-31', '2026-08-24T12:00:00+08:00', []);
}

export default function robustnessTest() {
  describe('RobustnessTest', () => {
    it('course_from_json_clamps_out_of_range_slots', 0, () => {
      // BUG-049：越界节次/星期不得导致时间线越界访问。
      const raw: Record<string, Object> = {
        'id': 'c1', 'name': '越界课', 'teacher': '', 'room': '', 'week_text': '1-16',
        'week_numbers': [1], 'exam_week_numbers': [], 'weekday': 9,
        'start_slot': 99, 'end_slot': -3, 'section_text': '100节', 'time_range': '00:00-23:59'
      };
      const course: Course = Course.fromJson(raw);
      expect(course.weekday).assertEqual(7);
      expect(course.startSlot).assertEqual(13);
      expect(course.endSlot >= course.startSlot).assertTrue();
      const raw2: Record<string, Object> = {
        'id': 'c2', 'name': '下界课', 'teacher': '', 'room': '', 'week_text': '1-16',
        'week_numbers': [1], 'exam_week_numbers': [], 'weekday': 0,
        'start_slot': -5, 'end_slot': -1, 'section_text': '1节', 'time_range': '08:00-08:45'
      };
      const course2: Course = Course.fromJson(raw2);
      expect(course2.weekday).assertEqual(1);
      expect(course2.startSlot).assertEqual(0);
      expect(course2.endSlot).assertEqual(0);
    });

    it('json_util_string_accepts_numbers', 0, () => {
      // BUG-018：数字字段按字符串兼容（对齐 Swift NSNumber）。
      expect(JsonUtil.string(2026)).assertEqual('2026');
      expect(JsonUtil.string(3.5)).assertEqual('3.5');
      expect(JsonUtil.string(undefined)).assertEqual('');
      expect(JsonUtil.string(null, 'd')).assertEqual('d');
      expect(JsonUtil.string(true, 'd')).assertEqual('d');
    });

    it('utf8_and_form_encoder_replace_lone_surrogates', 0, () => {
      // BUG-062：孤立代理对按 U+FFFD 编码（EF BF BD）。
      const lone: string = '\uD800';
      const encoded: number[] = Utf8.bytes(lone);
      expect(encoded.length).assertEqual(3);
      expect(encoded[0]).assertEqual(0xEF);
      expect(encoded[1]).assertEqual(0xBF);
      expect(encoded[2]).assertEqual(0xBD);
      const form: string = SJDFormURLEncoder.encode(new Map<string, string>([['k', lone]]));
      expect(form).assertEqual('k=%EF%BF%BD');
      // 合法代理对仍为 4 字节（不回归）。
      expect(Utf8.bytes('\uD83C\uDF93').length).assertEqual(4);
    });

    it('holiday_name_length_counts_code_points', 0, () => {
      // BUG-019：emoji（代理对）按 1 个码点计数。
      expect(HolidaySourceParser.codePointLength('春节')).assertEqual(2);
      expect(HolidaySourceParser.codePointLength('春节\uD83C\uDF89')).assertEqual(3);
      expect(HolidaySourceParser.codePointLength('a\uD83C\uDF93b')).assertEqual(3);
    });

    it('schedule_persistence_clear_wins_between_old_and_new_saves', 0,
      async (): Promise<void> => {
        const store: ControlledScheduleStore = new ControlledScheduleStore();
        const coordinator: SchedulePersistenceCoordinator =
          new SchedulePersistenceCoordinator(store);
        let oldGenerationCurrent: boolean = true;

        const oldSave: Promise<boolean> = coordinator.saveIfCurrent(
          persistenceSchedule('old-account-term'), (): boolean => oldGenerationCurrent);
        await store.firstSaveStarted;

        // 模拟 clear/account-change：先使旧 generation 失效，再把 clear 入队；
        // 新账号 save 必须排在 clear 后面。
        oldGenerationCurrent = false;
        const clearWork: Promise<void> = coordinator.clear();
        const newSave: Promise<boolean> = coordinator.saveIfCurrent(
          persistenceSchedule('new-account-term'), (): boolean => true);
        store.resumeFirstSave();

        const oldPublished: boolean = await oldSave;
        await clearWork;
        const newPublished: boolean = await newSave;

        expect(oldPublished).assertFalse();
        expect(newPublished).assertTrue();
        expect(store.clearCount).assertEqual(1);
        expect(store.stored?.termID ?? '').assertEqual('new-account-term');
      });
  });
}
