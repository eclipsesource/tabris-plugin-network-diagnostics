const {Button, ScrollView, Stack, TextView, contentView} = require('tabris');

const diagnostics = new es.NetworkDiagnostics();
const lines = [];

const checks = [
  ['interfaces', () => diagnostics.interfaces()],
  ['gateways', () => diagnostics.gateways()],
  ['dnsServers', () => diagnostics.dnsServers()],
  ['ping 127.0.0.1', () => diagnostics.ping('127.0.0.1', {packetCount: 2})],
  ['ping (empty host)', () => diagnostics.ping('')],
  ['dnsQuery apple.com', async () => {
    const [server] = await diagnostics.dnsServers();
    return diagnostics.dnsQuery('apple.com', {server});
  }],
  ['http https://www.apple.com', () => diagnostics.http('https://www.apple.com')],
  ['http https://127.0.0.1:1/', () => diagnostics.http('https://127.0.0.1:1/')]
];

const scrollView = new ScrollView({layoutData: 'stretch'}).appendTo(contentView);
const stack = new Stack({left: 16, top: 16, right: 16, spacing: 8}).appendTo(scrollView);

stack.append(
  new Button({id: 'runAll', text: 'Run all checks'}).onSelect(runAll),
  ...checks.map(([title, run]) => new Button({text: title}).onSelect(() => runCheck(title, run)))
);
const output = new TextView({id: 'output', font: '12px monospace', text: 'Idle'}).appendTo(stack);

async function runCheck(title, run) {
  try {
    show(title, await run());
  } catch (error) {
    show(`${title} rejected (${error.code})`, error.message);
  }
}

async function runAll() {
  lines.length = 0;
  for (const [title, run] of checks) {
    await runCheck(title, run);
  }
  show('all checks', 'done');
}

function show(title, value) {
  const text = `${title}:\n${typeof value === 'string' ? value : JSON.stringify(value, null, 2)}`;
  console.log(text);
  lines.unshift(text);
  output.text = lines.join('\n\n');
}

runAll();
