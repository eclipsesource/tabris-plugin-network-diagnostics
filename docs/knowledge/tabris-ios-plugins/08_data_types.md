# 08 — Data types across the bridge

All conversion happens in `JSValue+Tabris.m` (`~/git/tabris-ios/Tabris/Tabris/Classes/`). Both
directions are total: there is no per-plugin serialisation to write.

## JS → native (`-[JSValue toNativeObject]`)

Applies to: creation properties, `set` values, `call` parameter dictionaries.

| JavaScript | Native |
|------------|--------|
| `null` | `NSNull` |
| `boolean` | `NSNumber` |
| `number` | `NSNumber` |
| `string` | `NSString` |
| `Date` | `NSDate` |
| `Array` | `NSArray` (elements converted recursively) |
| `function` | **`JSFunctionValue`** |
| `ArrayBuffer` / any `TypedArray` | **`NSData`** |
| any other object | `NSDictionary` (values converted recursively) |
| `undefined` | `nil` (the key is absent from the dictionary) |

## native → JS (`+[JSValue withNativeObject:inContext:]`)

Applies to: event attributes, `get` results, `call` return values, `JSFunctionValue` arguments.

| Native | JavaScript |
|--------|------------|
| `nil` | `undefined` |
| `NSNumber` holding a boolean | `boolean` |
| `NSNumber` (other) | `number` |
| `NSString` | `string` |
| **`NSData`** | **`ArrayBuffer`** (via `ArrayBuffer.arrayBufferWithData:inContext:`) |
| `NSArray` | `Array` (recursive) |
| `NSDictionary` | plain object (recursive) |
| `NSDate` | `Date` (through JavaScriptCore's own bridging) |
| `JSFunctionValue` | `null` |
| anything else | `[JSValue valueWithObject:]` — JavaScriptCore's default bridging |

Two exceptions are raised rather than swallowed:
- missing `JSContext` while converting → `TabrisExceptionNameMissingJSContext`;
- an array/dictionary element that cannot be encoded → `TabrisExceptionNameUnableToEncodeObject`.

`NSNull` is not special-cased in `withNativeObject:`; it falls through to `valueWithObject:`, and the
reference plugins use it freely as an event attribute and as a "no error" callback argument.

## Type-safe dictionary getters

Rather than casting by hand, use the framework category (`NSDictionary+TypeSafeGetters.h`), available
in Objective-C and Swift:

```objc
- (NSDictionary*)dictionaryForKey:(id)key;
- (NSArray*)arrayForKey:(id)key;
- (NSArray*)arrayOfArraysForKey:(id)key;
- (NSArray*)arrayOfDictionariesForKey:(id)key;
- (NSData*)dataForKey:(id)key;
- (NSNumber*)numberForKey:(id)key;
- (NSString*)stringForKey:(id)key;
- (JSFunctionValue*)JSFunctionValueForKey:(id)key;
- (CGPoint)asCGPoint;  - (CGPoint)CGPointForKey:(id)key;
- (CGSize)asCGSize;    - (CGSize)CGSizeForKey:(id)key;
```

Each returns `nil` on a type mismatch instead of throwing, which is why Diamond's code reads as a
chain of nil-checks:

```objc
NSString* serialNumber = [parameters stringForKey:@"serialNumber"];
if (!serialNumber) { [self diamondLog:@"`serialNumber` is missing in parameters list: %@", parameters]; return @0; }
NSData* activationData = [parameters dataForKey:@"activationData"];
if (!activationData) { … return @0; }
NSNumber* remotePass = [parameters numberForKey:@"remotePass"];
if (!remotePass) { … return @0; }
```

There is also `NSArray+TypeSafeGetters.h` and, for single values,
`[NSObject object:x asInstanceOf:[NSString class]]` (`NSObject+Validation.h`) — used in
`TDP+PassKit.m` when converting incoming strings to PassKit enums.

The pure-Swift plugins skip the category and use `as?` casts plus `guard let`, which is equivalent:
```swift
guard let share = parameters["share"] as? String else { … }
let recursive = parameters["recursive"] as? Bool ?? false
```
Note `as? Bool` works because JS booleans arrive as `NSNumber` and Swift bridges that to `Bool`.

## Binary data

Both directions are automatic — do not hand-roll base64.

App → native: JS passes an `ArrayBuffer`, native reads `NSData`:
```js
addDiamondWorkflow.setPassData({
  encryptedPassData: new ArrayBuffer(32),
  activationData: new ArrayBuffer(32),
  ephemeralPublicKey: new ArrayBuffer(32),
  wrappedKey: new ArrayBuffer(32)
});
```
```objc
request.encryptedPassData = [parameters dataForKey:@"encryptedPassData"];
```

Native → app: put `NSData` in the payload and JS receives an `ArrayBuffer`:
```objc
[self fireEventNamed:@"tokenGenerated" withAttributes:@{ @"token": token, … }];   // token is NSData
```
```swift
let data = try NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: true)
complete(with: [data], completion: getCompletion(properties))   // arrives as ArrayBuffer
```
OIDC uses this to hand a whole `NSKeyedArchiver`-serialised `OIDAuthState` to JS, which persists it
in `secureStorage` and restores it later with `setAuthenticationState`.

Images: convert to `NSData` explicitly — `UIImagePNGRepresentation(pass.icon)` in `TDP+PassKit.m`.

## Manual `ArrayBuffer` construction and the JSContext problem

`ArrayBuffer.h` exposes the low-level API:
```objc
+ (JSValue*)arrayBufferWithData:(NSData*)data inContext:(JSContext*)context;
+ (NSData*)valueToData:(JSValue*)value;
+ (BOOL)isArrayBufferOrTypedArray:(JSValue*)value;
```

Using it requires a `JSContext`, and a `BasicObject` has no direct handle on one. `AddDiamondWorkflow`
obtains it from a dummy JS callback — the JS side injects a no-op function purely so the native side
can read `JSFunctionValue.context`:

```js
run(parameters) {
  // Native implementation of this class does not have access to
  // JavaScript context. Without it it's not possible to instantiate
  // `ArrayBuffer`s. Appending a dummy callback to the parameters of
  // this method make it possible to access JavaScript context.
  parameters['ctx'] = function() {};
  return this._nativeCall('run', parameters);
}
```
```objc
JSFunctionValue* fn = [parameters JSFunctionValueForKey:@"ctx"];
if (!fn) { [self diamondLog:@"dummy callback is missing in parameters list: %@", parameters]; return @0; }
self.jsContext = fn.context;
…
JSValue* value = [ArrayBuffer arrayBufferWithData:obj inContext:ctx];
```

**Do not copy this hack for plain `NSData`.** In the framework version examined here (3.9),
`withNativeObject:` converts `NSData` — including `NSData` nested in arrays and dictionaries — to
`ArrayBuffer` automatically, and `DeviceCheck.m` relies on that. Passing `NSArray<NSData*>` as an
event attribute is enough; the manual construction only becomes necessary if you genuinely need a
`JSValue` for something else.

`context.jsContext` also exists on `TabrisContext`, but touching JavaScriptCore directly from a
plugin is outside the supported surface.

## Native SDK objects → plain dictionaries

The bridge cannot carry an arbitrary Objective-C object, so flatten it. Diamond puts a `toDictionary`
category on each PassKit type; SMB2 does the same with a Swift extension:

```swift
extension Dictionary where Key == URLResourceKey, Value == Any {
    func AMSMB2ResourceToTabrisObject() -> [String: Any] {
        return [
            "name": self[.nameKey] as? String as Any,
            "path": self[.pathKey] as? String as Any,
            "isDirectory": self[.isDirectoryKey] as? Bool ?? false,
            "fileSize": self[.fileSizeKey] as? Int64 as Any,
            "contentModificationDate": self[.contentModificationDateKey] as? Date as Any,
            …
        ]
    }
}
```

Conventions from the reference plugins:
- Enums become strings in both directions, with a named conversion function and an explicit
  fallback:
  `NSStringFromPKPaymentPassActivationState()` → `"activated"`, `"suspended"`, …, `"unknown"` plus a
  log line; `PKPaymentNetworkFromNSString()` for the reverse.
- `NSURL` → `absoluteString`.
- `NSDate` → either the bridged `Date` (SMB2) or `timeIntervalSince1970` (Diamond). Pick one per
  plugin and document it.
- Use `?: [NSNull null]` for every optional so the JS object has a stable shape.

> `AMSMB2ResourceToTabrisObject` also emits `"fileResourceType": … as? URLFileResourceType`, which is
> an `NSString`-backed struct. Whether that survives the conversion is not verified; `NSString`-typed
> keys are the safe choice.
