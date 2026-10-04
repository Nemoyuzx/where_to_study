// 独立于北邮教务凭据的 QMplus/Microsoft 自愿保存登录资料。
// ASSET 是秘密的唯一持久载体；授权journal仅记录非敏感recordID，
// 没有与本ASSET记录匹配的显式授权时自动填写默认关闭。
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

export function newQMPlusRecordID(): string {
  const bytes: Uint8Array = cryptoFramework.createRandom().generateRandomSync(16).data;
  let result: string = '';
  for (const value of bytes) {
    result += value.toString(16).padStart(2, '0');
  }
  bytes.fill(0);
  return result;
}

// ArkTS 的 JSON.stringify 输入必须是具名结构，不能给 Record 索引类型直接赋
// object literal；字段名与既有 ASSET schema 保持完全一致。
class QMPlusSavedLoginPayload {
  readonly schema_version: number = 1;
  readonly record_id: string;
  readonly account: string;
  readonly password: string;

  constructor(recordID: string, account: string, password: string) {
    this.record_id = recordID;
    this.account = account;
    this.password = password;
  }
}

export class QMPlusSavedLogin {
  readonly recordID: string;
  readonly account: string;
  readonly password: string;

  constructor(recordID: string, account: string, password: string) {
    const normalized: string = account.trim();
    // 必须绑定明确的登录标识，不能把密码填入同源的另一账户页面。
    if (!/^[0-9a-f]{32}$/.test(recordID) || normalized.length === 0 || normalized.length > 320 ||
      !/^[^\s@]+@[^\s@]+$/.test(normalized) ||
      password.length === 0 || password.length > 2048) {
      throw new Error('请填写有效的 QMplus 登录账号及密码。');
    }
    this.recordID = recordID;
    this.account = normalized;
    this.password = password;
  }

  toJsonText(): string {
    return JSON.stringify(new QMPlusSavedLoginPayload(this.recordID, this.account, this.password));
  }

  static fromJsonText(text: string): QMPlusSavedLogin {
    if (text.length > 8192) { throw new Error('QMplus 安全存储内容无效。'); }
    const parsed: Object = JSON.parse(text) as Object;
    if (parsed === null || Array.isArray(parsed) || typeof parsed !== 'object') {
      throw new Error('QMplus 安全存储内容无效。');
    }
    const record: Record<string, Object> = parsed as Record<string, Object>;
    if (Object.keys(record).length !== 4 || record['schema_version'] !== 1 ||
      typeof record['record_id'] !== 'string' || typeof record['account'] !== 'string' ||
      typeof record['password'] !== 'string') {
      throw new Error('QMplus 安全存储内容无效。');
    }
    return new QMPlusSavedLogin(record['record_id'] as string,
      record['account'] as string, record['password'] as string);
  }
}

export interface QMPlusSavedLoginStoring {
  load(): Promise<QMPlusSavedLogin | null>;
  save(login: QMPlusSavedLogin): Promise<void>;
  clear(): Promise<void>;
}

const ASSET_NOT_FOUND: number = 24000002;

export class AssetQMPlusSavedLoginStore implements QMPlusSavedLoginStoring {
  // 与 bupt-jwgl 资产完全隔离，不复用北邮密码或普通 Preferences。
  private static readonly alias: string = 'qmplus-microsoft-login-v1';

  private aliasAttributes(): asset.AssetMap {
    const attributes: asset.AssetMap = new Map();
    const encoder: util.TextEncoder = new util.TextEncoder();
    attributes.set(asset.Tag.ALIAS, encoder.encodeInto(AssetQMPlusSavedLoginStore.alias));
    return attributes;
  }

  async load(): Promise<QMPlusSavedLogin | null> {
    const query: asset.AssetMap = this.aliasAttributes();
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const matches: Array<asset.AssetMap> = await asset.query(query);
      if (matches.length === 0) { return null; }
      const secret: Uint8Array | undefined = matches[0].get(asset.Tag.SECRET) as Uint8Array;
      if (secret === undefined) { throw new Error('QMplus 安全存储内容无效。'); }
      try {
        return QMPlusSavedLogin.fromJsonText(util.TextDecoder.create('utf-8').decodeToString(secret));
      } finally {
        secret.fill(0);
      }
    } catch (e) {
      if ((e as BusinessError).code === ASSET_NOT_FOUND) { return null; }
      // 系统异常/解码失败均不含原始 secret、URL 或账户文本。
      throw new Error('无法读取 QMplus 安全存储。');
    }
  }

  async save(login: QMPlusSavedLogin): Promise<void> {
    const encoder: util.TextEncoder = new util.TextEncoder();
    const secret: Uint8Array = encoder.encodeInto(login.toJsonText());
    const update: asset.AssetMap = new Map();
    update.set(asset.Tag.SECRET, secret);
    try {
      try {
        await asset.update(this.aliasAttributes(), update);
      } catch (e) {
        if ((e as BusinessError).code !== ASSET_NOT_FOUND) {
          throw new Error('无法保存 QMplus 登录资料。');
        }
        const add: asset.AssetMap = this.aliasAttributes();
        add.set(asset.Tag.SECRET, secret);
        add.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
        try {
          await asset.add(add);
        } catch (e2) {
          throw new Error('无法保存 QMplus 登录资料。');
        }
      }
      const saved: QMPlusSavedLogin | null = await this.load();
      if (saved === null || saved.recordID !== login.recordID ||
        saved.account !== login.account || saved.password !== login.password) {
        throw new Error('QMplus 安全存储未能验证保存结果。');
      }
    } finally {
      secret.fill(0);
    }
  }

  async clear(): Promise<void> {
    try {
      await asset.remove(this.aliasAttributes());
    } catch (e) {
      if ((e as BusinessError).code === ASSET_NOT_FOUND) { return; }
      throw new Error('无法清除 QMplus 登录资料。');
    }
  }
}
