// Type declarations for the JavaScript module in www/NetworkDiagnostics.js.
// The runtime object is installed by Cordova as the global `es.NetworkDiagnostics`
// (see the clobbers target in plugin.xml), so everything is declared in the
// global namespace `es`. The file is a module (`export {}`), so an app pulls
// the declarations in with `import 'tabris-plugin-network-diagnostics';`.
// Result shapes mirror the Tabris objects built in
// Sources/NetworkDiagnostics/Bridge/*+Tabris.swift and are documented in README.md.
import {EventObject, NativeObject} from 'tabris';

declare global {
  namespace es {

    class NetworkDiagnostics extends NativeObject {
      constructor();
      interfaces(): Promise<NetworkInterface[]>;
      gateways(options?: GatewaysOptions): Promise<Gateway[]>;
      dnsServers(): Promise<string[]>;
      ping(host: string, options?: PingOptions): Promise<PingResult>;
      dnsQuery(domain: string, options: DnsQueryOptions): Promise<DnsQueryResult>;
      http(url: string, options?: HttpOptions): Promise<HttpResult>;
      diagnose(configuration?: DiagnoseConfiguration): Promise<Report>;
      cancel(): Promise<null>;
      dispose(): void;
      isDisposed(): boolean;
      on<T extends keyof NetworkDiagnosticsEvents>(
        type: T,
        listener: (event: NetworkDiagnosticsEvents[T]) => void,
        context?: object
      ): this;
      on(type: string, listener: (event: EventObject<NativeObject>) => any, context?: object): this;
      on(listeners: NetworkDiagnosticsListeners): this;
      off<T extends keyof NetworkDiagnosticsEvents>(
        type: T,
        listener: (event: NetworkDiagnosticsEvents[T]) => void,
        context?: object
      ): this;
      off(type: string, listener: (event: EventObject<NativeObject>) => void, context?: object): this;
      off(listeners: NetworkDiagnosticsListeners): this;
      once<T extends keyof NetworkDiagnosticsEvents>(
        type: T,
        listener: (event: NetworkDiagnosticsEvents[T]) => void,
        context?: object
      ): this;
      once(type: string, listener: (event: EventObject<NativeObject>) => any, context?: object): this;
      once(listeners: NetworkDiagnosticsListeners): this;
    }

    interface GatewaysOptions {
      timeoutSeconds?: number;
    }

    interface PingOptions {
      packetCount?: number;
      timeoutSeconds?: number;
    }

    interface DnsQueryOptions {
      server: string;
      timeoutSeconds?: number;
    }

    type HttpMethod = 'HEAD' | 'GET';

    interface HttpOptions {
      method?: HttpMethod;
      timeoutSeconds?: number;
    }

    interface DiagnoseConfiguration {
      pingHosts?: string[];
      httpHosts?: string[];
      dnsTestDomains?: string[];
      timeoutPerHostSeconds?: number;
      pingPacketCount?: number;
      httpMethod?: HttpMethod;
    }

    // Every rejected promise carries one of these codes; probe failures are never
    // rejections but `state` values inside an outcome.
    type ErrorCode = 'invalidParameter' | 'unavailable' | 'alreadyRunning' | 'cancelled' | 'disposed';

    interface NetworkDiagnosticsError extends Error {
      code: ErrorCode;
    }

    interface NetworkInterface {
      name: string;
      ipv4Addresses: string[];
      ipv6Addresses: string[];
      isUp: boolean;
      isLoopback: boolean;
    }

    interface Gateway {
      address: string;
      interfaceName: string | null;
    }

    type PingOutcome =
      | {
        state: 'reachable';
        sentPackets: number;
        receivedPackets: number;
        minRttMs: number;
        avgRttMs: number;
        maxRttMs: number;
        packetLossPercent: number;
      }
      | {state: 'unreachable'; sentPackets: number}
      | {state: 'resolutionFailed'; reason: string}
      | {state: 'failed'; reason: string};

    interface PingResult {
      host: string;
      resolvedAddress: string | null;
      outcome: PingOutcome;
    }

    type DnsResponseCode =
      | 'noError'
      | 'formatError'
      | 'serverFailure'
      | 'nameError'
      | 'notImplemented'
      | 'refused'
      | 'other';

    type DnsQueryOutcome =
      | {state: 'answered'; responseCode: DnsResponseCode; rcode: number; addresses: string[]; latencyMs: number}
      | {state: 'timedOut'}
      | {state: 'failed'; reason: string};

    interface DnsQueryResult {
      domain: string;
      server: string;
      outcome: DnsQueryOutcome;
      isResolved: boolean;
    }

    type HttpFailure =
      | 'dnsResolutionFailed'
      | 'tlsHandshakeFailed'
      | 'connectionRefused'
      | 'timedOut'
      | 'networkUnavailable'
      | 'other';

    type HttpOutcome =
      | {state: 'response'; statusCode: number; latencyMs: number}
      | {state: 'failure'; failure: Exclude<HttpFailure, 'other'>}
      | {state: 'failure'; failure: 'other'; description: string};

    interface HttpResult {
      url: string;
      outcome: HttpOutcome;
    }

    type Stage =
      | 'interfaces'
      | 'gateways'
      | 'dnsServers'
      | 'gatewayPing'
      | 'dnsServerCheck'
      | 'hostPing'
      | 'httpProbe';

    type Discovery<Item> =
      | {state: 'found'; items: Item[]}
      | {state: 'unavailable'; reason: string};

    interface GatewayReport extends Gateway {
      ping: PingOutcome;
    }

    interface DnsServerQuery {
      domain: string;
      outcome: DnsQueryOutcome;
      isResolved: boolean;
    }

    interface DnsServerReport {
      address: string;
      ping: PingOutcome;
      queries: DnsServerQuery[];
    }

    type Verdict =
      | 'healthy'
      | 'noActiveInterface'
      | 'gatewayUnreachable'
      | 'dnsResolutionFailing'
      | 'remoteHostsUnreachable'
      | 'partialConnectivity'
      | 'inconclusive';

    type Summary =
      | {verdict: Exclude<Verdict, 'inconclusive'>; message: string}
      | {verdict: 'inconclusive'; message: string; reason: string};

    interface Report {
      startedAt: string;
      durationSeconds: number;
      interfaces: Discovery<NetworkInterface>;
      gateways: Discovery<GatewayReport>;
      dnsServers: Discovery<DnsServerReport>;
      pingResults: PingResult[];
      httpResults: HttpResult[];
      summary: Summary;
    }

    interface StageEvent extends EventObject<NetworkDiagnostics> {
      stage: Stage;
    }

    interface GatewayResultEvent extends EventObject<NetworkDiagnostics>, GatewayReport {}

    interface DnsServerResultEvent extends EventObject<NetworkDiagnostics>, DnsServerReport {}

    interface PingResultEvent extends EventObject<NetworkDiagnostics>, PingResult {}

    interface HttpResultEvent extends EventObject<NetworkDiagnostics>, HttpResult {}

    interface NetworkDiagnosticsEvents {
      stageStarted: StageEvent;
      stageFinished: StageEvent;
      gatewayResult: GatewayResultEvent;
      dnsServerResult: DnsServerResultEvent;
      pingResult: PingResultEvent;
      httpResult: HttpResultEvent;
    }

    type NetworkDiagnosticsListeners = {
      [T in keyof NetworkDiagnosticsEvents]?: (event: NetworkDiagnosticsEvents[T]) => void;
    };

  }
}

export {};
