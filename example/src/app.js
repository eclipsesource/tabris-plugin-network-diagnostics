const {Button, ScrollView, Stack, TextInput, TextView, app, contentView} = require('tabris');

const STAGES = [
  ['interfaces', 'Interfaces'],
  ['gateways', 'Gateways'],
  ['dnsServers', 'DNS servers'],
  ['gatewayPing', 'Gateway ping'],
  ['dnsServerCheck', 'DNS server check'],
  ['hostPing', 'Host ping'],
  ['httpProbe', 'HTTP probe']
];
const SECTIONS = {
  gateways: 'No gateways discovered',
  dnsServers: 'No DNS servers discovered',
  ping: 'No ping hosts configured',
  http: 'No HTTP hosts configured'
};

let diagnostics = createDiagnostics();
let report = null;
let settlements = 0;
const sectionLines = {};

const stack = new Stack({left: 16, top: 16, right: 16, spacing: 8})
  .appendTo(new ScrollView({layoutData: 'stretch'}).appendTo(contentView));

stack.append(
  heading('Targets'),
  new TextInput({id: 'pingHosts', type: 'multiline', message: 'Ping hosts', text: '1.1.1.1, 8.8.8.8', layoutData: 'stretchX'}),
  new TextInput({id: 'httpHosts', type: 'multiline', message: 'HTTP URLs', text: 'https://www.apple.com', layoutData: 'stretchX'}),
  new TextInput({id: 'dnsTestDomains', type: 'multiline', message: 'DNS test domains', text: 'apple.com', layoutData: 'stretchX'}),
  new TextInput({id: 'timeout', keyboard: 'number', message: 'Timeout per host (s)', text: '3', layoutData: 'stretchX'}),
  new TextInput({id: 'packets', keyboard: 'number', message: 'Ping packets', text: '3', layoutData: 'stretchX'}),
  new Button({id: 'run', text: 'Run diagnostics', layoutData: 'stretchX'}).onSelect(run),
  new Button({id: 'cancel', text: 'Cancel', enabled: false, layoutData: 'stretchX'}).onSelect(() => diagnostics.cancel()),
  new Button({id: 'recreate', text: 'Dispose and recreate', layoutData: 'stretchX'}).onSelect(recreate),
  new Button({id: 'share', text: 'Share JSON', enabled: false, layoutData: 'stretchX'}).onSelect(share),
  new TextView({id: 'settlements', text: 'settlements: 0', font: '12px monospace', layoutData: 'stretchX'}),
  heading('Progress'),
  ...STAGES.map(([stage, title]) => new TextView({id: `stage-${stage}`, text: `○ ${title}`, layoutData: 'stretchX'})),
  heading('Summary'),
  new TextView({id: 'summary', text: 'Not run yet', layoutData: 'stretchX'}),
  heading('Interfaces'),
  new TextView({id: 'interfaces', text: '—', font: '12px monospace', layoutData: 'stretchX'}),
  heading('Gateways'),
  new TextView({id: 'gateways', text: '—', font: '12px monospace', layoutData: 'stretchX'}),
  heading('DNS servers'),
  new TextView({id: 'dnsServers', text: '—', font: '12px monospace', layoutData: 'stretchX'}),
  heading('Ping'),
  new TextView({id: 'ping', text: '—', font: '12px monospace', layoutData: 'stretchX'}),
  heading('HTTP'),
  new TextView({id: 'http', text: '—', font: '12px monospace', layoutData: 'stretchX'})
);

function createDiagnostics() {
  const created = new es.NetworkDiagnostics();
  created.on('stageStarted', ({stage}) => setStage(stage, '◐'));
  created.on('stageFinished', ({stage}) => setStage(stage, '●'));
  created.on('gatewayResult', event => appendLine('gateways', `${event.address} via ${event.interfaceName || '?'} — ${pingSummary(event.ping)}`));
  created.on('dnsServerResult', event => appendLine('dnsServers', dnsServerSummary(event)));
  created.on('pingResult', event => appendLine('ping', `${event.host}${event.resolvedAddress ? ` (${event.resolvedAddress})` : ''} — ${pingSummary(event.outcome)}`));
  created.on('httpResult', event => appendLine('http', `${event.url} — ${httpSummary(event.outcome)}`));
  return created;
}

async function run() {
  const configuration = {
    pingHosts: list($('#pingHosts').first().text),
    httpHosts: list($('#httpHosts').first().text),
    dnsTestDomains: list($('#dnsTestDomains').first().text),
    timeoutPerHostSeconds: Number($('#timeout').first().text),
    pingPacketCount: Number($('#packets').first().text)
  };
  const started = Date.now();
  resetOutput();
  setRunning(true);
  try {
    report = await diagnostics.diagnose(configuration);
    settle(`resolved: ${report.summary.verdict}`);
    showReport(report, (Date.now() - started) / 1000);
  } catch (error) {
    settle(`rejected (${error.code}): ${error.message}`);
    $('#summary').first().text = `Run rejected (${error.code}): ${error.message}`;
  } finally {
    setRunning(false);
  }
}

function recreate() {
  diagnostics.dispose();
  diagnostics = createDiagnostics();
  console.log('NetworkDiagnostics object recreated');
}

async function share() {
  try {
    await app.share({title: 'Network diagnosis', text: JSON.stringify(report, null, 2)});
  } catch (error) {
    console.log(`share failed: ${error.message}`);
  }
}

function showReport(result, elapsedSeconds) {
  $('#summary').first().text = `${result.summary.message}\n\nFinished in ${result.durationSeconds.toFixed(2)} s (JS: ${elapsedSeconds.toFixed(2)} s)`;
  $('#interfaces').first().text = result.interfaces.state === 'found'
    ? result.interfaces.items.map(iface => `${iface.name}${iface.isUp ? '' : ' (down)'}: ${[...iface.ipv4Addresses, ...iface.ipv6Addresses].join(', ') || 'no address'}`).join('\n') || 'No interfaces'
    : `unavailable: ${result.interfaces.reason}`;
  for (const [section, emptyText] of Object.entries(SECTIONS)) {
    if (!sectionLines[section].length) {
      const discovery = result[section === 'ping' ? 'pingResults' : section === 'http' ? 'httpResults' : section];
      $(`#${section}`).first().text = discovery && discovery.state === 'unavailable' ? `unavailable: ${discovery.reason}` : emptyText;
    }
  }
  $('#share').first().enabled = true;
}

function resetOutput() {
  report = null;
  $('#share').first().enabled = false;
  $('#summary').first().text = 'Running…';
  $('#interfaces').first().text = '—';
  for (const [stage] of STAGES) {
    setStage(stage, '○');
  }
  for (const section of Object.keys(SECTIONS)) {
    sectionLines[section] = [];
    $(`#${section}`).first().text = 'Waiting…';
  }
}

function setRunning(running) {
  $('#run').first().enabled = !running;
  $('#cancel').first().enabled = running;
}

function setStage(stage, glyph) {
  const title = STAGES.find(([name]) => name === stage)[1];
  $(`#stage-${stage}`).first().text = `${glyph} ${title}`;
}

function appendLine(section, line) {
  sectionLines[section].push(line);
  $(`#${section}`).first().text = sectionLines[section].join('\n');
}

function settle(text) {
  settlements += 1;
  $('#settlements').first().text = `settlements: ${settlements} — last: ${text}`;
  console.log(`diagnose ${text}`);
}

function list(text) {
  return text.split(/[,\n]/).map(entry => entry.trim()).filter(entry => entry.length > 0);
}

function heading(text) {
  return new TextView({text, font: 'bold 16px', layoutData: 'stretchX'});
}

function pingSummary(outcome) {
  switch (outcome.state) {
    case 'reachable':
      return `avg ${outcome.avgRttMs.toFixed(1)} ms, loss ${outcome.packetLossPercent.toFixed(0)}%`;
    case 'unreachable':
      return `no reply to ${outcome.sentPackets} packets`;
    case 'resolutionFailed':
      return `resolution failed: ${outcome.reason}`;
    default:
      return `failed: ${outcome.reason}`;
  }
}

function httpSummary(outcome) {
  if (outcome.state === 'response') {
    return `HTTP ${outcome.statusCode} in ${outcome.latencyMs.toFixed(0)} ms`;
  }
  return outcome.description ? `${outcome.failure}: ${outcome.description}` : outcome.failure;
}

function querySummary(outcome) {
  switch (outcome.state) {
    case 'answered':
      return `${outcome.responseCode}${outcome.addresses.length ? ` → ${outcome.addresses.join(', ')}` : ''} (${outcome.latencyMs.toFixed(0)} ms)`;
    case 'timedOut':
      return 'timed out';
    default:
      return `failed: ${outcome.reason}`;
  }
}

function dnsServerSummary(server) {
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
    setSelfcheck(`dispose mid-run rejected with code ${error.code}: ${error.message}`);
  }
})();

function setSelfcheck(text) {
  console.log(`self-check: ${text}`);
  new TextView({id: 'selfcheck', text: `self-check: ${text}`, font: '12px monospace', layoutData: 'stretchX'})
    .insertAfter($('#settlements').first());
}
