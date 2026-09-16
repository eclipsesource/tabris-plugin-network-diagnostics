// The global `es` namespace comes from the plugin's types/index.d.ts, listed
// under compilerOptions.types in tsconfig.json. The runtime object itself is
// installed by Cordova through the <plugin> entry in cordova/config.xml; see
// README.md for the two channels.
import {app, Button, Composite, contentView, device, ScrollView, Stack, TextInput, TextView} from 'tabris';

const TARGETS_STORAGE_KEY = 'networkDiagnostics.targets';
const LABEL_COLUMN_WIDTH = 200;
const SIDE_BY_SIDE_MIN_WIDTH = 600;

type FieldId = 'pingHosts' | 'httpHosts' | 'dnsTestDomains' | 'timeout' | 'packets';
type Section = 'gateways' | 'dnsServers' | 'ping' | 'http';

interface FieldDefinition {
  id: FieldId;
  label: string;
  multiline: boolean;
  text: string;
}

const FIELDS: FieldDefinition[] = [
  {id: 'pingHosts', label: 'Ping hosts', multiline: true, text: '1.1.1.1, 8.8.8.8'},
  {id: 'httpHosts', label: 'HTTP URLs', multiline: true, text: 'https://www.apple.com'},
  {id: 'dnsTestDomains', label: 'DNS test domains', multiline: true, text: 'apple.com'},
  {id: 'timeout', label: 'Timeout per host (s)', multiline: false, text: '3'},
  {id: 'packets', label: 'Ping packets', multiline: false, text: '3'}
];
const STAGES: Array<[es.Stage, string]> = [
  ['interfaces', 'Interfaces'],
  ['gateways', 'Gateways'],
  ['dnsServers', 'DNS servers'],
  ['gatewayPing', 'Gateway ping'],
  ['dnsServerCheck', 'DNS server check'],
  ['hostPing', 'Host ping'],
  ['httpProbe', 'HTTP probe']
];
const SECTIONS: Record<Section, string> = {
  gateways: 'No gateways discovered',
  dnsServers: 'No DNS servers discovered',
  ping: 'No ping hosts configured',
  http: 'No HTTP hosts configured'
};

let diagnostics = createDiagnostics();
let report: es.Report | null = null;
let settlements = 0;
const sectionLines: Record<Section, string[]> = {gateways: [], dnsServers: [], ping: [], http: []};
const storedTargets = readStoredTargets();

const labels = {} as Record<FieldId, TextView>;
const inputs = {} as Record<FieldId, TextInput>;
const stageViews = {} as Record<es.Stage, TextView>;
const sectionViews = {} as Record<Section, TextView>;

const runButton = new Button({id: 'run', text: 'Run diagnostics', layoutData: 'stretchX'}).onSelect(run);
const cancelButton = new Button({id: 'cancel', text: 'Cancel', enabled: false, layoutData: 'stretchX'})
  .onSelect(() => diagnostics.cancel());
const shareButton = new Button({id: 'share', text: 'Share JSON', enabled: false, layoutData: 'stretchX'}).onSelect(share);
const settlementsView = new TextView({id: 'settlements', text: 'settlements: 0', font: '12px monospace', layoutData: 'stretchX'});
const summaryView = new TextView({id: 'summary', text: 'Not run yet', layoutData: 'stretchX'});
const interfacesView = new TextView({id: 'interfaces', text: '—', font: '12px monospace', layoutData: 'stretchX'});

const stack = new Stack({left: 16, top: 16, right: 16, spacing: 8})
  .appendTo(new ScrollView({layoutData: 'stretch'}).appendTo(contentView));

stack.append(
  heading('Targets'),
  ...FIELDS.map(field),
  runButton,
  cancelButton,
  new Button({id: 'recreate', text: 'Dispose and recreate', layoutData: 'stretchX'}).onSelect(recreate),
  shareButton,
  settlementsView,
  heading('Progress'),
  ...STAGES.map(([stage, title]) => stageViews[stage] = new TextView({id: `stage-${stage}`, text: `○ ${title}`, layoutData: 'stretchX'})),
  heading('Summary'),
  summaryView,
  heading('Interfaces'),
  interfacesView,
  heading('Gateways'),
  sectionView('gateways'),
  heading('DNS servers'),
  sectionView('dnsServers'),
  heading('Ping'),
  sectionView('ping'),
  heading('HTTP'),
  sectionView('http')
);

contentView.onResize(({width}) => applyFieldLayout(width));
// contentView has no width yet before the first layout pass, so the initial
// choice comes from the screen.
applyFieldLayout(device.screenWidth);

function createDiagnostics(): es.NetworkDiagnostics {
  const created = new es.NetworkDiagnostics();
  created.on('stageStarted', ({stage}) => setStage(stage, '◐'));
  created.on('stageFinished', ({stage}) => setStage(stage, '●'));
  created.on('gatewayResult', event => appendLine('gateways', `${event.address} via ${event.interfaceName || '?'} — ${pingSummary(event.ping)}`));
  created.on('dnsServerResult', event => appendLine('dnsServers', dnsServerSummary(event)));
  created.on('pingResult', event => appendLine('ping', `${event.host}${event.resolvedAddress ? ` (${event.resolvedAddress})` : ''} — ${pingSummary(event.outcome)}`));
  created.on('httpResult', event => appendLine('http', `${event.url} — ${httpSummary(event.outcome)}`));
  return created;
}

async function run(): Promise<void> {
  const configuration: es.DiagnoseConfiguration = {
    pingHosts: list(inputs.pingHosts.text),
    httpHosts: list(inputs.httpHosts.text),
    dnsTestDomains: list(inputs.dnsTestDomains.text),
    timeoutPerHostSeconds: Number(inputs.timeout.text),
    pingPacketCount: Number(inputs.packets.text)
  };
  const started = Date.now();
  resetOutput();
  setRunning(true);
  try {
    report = await diagnostics.diagnose(configuration);
    settle(`resolved: ${report.summary.verdict}`);
    showReport(report, (Date.now() - started) / 1000);
  } catch (error) {
    const {code, message} = error as es.NetworkDiagnosticsError;
    settle(`rejected (${code}): ${message}`);
    summaryView.text = `Run rejected (${code}): ${message}`;
  } finally {
    setRunning(false);
  }
}

function recreate(): void {
  diagnostics.dispose();
  diagnostics = createDiagnostics();
  console.log('NetworkDiagnostics object recreated');
}

async function share(): Promise<void> {
  try {
    await app.share({title: 'Network diagnosis', text: JSON.stringify(report, null, 2)});
  } catch (error) {
    console.log(`share failed: ${(error as Error).message}`);
  }
}

function showReport(result: es.Report, elapsedSeconds: number): void {
  summaryView.text = `${result.summary.message}\n\nFinished in ${result.durationSeconds.toFixed(2)} s (JS: ${elapsedSeconds.toFixed(2)} s)`;
  interfacesView.text = result.interfaces.state === 'found'
    ? result.interfaces.items.map(iface => `${iface.name}${iface.isUp ? '' : ' (down)'}: ${[...iface.ipv4Addresses, ...iface.ipv6Addresses].join(', ') || 'no address'}`).join('\n') || 'No interfaces'
    : `unavailable: ${result.interfaces.reason}`;
  for (const section of Object.keys(SECTIONS) as Section[]) {
    if (!sectionLines[section].length) {
      const discovery = discoveryOf(result, section);
      sectionViews[section].text = discovery && discovery.state === 'unavailable' ? `unavailable: ${discovery.reason}` : SECTIONS[section];
    }
  }
  shareButton.enabled = true;
}

// Only the two discovered sections can be unavailable as a whole; the ping and
// HTTP sections are plain lists that are simply empty when nothing was configured.
function discoveryOf(result: es.Report, section: Section): es.Discovery<unknown> | null {
  switch (section) {
    case 'gateways':
      return result.gateways;
    case 'dnsServers':
      return result.dnsServers;
    default:
      return null;
  }
}

function resetOutput(): void {
  report = null;
  shareButton.enabled = false;
  summaryView.text = 'Running…';
  interfacesView.text = '—';
  for (const [stage] of STAGES) {
    setStage(stage, '○');
  }
  for (const section of Object.keys(SECTIONS) as Section[]) {
    sectionLines[section] = [];
    sectionViews[section].text = 'Waiting…';
  }
}

function setRunning(running: boolean): void {
  runButton.enabled = !running;
  cancelButton.enabled = running;
}

function setStage(stage: es.Stage, glyph: string): void {
  const [, title] = STAGES.find(([name]) => name === stage) ?? [stage, stage];
  stageViews[stage].text = `${glyph} ${title}`;
}

function appendLine(section: Section, line: string): void {
  sectionLines[section].push(line);
  sectionViews[section].text = sectionLines[section].join('\n');
}

function settle(text: string): void {
  settlements += 1;
  settlementsView.text = `settlements: ${settlements} — last: ${text}`;
  console.log(`diagnose ${text}`);
}

function list(text: string): string[] {
  return text.split(/[,\n]/).map(entry => entry.trim()).filter(entry => entry.length > 0);
}

function heading(text: string): TextView {
  return new TextView({text, font: 'bold 16px', layoutData: 'stretchX'});
}

function sectionView(section: Section): TextView {
  return sectionViews[section] = new TextView({id: section, text: '—', font: '12px monospace', layoutData: 'stretchX'});
}

// Every target input carries a visible label: the placeholder disappears as
// soon as a field holds a value, so a filled-in form would otherwise give no
// clue which target is which.
function field({id, label, multiline, text}: FieldDefinition): Composite {
  labels[id] = new TextView({id: `label-${id}`, text: label});
  inputs[id] = new TextInput({
    id,
    type: multiline ? 'multiline' : 'default',
    keyboard: multiline ? 'default' : 'number',
    text: storedTargets[id] ?? text
  }).onTextChanged(storeTargets);
  return new Composite({layoutData: 'stretchX'}).append(labels[id], inputs[id]);
}

// Label beside the input when there is room for it, above it when there is not.
// Rotation and Split View both change the available width, so the breakpoint is
// re-evaluated on every resize instead of being fixed at startup. Only layout
// data changes here — the inputs are never rebuilt, so nothing typed into them
// is lost when the layout flips.
function applyFieldLayout(width: number): void {
  const besideInput = width >= SIDE_BY_SIDE_MIN_WIDTH;
  for (const {id} of FIELDS) {
    labels[id].layoutData = besideInput
      ? {left: 0, width: LABEL_COLUMN_WIDTH, centerY: 0}
      : {left: 0, right: 0, top: 0};
    inputs[id].layoutData = besideInput
      ? {left: LABEL_COLUMN_WIDTH + 8, right: 0, top: 0}
      : {left: 0, right: 0, top: [labels[id], 2]};
  }
}

// Targets outlive a restart, so testing against hosts on the device's own LAN
// does not mean typing them in again every launch. `localStorage` is Tabris's
// persistent key-value store; on iOS it lands in Documents/tabris.ClientStore.
function readStoredTargets(): Partial<Record<FieldId, string>> {
  try {
    return JSON.parse(localStorage.getItem(TARGETS_STORAGE_KEY) ?? 'null') || {};
  } catch (error) {
    console.error(`stored targets are unreadable, falling back to the defaults: ${(error as Error).message}`);
    return {};
  }
}

function storeTargets(): void {
  const targets: Partial<Record<FieldId, string>> = {};
  for (const {id} of FIELDS) {
    targets[id] = inputs[id].text;
  }
  localStorage.setItem(TARGETS_STORAGE_KEY, JSON.stringify(targets));
}

function pingSummary(outcome: es.PingOutcome): string {
  switch (outcome.state) {
    case 'reachable':
      return `avg ${outcome.avgRttMs.toFixed(1)} ms, loss ${outcome.packetLossPercent.toFixed(0)}%`;
    case 'unreachable':
      return `no reply to ${outcome.sentPackets} packets`;
    case 'resolutionFailed':
      return `resolution failed: ${outcome.reason}`;
    case 'failed':
      return `failed: ${outcome.reason}`;
  }
}

function httpSummary(outcome: es.HttpOutcome): string {
  if (outcome.state === 'response') {
    return `HTTP ${outcome.statusCode} in ${outcome.latencyMs.toFixed(0)} ms`;
  }
  return outcome.failure === 'other' ? `${outcome.failure}: ${outcome.description}` : outcome.failure;
}

function querySummary(outcome: es.DnsQueryOutcome): string {
  switch (outcome.state) {
    case 'answered':
      return `${outcome.responseCode}${outcome.addresses.length ? ` → ${outcome.addresses.join(', ')}` : ''} (${outcome.latencyMs.toFixed(0)} ms)`;
    case 'timedOut':
      return 'timed out';
    case 'failed':
      return `failed: ${outcome.reason}`;
  }
}

function dnsServerSummary(server: es.DnsServerReport): string {
  const queries = server.queries.map(query => `\n    ${query.domain}: ${querySummary(query.outcome)}`).join('');
  return `${server.address} — ${pingSummary(server.ping)}${queries}`;
}

// Launch-time self-check: disposing an object with a diagnosis in flight must
// reject that promise with the `disposed` code — the only path that produces it
// is the native destroy(). Rendered into #selfcheck so a screenshot proves it.
(async () => {
  const probe = new es.NetworkDiagnostics();
  const pending = probe.diagnose({pingHosts: ['192.0.2.1'], timeoutPerHostSeconds: 30});
  probe.dispose();
  try {
    await pending;
    setSelfcheck('unexpected: dispose did not reject the running diagnose');
  } catch (error) {
    const {code, message} = error as es.NetworkDiagnosticsError;
    setSelfcheck(`dispose mid-run rejected with code ${code}: ${message}`);
  }
})();

function setSelfcheck(text: string): void {
  console.log(`self-check: ${text}`);
  new TextView({id: 'selfcheck', text: `self-check: ${text}`, font: '12px monospace', layoutData: 'stretchX'})
    .insertAfter(settlementsView);
}
