# 07 — Events (native → JS)

## The complete contract

Three things must line up:

1. **JS declares the event as native**
   ```js
   tabris.NativeObject.defineEvents(SwiftObject.prototype, { step: {native: true} });
   ```
2. **Native declares a listener flag** named `<eventName>Listener`, as an Objective-C-visible `BOOL`
   property:
   ```swift
   @objc public var stepListener = false
   ```
   ```objc
   @property (nonatomic) BOOL selectListener;   // in the class extension
   ```
3. **Native fires the event**, guarded by that flag:
   ```swift
   func fireStepEvent() {
       if stepListener {
           self.fireEventNamed("step", withAttributes: ["timestamp": Date().timeIntervalSince1970])
       }
   }
   ```

## How the listener flag is set

`BasicObject.listenWithProperties:` (`tabris-ios/Tabris/Tabris/Classes/BasicObject.m`) receives the
`listen` operation, which carries `{eventName: true|false}`:

```objc
static NSString *const LISTENER_SUFFIX = @"Listener";

for (NSString *key in properties) {
    NSNumber *value = properties[key];
    if ([value isKindOfClass:[NSNumber class]]) {
        if (![key hasSuffix:LISTENER_SUFFIX]) {
            key = [[key stringByReplacingCharactersInRange:NSMakeRange(0,1)
                                                withString:[[key substringToIndex:1] lowercaseString]]
                   stringByAppendingString:LISTENER_SUFFIX];
        }
        [self setKey:key toValue:value];
    }
}
```

So: first character lowercased, `Listener` appended, then the same KVC path used for properties. That
gives the naming rules:

- `select` → `selectListener`; `authStateChanged` → `authStateChangedListener`;
  `tokenGenerated` → `tokenGeneratedListener`.
- The flag must be `@objc` (Swift) or a declared `@property` (Objective-C) — `class_getProperty`
  has to see it, exactly as for real properties.
- The flag must be `Bool`/`BOOL`. Any other encoding is dropped.
- **Do not add the flag to `remoteObjectProperties`.** None of the reference plugins does. That set
  gates reads only, and JS never reads the flag. (Some built-in framework widgets do register
  theirs, e.g. `Drawer` adds `openListener`/`closeListener` — not required for a plugin.)
- The flag goes `true` on the first listener and `false` when the last one is removed, so it doubles
  as "is anyone listening".

## Firing

```objc
- (id)fireEventNamed:(NSString *)eventName withAttributes:(NSDictionary *)attributes;
```
This is the **only** public firing API. It forwards to `TabrisNotificationsDispatcher`, which calls
the JS `notify(objectId, event, attributes)` function through `context.syncCodeDispatcher` — a
**synchronous** hop onto the JS thread — and returns `retVal.toObject()`, or `nil` if JS returned
`undefined`. Attributes are converted with `JSValue withNativeObject:` (`08_data_types.md`).

Always pass a dictionary, `@{}` when there is no payload:
```objc
[self fireEventNamed:AddDiamondButtonSelectEvent withAttributes:@{}];
```

> `OpenIDConnect.swift` contains a single-argument call, `self.fireEventNamed("authStateChanged")`,
> which has no counterpart in the public headers of Tabris 3.9 (only
> `fireEventNamed:withAttributes:` and the internal `fireEventNamed:onObject:withAttributes:` are
> present in the binary). It presumably compiled against an additional overload in the version OIDC
> targets (its README says 3.7) — unverified. Write new code against
> `fireEventNamed(_:withAttributes:)`.

## What an event can carry back

`fireEventNamed` returns whatever the JS `_trigger` implementation returns. In practice that is a
boolean, which is why Diamond's example app states plainly:

> events in Tabris.js cannot return anything except "boolean", so this stuff needs to be stored in
> the property

The framework's own widgets rely on that boolean (`TabrisWebView` uses the result of its `navigate`
event to veto navigation). For anything richer, the workaround is **event out, method in**:

```
native: fireEventNamed("generateRequest", withAttributes: {certificates, nonce, nonceSignature})
   JS: builds the payload, then calls workflow.setPassData({...})
native: setPassData: resolves the stored completion handler
```
`AddDiamondWorkflow` parks the PassKit handler in a property between the two halves:
```objc
@property (copy, nonatomic) void (^returnPassData)(PKAddPaymentPassRequest * _Nonnull);
```

## Guard helpers

Write the guard once. `SwiftObject`/`OpenIDConnect` inline an `if`; `AddDiamondWorkflow` derives the
flag name by KVC so one helper covers all its events:

```objc
- (id)fireIfNeeded:(NSString*)event attributes:(NSDictionary*)attributes {
    NSString* listenerName = [event stringByAppendingString:@"Listener"];
    id listenerValue = [self valueForKey:listenerName];
    if (listenerValue) {
        return [self fireEventNamed:event withAttributes:attributes];
    }
    return nil;
}
```
(Works only for event names that already start lowercase.)

Logging the "nobody is listening" branch is genuinely useful during development:
```objc
else { [self diamondLog:@"JavaScript Application is not listening for `tokenGenerated` event"]; }
```

## Payload conventions

- Errors: `error.localizedDescription` or `NSNull`, never an `NSError` object.
  ```objc
  [self fireEventNamed:@"activationFinished" withAttributes:@{
      @"success": @(success),
      @"error": error ? error.localizedDescription : [NSNull null]
  }];
  ```
- Timestamps as seconds since epoch: `["timestamp": Date().timeIntervalSince1970]`.
- Binary payloads as `NSData` — automatically converted to an `ArrayBuffer`
  (`DeviceCheck` passes `@"token": token` directly).
- Bridging a delegate protocol: fan several callbacks into one event. OIDC forwards both
  `OIDAuthStateErrorDelegate` methods (authorization + transient errors) to a single
  `authStateError` event, and documents that in `docs/openidconnect.md`.

## Normalising and self-disposing on the JS side

Nullable attributes are easier to fix in JS than in native code:
```js
OpenIdConnect.prototype._trigger = function(name, event) {
  if (name === 'authStateChanged' && !('value' in event)) event.value = null;
  tabris.Widget.prototype._trigger.call(this, name, event);
};
```

A single-use object can dispose itself when its terminal event arrives:
```js
_trigger(name, event) {
  let result = super._trigger(name, event);
  if (name === 'finishedAdding') { this.dispose(); }
  return result;
}
```
Document that in the JS API, because the app must then create a fresh instance per run — Diamond's
example app does exactly that, and the native `run:` also refuses a second run:
```objc
if (self.ran) {
    [self diamondLog:@"this workflow already have been executed, please create a new instance …"];
    return @0;
}
```
