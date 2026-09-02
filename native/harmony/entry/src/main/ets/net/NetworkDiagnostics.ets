// NetworkKit 错误的纯逻辑映射：既保留可报告的错误码，又不把 DNS、TLS、
// 超时、代理或请求参数错误全部伪装成同一个“无网络”提示。
export class NetworkDiagnostics {
  static shouldRetryIPv4(code: number): boolean {
    return code === 2300005 || code === 2300006 || code === 2300007 ||
      code === 2300028 || code === 2300052 || code === 2300055 || code === 2300056;
  }

  static userMessage(code: number): string {
    if (code === 2300005 || code === 2300006) {
      return '域名解析失败（网络错误 ' + code.toString() +
        '），请检查 DNS、代理或校园网认证后重试。';
    }
    if (code === 2300028) {
      return '连接服务器超时（网络错误 2300028），请切换网络或稍后重试。';
    }
    if (code === 2300058 || code === 2300059 || code === 2300060 || code === 2300077) {
      return '安全连接校验失败（网络错误 ' + code.toString() +
        '），请关闭网络代理、完成校园网认证或切换网络后重试。';
    }
    if (code === 401 || code === 2300001 || code === 2300003 || code === 2300998 ||
      code === 2300999) {
      return '网络请求配置异常（错误 ' + code.toString() + '），请向开发者反馈。';
    }
    if (code > 0) {
      return '无法连接服务器（网络错误 ' + code.toString() +
        '），请切换网络或完成校园网认证后重试。';
    }
    return '无法连接服务器（未知网络错误），请切换网络或完成校园网认证后重试。';
  }
}
