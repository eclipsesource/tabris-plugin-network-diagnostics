const {ScrollView, TextView, contentView} = require('tabris');

const scrollView = new ScrollView({layoutData: 'stretch'}).appendTo(contentView);
const output = new TextView({
  left: 16, top: 16, right: 16,
  font: '12px monospace',
  text: 'Enumerating interfaces…'
}).appendTo(scrollView);
const lines = [];

const diagnostics = new es.NetworkDiagnostics();

diagnostics.interfaces()
  .then(interfaces => show('interfaces', interfaces))
  .catch(error => show(`interfaces rejected (${error.code})`, error.message))
  .then(() => {
    diagnostics.dispose();
    show('dispose', 'NetworkDiagnostics disposed');
    return disposeWhilePending();
  });

// Disposing an object with a call in flight must reject that call with the
// `disposed` code — the only code path that produces it is the native destroy().
function disposeWhilePending() {
  const probe = new es.NetworkDiagnostics();
  const pending = probe.interfaces();
  probe.dispose();
  return pending
    .then(() => show('dispose check', 'unexpected: promise resolved after dispose'))
    .catch(error => show('dispose check', `rejected with code ${error.code}: ${error.message}`));
}

function show(title, value) {
  const text = `${title}:\n${typeof value === 'string' ? value : JSON.stringify(value, null, 2)}`;
  console.log(text);
  lines.unshift(text);
  output.text = lines.join('\n\n');
}
