// 沙箱 JSON 文件的读取与原子写入辅助。
// 读取带大小上限，防止异常膨胀的缓存文件拖垮启动；
// 写入采用“临时文件 + rename”与 iOS 端 .atomic 写入对齐。
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// fs 的“文件不存在”错误码。
const FS_NO_SUCH_FILE: number = 13900002;

export class JsonFile {
  // 与 security-logic-review 的 RST-5 一致：本地课表与空教室缓存读取上限 8 MiB。
  static readonly defaultMaxBytes: number = 8 * 1024 * 1024;

  static async readText(path: string, maxBytes: number = JsonFile.defaultMaxBytes): Promise<string | null> {
    // 注意：模拟器上 fs.accessSync 对缺失文件不抛异常，因此统一用 statSync 判断存在性。
    let stat: fs.Stat;
    try {
      stat = fs.statSync(path);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code === FS_NO_SUCH_FILE) {
        return null;
      }
      hilog.error(0x0000, 'JsonFile', 'statSync failed for %{public}s code=%{public}d msg=%{public}s',
        path, err.code, err.message);
      throw new Error('无法读取本地缓存。');
    }
    if (stat.size > maxBytes) {
      throw new Error('本地缓存过大。');
    }
    try {
      const text: string = fs.readTextSync(path);
      if (text.length === 0) {
        return null;
      }
      return text;
    } catch (e) {
      throw new Error('无法读取本地缓存。');
    }
  }

  static async writeTextAtomic(path: string, content: string): Promise<void> {
    const dir: string = path.substring(0, path.lastIndexOf('/'));
    try {
      fs.mkdirSync(dir, true);
    } catch (e) {
      throw new Error('无法定位本地缓存目录。');
    }
    const tmpPath: string = path + '.tmp';
    let file: fs.File | null = null;
    try {
      file = fs.openSync(tmpPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.fsyncSync(file.fd);
      fs.closeSync(file);
      file = null;
      fs.renameSync(tmpPath, path);
    } catch (e) {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (closeError) {
          // 忽略关闭失败。
        }
      }
      try {
        fs.unlinkSync(tmpPath);
      } catch (unlinkError) {
        // 忽略临时文件清理失败。
      }
      throw new Error('无法写入本地缓存。');
    }
  }

  static async removeFile(path: string): Promise<void> {
    if (!JsonFile.existsSync(path)) {
      return;
    }
    try {
      fs.unlinkSync(path);
    } catch (e) {
      throw new Error('无法清除本地缓存。');
    }
  }

  static async removeDirectory(path: string): Promise<void> {
    if (!JsonFile.existsSync(path)) {
      return;
    }
    try {
      // 先清空目录内文件，再删除目录本身。
      const names: string[] = fs.listFileSync(path);
      for (const name of names) {
        const child: string = path + '/' + name;
        const childStat: fs.Stat = fs.statSync(child);
        if (childStat.isDirectory()) {
          JsonFile.removeDirectorySync(child);
        } else {
          fs.unlinkSync(child);
        }
      }
      fs.rmdirSync(path);
    } catch (e) {
      throw new Error('无法清除本地缓存。');
    }
  }

  private static existsSync(path: string): boolean {
    try {
      fs.statSync(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  private static removeDirectorySync(path: string): void {
    const names: string[] = fs.listFileSync(path);
    for (const name of names) {
      const child: string = path + '/' + name;
      const childStat: fs.Stat = fs.statSync(child);
      if (childStat.isDirectory()) {
        JsonFile.removeDirectorySync(child);
      } else {
        fs.unlinkSync(child);
      }
    }
    fs.rmdirSync(path);
  }
}
