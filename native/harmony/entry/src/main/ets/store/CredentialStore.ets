// 与 iOS 端 CredentialStore.swift（Keychain）对应的鸿蒙实现：
// 使用 ASSET 系统安全存储（@kit.AssetStoreKit），等价于
// Keychain 的 kSecClassGenericPassword + AfterFirstUnlockThisDeviceOnly。
// 账号密码序列化为 JSON 后作为 SECRET 保存，绝不明文写入普通设置文件。
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

export class Credentials {
  account: string;
  password: string;

  constructor(account: string, password: string) {
    this.account = account;
    this.password = password;
  }

  toJsonText(): string {
    const out: Record<string, Object> = {};
    out['account'] = this.account;
    out['password'] = this.password;
    return JSON.stringify(out);
  }

  static fromJsonText(text: string): Credentials {
    const raw: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    return new Credentials(
      typeof raw['account'] === 'string' ? raw['account'] as string : '',
      typeof raw['password'] === 'string' ? raw['password'] as string : ''
    );
  }
}

export interface CredentialStoring {
  load(): Promise<Credentials | null>;

  save(credentials: Credentials): Promise<void>;

  clear(): Promise<void>;
}

// ASSET 在条目不存在时报错码 24000002（201 表示调用方无权限）。
const ASSET_NOT_FOUND: number = 24000002;

export class AssetCredentialStore implements CredentialStoring {
  private static readonly alias: string = 'bupt-jwgl';

  private static aliasAttr(): asset.AssetMap {
    const map: asset.AssetMap = new Map();
    const encoder: util.TextEncoder = new util.TextEncoder();
    map.set(asset.Tag.ALIAS, encoder.encodeInto(AssetCredentialStore.alias));
    return map;
  }

  private static secretAttr(credentials: Credentials): asset.AssetMap {
    const map: asset.AssetMap = new Map();
    const encoder: util.TextEncoder = new util.TextEncoder();
    map.set(asset.Tag.SECRET, encoder.encodeInto(credentials.toJsonText()));
    return map;
  }

  async load(): Promise<Credentials | null> {
    try {
      const results: Array<asset.AssetMap> = await asset.query(AssetCredentialStore.aliasAttr());
      if (results.length === 0) {
        return null;
      }
      const secret: Uint8Array | undefined = results[0].get(asset.Tag.SECRET) as Uint8Array;
      if (secret === undefined) {
        return null;
      }
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return Credentials.fromJsonText(decoder.decodeToString(secret));
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code === ASSET_NOT_FOUND) {
        return null;
      }
      throw new Error('系统安全存储操作失败（' + err.code.toString() + '）。');
    }
  }

  async save(credentials: Credentials): Promise<void> {
    const updateAttr: asset.AssetMap = AssetCredentialStore.secretAttr(credentials);
    updateAttr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      await asset.update(AssetCredentialStore.aliasAttr(), updateAttr);
      return;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code !== ASSET_NOT_FOUND) {
        throw new Error('系统安全存储操作失败（' + err.code.toString() + '）。');
      }
    }
    const addAttr: asset.AssetMap = AssetCredentialStore.aliasAttr();
    const encoder: util.TextEncoder = new util.TextEncoder();
    addAttr.set(asset.Tag.SECRET, encoder.encodeInto(credentials.toJsonText()));
    addAttr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      await asset.add(addAttr);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      throw new Error('系统安全存储操作失败（' + err.code.toString() + '）。');
    }
  }

  async clear(): Promise<void> {
    try {
      await asset.remove(AssetCredentialStore.aliasAttr());
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code === ASSET_NOT_FOUND) {
        return;
      }
      throw new Error('系统安全存储操作失败（' + err.code.toString() + '）。');
    }
  }
}
