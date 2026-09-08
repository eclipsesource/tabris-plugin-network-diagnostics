# Every promise settlement schedules a Tabris flush on a timer

Date: 2026-09-08

## Context

Tabris does not send JavaScript-to-native operations as they are written. The
JavaScript runtime appends them to `NativeBridge.$operations` and ships the
whole buffer when `tabris.flush()` runs (`tabris.js`, `Tabris.prototype.flush`:
`trigger('tick'); trigger('flush'); clearCache(); _nativeBridge.flush()`).

Two of the three ways native code and JavaScript meet flush by themselves:

- the **event** path — `Tabris.prototype._notify`, which `fireEventNamed:`
  reaches, ends its body with `this.flush()`;
- the **call** path in the other direction — `NativeBridge.prototype.call` and
  `.get` flush *before* forwarding to native.

The **callback** path does not. `createNativeCallback`, the only helper in the
runtime that appends a flush to a JavaScript function handed to native, is
applied in exactly two places: the timer callback and the canvas
`getImageData` success callback. A function a plugin passes through
`_nativeCall` is a plain function; `JSFunctionValue.callWithParameters:` calls
straight into JavaScriptCore and returns.

This plugin settles every promise through such a callback. Observed on the
simulator: a `diagnose()` run finished natively in 0.5 s, the report was
correct, and the progress events had rendered live — but the summary still read
`Running…`, the interface list still read `—`, `Run diagnostics` was still
disabled and the settlement counter still read `0`. Everything the `await`
continuation had written was in the buffer. Tapping *Cancel* issued a
`_nativeCall`, whose pre-call flush shipped the backlog, and the whole interface
jumped forward at once — displaying the true 0.5 s duration many seconds late.

Every promise-returning method was affected, not only `diagnose()`.

## Decision

`www/NetworkDiagnostics.js` schedules a flush on a timer at the end of every
completion callback:

```js
function flushAfterContinuations() {
  setTimeout(() => tabris.flush(), 0);
}
```

The timer is the substance of the decision, and it was settled by measurement
rather than by reasoning about JavaScriptCore.

`resolve(value)` does not run the caller's continuation; it *schedules* it as a
microtask. A flush that runs before that microtask ships nothing. A timer
callback is a macrotask, so the language guarantees it runs after the microtask
queue has drained — the first moment at which every write the continuation made
is in the buffer. Tabris timers are native-backed and their callbacks go through
`createNativeCallback`, so the trailing flush would happen even without the
explicit call; the call stays because relying on that wrapper's side effect
would be invisible to the next reader.

The whole fix lives in the JavaScript module. `src/ios/` keeps its existing
shape: parse, start work, deliver on the main thread.

## Consequences

- A settlement reaches the interface one run-loop turn after it reaches
  JavaScript. Against a diagnosis measured in seconds this is not observable.
- One native timer round trip per settled call.
- The mechanism is invisible to the plugin's users; the public promise contract
  is unchanged.
- Verification is the example app on the simulator. `src/ios/` and the widget
  layer are out of reach of `swift test`, so the host suite asserts the shape of
  the fix — `PluginManifestTests` requires the flush to be scheduled on a timer —
  and `scripts/example-clickthrough.sh` asserts the behaviour. That script polls
  the accessibility tree, which does not enter JavaScript and therefore cannot
  mask the defect by flushing on its own.

## Rejected alternatives

The first two were implemented and **measured to fail** on an iPad Pro 13-inch
simulator running the example app; they are recorded because both are the
obvious thing to try.

- **Flushing natively straight after `JSFunctionValue.callWithParameters:`
  returns**, with the flush closure passed through the call parameters
  alongside `completion`. The reasoning was that JavaScriptCore drains
  microtasks when the outermost host-to-JavaScript entry unwinds, so the
  continuation would already have run. It does not, or not there: with this in
  place the console showed `diagnose resolved: healthy` while the same capture
  still showed `Summary: Running…` and `settlements: 0`. The flush ran before
  the continuation and shipped nothing.
- **Flushing inside the JavaScript completion callback**, mirroring
  `createNativeCallback`. Same ordering, same result, for the same reason.
- **Queuing the flush as a microtask** (`Promise.resolve().then(...)`). The
  continuation may enqueue further microtasks after it, so the ordering is not
  guaranteed. The macrotask boundary is the one the language actually promises.
- **Deferring the settlement itself into the timer** rather than the flush. The
  continuation would still be a microtask scheduled inside the timer callback,
  so `createNativeCallback`'s trailing flush would again run before it.
- **Reaching for `tabris` as a JavaScript global from native**
  (`context.jsContext.objectForKeyedSubscript("tabris")`, or evaluating the
  string `"tabris.flush()"`). Orthogonal to the ordering problem, and it swaps
  the parameter contract the bridge already uses for an undocumented global.
- **Delivering results as events instead of callbacks.** Events flush, so it
  would work, but it dismantles the promise API that is the plugin's public
  contract.
