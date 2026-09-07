# 04 — The JavaScript module

## `NativeObject` (non-visual)

```js
class SMBClient extends tabris.NativeObject {

  constructor(properties) {
    super(properties);
  }

  get _nativeType() {
    return 'com.eclipsesource.smbclient';
  }

  connectShare(parameters) {
    this._nativeCall('connectShare', parameters);
  }
}

tabris.NativeObject.defineProperties(SMBClient.prototype, {
  serverURL: {type: 'string', default: ''},
  user:      {type: 'string', default: ''},
  password:  {type: 'string', default: ''}
});

module.exports = SMBClient;
```
Source: `~/git/tabris-plugin-swift/www/SMBClient.js`, with the constructor corrected (see the warning
below).

Mandatory pieces:
- `super(properties)` — or no constructor at all. `NativeObject`'s own constructor calls
  `this._nativeCreate(param)`, which registers the object (`_register()` assigns the `cid`), sends the
  `create` operation with `this._nativeType`, and applies `param` as properties. Verified in
  `tabris.js` 3.8.0, 3.10.0 and 3.11.0-dev (`class NativeObject … constructor(param) { …
  this._nativeCreate(param); }`).

  > **Warning — the three reference plugins get this wrong.** `SMBClient.js`, `OpenIdConnect.js` and
  > `DeviceCheck.js` (written against Tabris 3.7) do `super(); this._nativeCreate(this._nativeType,
  > properties)`. On 3.8+ that runs `_nativeCreate` twice: the first call already created a native peer,
  > and the second `_register()` tries to redefine the non-configurable `cid` property — a second native
  > object at best, a `TypeError` at worst. Follow `~/git/tabris-plugin-omr-2/www/*.js`
  > (`super(properties)` / `super({modelFile, labels})`) instead.
- `get _nativeType()` returning the same string as `+ remoteObjectType`.
- `tabris` and `tabris.NativeObject` are globals inside a plugin module — there is no `require('tabris')`
  in any of the three plugins' `www/` files.
- `module.exports` = the class; `<clobbers target="es.X"/>` makes it `es.X` in app code.

## `Widget` (visual)

```js
class AddDiamondButton extends tabris.Widget {
  get _nativeType() {
    return 'com.eclipsesource.AddDiamondButton';
  }
}
```
Source: `~/git/tabris-plugin-diamond/www/AddDiamondButton.js`.

No constructor — `tabris.Widget` (via `NativeObject`) handles creation, layout properties and
`appendTo()`. Only `_nativeType` plus the property/event declarations are yours.

## `defineProperties`

```js
tabris.NativeObject.defineProperties(OpenIdConnect.prototype, {
  infoLogging:  {type: 'boolean', default: false},
  accessToken:  {type: 'string', readonly: true, nocache: true},
  refreshToken: {type: 'string', readonly: true, nocache: true}
});
```

Options observed across the three plugins:

| Option | Effect | Used in |
|--------|--------|---------|
| `type` | value coercion/validation (`'string'`, `'boolean'`) | all |
| `default` | value before the first write | SMB2, OIDC, Diamond |
| `readonly: true` | JS cannot assign; native computes it | OIDC `accessToken`, `refreshToken` |
| `nocache: true` | every read goes to native instead of the JS-side cache | OIDC tokens, Diamond `mock` |
| `const: true` | settable only in the constructor | Diamond `AddDiamondButton.style` |
| `choice: [...]` | restricts allowed values | Diamond `style: ['black','blackOutline']` |

A property declared with no options at all is legal: `mock: {nocache: true}` in
`DiamondLibrary.js` has no `type`, so no coercion happens.

`nocache` matters whenever the native side is the owner of the value — without it JS answers reads
from its own cache and never issues a `get` operation.

## `defineEvents`

```js
tabris.NativeObject.defineEvents(OpenIdConnect.prototype, {
  authStateChanged: {native: true},
  authStateError:   {native: true}
});
```

`{native: true}` is what makes `on(...)`/`off(...)` emit the `listen` bridge operation, which flips
the `<name>Listener` flag natively (`07_events.md`). An event without it stays JS-only.

## Method call conventions

`_nativeCall(method, properties)` sends the `call` operation and returns whatever the native selector
returned. Two conventions appear:

**Flat parameters (SMB2, Diamond)** — pass the caller's object straight through:
```js
connectShare(parameters) { this._nativeCall('connectShare', parameters); }
isSupported(parameters)  { return this._nativeCall('isSupported', parameters); }
```

**Nested + Promise (OIDC)** — one wrapper turns every method into a Promise:
```js
nativeCall(method, parameters) {
  return new Promise((resolve, reject) => {
    this._nativeCall(method, {
      parameters,
      completion: (error, result) => {
        if (error != null) { reject(new Error(error)); }
        else { resolve(result === undefined ? null : result); }
      }
    });
  });
}

authenticate(parameters) { return this.nativeCall('authenticate', parameters); }
getFreshTokens()         { return this.nativeCall('getFreshTokens', {}); }
```
The native side then reads `properties["parameters"]` and `properties["completion"]`. This is the
better public API — the app gets `await`, and error handling is uniform. See
`06_methods_and_callbacks.md`.

## `_trigger` override

`_trigger(name, event)` is the JS-side hook that runs for every incoming native event. Two real uses:

**Normalise a payload** (OIDC — a cleared auth state fires without a `value` attribute):
```js
OpenIdConnect.prototype._trigger = function(name, event) {
  if (name === 'authStateChanged' && !('value' in event)) event.value = null;
  tabris.Widget.prototype._trigger.call(this, name, event);
};
```
Note it delegates to `tabris.Widget.prototype._trigger` even though the class extends
`NativeObject` — verbatim from the source.

**Auto-dispose after a terminal event** (Diamond — a workflow is single-use):
```js
_trigger(name, event) {
  let result = super._trigger(name, event);
  if (name === 'finishedAdding') { this.dispose(); }
  return result;
}
```
Returning `result` matters: the return value travels back to native as the result of
`fireEventNamed:withAttributes:`.

## Documenting the JS API

OIDC ships `docs/openidconnect.md` with three sections — Methods, Properties, Events — each entry
one line plus a link to the wrapped SDK's documentation. Cheap and worth copying.
