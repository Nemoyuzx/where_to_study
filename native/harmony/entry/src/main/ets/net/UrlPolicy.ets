// URL 安全策略的纯字符串解析（无平台依赖）：
// 与 iOS 端 SJDNetworkPolicy.allows 的规则一致 —— 仅允许
// HTTPS、指定主机、443 端口（可省略）、且不含内嵌用户信息。
export class UrlPolicy {
  static allows(url: string, allowedHost: string): boolean {
    const schemeEnd: number = url.indexOf('://');
    if (schemeEnd < 0) {
      return false;
    }
    const scheme: string = url.substring(0, schemeEnd).toLowerCase();
    if (scheme !== 'https') {
      return false;
    }
    const rest: string = url.substring(schemeEnd + 3);
    const slash: number = rest.indexOf('/');
    const authority: string = slash < 0 ? rest : rest.substring(0, slash);
    if (authority.indexOf('@') >= 0) {
      return false;
    }
    const colon: number = authority.indexOf(':');
    const host: string = (colon < 0 ? authority : authority.substring(0, colon)).toLowerCase();
    if (host !== allowedHost) {
      return false;
    }
    const port: number = colon < 0 ? 443 : Number(authority.substring(colon + 1));
    return port === 443;
  }

  // 相对重定向地址解析：绝对地址直接使用，其余按基础地址解析。
  static resolveRedirect(base: string, location: string): string {
    if (location.startsWith('https://') || location.startsWith('http://')) {
      return location;
    }
    const schemeEnd: number = base.indexOf('://');
    const scheme: string = base.substring(0, schemeEnd);
    const rest: string = base.substring(schemeEnd + 3);
    const slash: number = rest.indexOf('/');
    const authority: string = slash < 0 ? rest : rest.substring(0, slash);
    if (location.startsWith('/')) {
      return scheme + '://' + authority + location;
    }
    const basePath: string = slash < 0 ? '/' : rest.substring(slash, rest.lastIndexOf('/') + 1);
    return scheme + '://' + authority + basePath + location;
  }
}
