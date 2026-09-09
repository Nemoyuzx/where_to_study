// 每条归档流按调用顺序写入；清除使旧任务失效，并排在已开始的写入之后。
// 只清理历史错误路径，不读取它，避免恢复旧账号或已清除的私密课表。
export interface WidgetFileOperations {
  write(path: string, text: string): Promise<void>;
  remove(path: string): Promise<void>;
}

export class WidgetFileQueue {
  private generation: number = 0;
  private pending: Promise<void> = Promise.resolve();
  private readonly operations: WidgetFileOperations;

  constructor(operations: WidgetFileOperations) {
    this.operations = operations;
  }

  replace(path: string, obsoletePath: string, text: string | null): Promise<boolean> {
    const generation: number = ++this.generation;
    let current: boolean = false;
    const work: Promise<void> = this.pending.catch(() => {}).then(async (): Promise<void> => {
      if (generation !== this.generation) {
        return;
      }
      await this.operations.remove(obsoletePath);
      if (generation !== this.generation) {
        return;
      }
      if (text === null) {
        await this.operations.remove(path);
      } else {
        await this.operations.write(path, text);
      }
      current = generation === this.generation;
    });
    this.pending = work;
    return work.then((): boolean => current);
  }
}
