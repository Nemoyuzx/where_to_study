import { connection, http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NetworkDiagnostics } from './NetworkDiagnostics';

export class CellularAssistError extends Error {
  readonly code: number;
  readonly cellularAttempted: boolean;
  constructor(code: number, cellularAttempted: boolean) {
    super(NetworkDiagnostics.userMessage(code));
    this.code = code;
    this.cellularAttempted = cellularAttempted;
  }
}

// AppModel updates this local setting after loading preferences. Default off.
// NetworkKit pathPreference applies only to this HTTP request; never setAppNet.
export class CellularAssist {
  static readonly preferenceKey: string = 'cellularAssistEnabled';
  static enabled: boolean = false;

  static canRetry(method: http.RequestMethod, enabled: boolean, wifi: boolean,
    code: number, consumed: boolean): boolean {
    return enabled && wifi && !consumed &&
      (method === http.RequestMethod.GET || method === http.RequestMethod.HEAD) &&
      NetworkDiagnostics.shouldRetryIPv4(code);
  }

  private static wifiActive(): boolean {
    if (!CellularAssist.enabled) { return false; }
    try {
      const network: connection.NetHandle = connection.getDefaultNetSync();
      const capabilities: connection.NetCapabilities = connection.getNetCapabilitiesSync(network);
      return capabilities.bearerTypes.includes(connection.NetBearType.BEARER_WIFI);
    } catch (_) { return false; }
  }

  static async request(client: http.HttpRequest, url: string,
    options: http.HttpRequestOptions, consumed: boolean = false,
    onFallbackStarted: (() => void) | null = null): Promise<http.HttpResponse> {
    const wifi: boolean = CellularAssist.wifiActive();
    try { return await client.request(url, options); }
    catch (e) {
      const error: BusinessError = e as BusinessError;
      const code: number = typeof error.code === 'number' ? error.code : 0;
      const method: http.RequestMethod = options.method ?? http.RequestMethod.GET;
      if (!CellularAssist.canRetry(method, CellularAssist.enabled, wifi, code, consumed)) {
        throw new CellularAssistError(code, false);
      }
      // Consume the caller's whole-request budget before starting the fallback.
      // A successful redirect response must not grant the next hop a new retry.
      if (onFallbackStarted !== null) { onFallbackStarted(); }
      const fallback: http.HttpRequest = http.createHttp();
      const previousPreference: http.PathPreference | undefined = options.pathPreference;
      try {
        // The OS chooses the actual route; this is a preference, not a promise
        // that the SIM/carrier/network supports cellular access.
        options.pathPreference = 'primaryCellular';
        return await fallback.request(url, options);
      } catch (retryError) {
        const retry: BusinessError = retryError as BusinessError;
        throw new CellularAssistError(typeof retry.code === 'number' ? retry.code : 0, true);
      } finally {
        options.pathPreference = previousPreference;
        fallback.destroy();
      }
    }
  }
}
