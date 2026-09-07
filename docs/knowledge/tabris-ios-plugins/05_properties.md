# 05 — Properties

## The mechanism

Properties do **not** go through registered selectors. They go through Objective-C runtime
introspection in `BasicObject` (`tabris-ios/Tabris/Tabris/Classes/BasicObject.m`):

- **set**: `setWithProperties:` iterates the incoming dictionary and calls `setKey:toValue:` for each
  key. `setKey:toValue:` does `class_getProperty([self class], key)`, reads the property's type
  encoding and invokes the synthesised setter through a typed function pointer.
- **get**: `getWithMethod:` first checks `[[self.class remoteObjectProperties] containsObject:key]`,
  then `getKey:` does the same introspection on the getter.

Two consequences that are easy to get wrong:

1. **`remoteObjectProperties` gates reads only.** A property absent from the set is still written by
   JS assignments; it just always reads back `undefined`. (`SwiftObject` never registers
   `stepListener`, yet the framework writes it.)
2. **The property must be a declared Objective-C `@property`.** `class_getProperty` returns `NULL`
   for a plain instance variable or a Swift property that is not exposed to Objective-C. In Swift
   this means `@objc` is mandatory:
   ```swift
   @objc public var forward = true          // works
   public var forward = true                // silently ignored by set and get
   ```

## Supported property types

`setKey:toValue:` and `getKey:` switch on the first character of the type encoding and handle
exactly these cases:

| Encoding | Swift / ObjC type | Notes |
|----------|-------------------|-------|
| `B` | `Bool` | |
| `c` | `signed char` | the `BOOL` encoding on some architectures; read back as `@YES`/`@NO` |
| `@` | object | on get, only `NSString`, `NSNumber`, `NSArray`, `NSDictionary`, `UIColor`, `UIFont` are converted; `UIColor`/`UIFont` go through `TypeConverter` |
| `{` | struct | **only** `CGRect` and `CGPoint`, converted via `TypeConverter` |

Anything else hits `default: break` — the value is dropped without an error.

**Practical rule: never declare a numeric property as `Int` or `Double`.** Those encode as `q`/`d`
and are silently ignored in both directions. Use `NSNumber` (`@objc public var count: NSNumber?`) or
a `String`, or pass the number as a method parameter instead. All three reference plugins only ever
declare `Bool` and `String?` properties:

```swift
@objc public var serverURL: String?     // SMBClient
@objc public var user: String?
@objc public var password: String?
@objc public var infoLogging = false    // OpenIDConnect
@objc public var forward = true         // SwiftObject
```

## Set ordering

`+ prioritizeKeys:` reorders keys before applying them, so within a single `set` operation:
- `data`, `enabled`, `focused` are applied **first**, in exactly that order;
- `parent`, then `layoutData`, are applied **last**.

Everything else keeps dictionary order, which is unordered. Never depend on two custom properties
being applied in a particular order — if one depends on the other, resolve it lazily.

## Read-only computed properties

Declare the Swift property as a computed getter and add it to `remoteObjectProperties`; mark it
`readonly` on the JS side:

```swift
@objc public var accessToken: String? { return authState?.lastTokenResponse?.accessToken }
@objc public var refreshToken: String? { return authState?.lastTokenResponse?.refreshToken }
```
```js
accessToken:  {type: 'string', readonly: true, nocache: true},
refreshToken: {type: 'string', readonly: true, nocache: true}
```

`nocache: true` is essential here — the value changes natively without any JS write, so a cached
read would go stale.

## Setters with side effects

A property setter is a normal setter, so it can do work. `DiamondLibrary` uses one as a global
logging switch that also rewires the console sink:

```objc
- (void)setLogging:(BOOL)logging {
    _logging = logging;
    diamondConsole = logging ? self.context.console : nil;
}
```
The example app comments that this switch is global for the whole plugin and survives app reloads
(`~/git/tabris-plugin-diamond/example/src/app.js`).

## Lazy consumption of property values

Properties arrive after the initializer has run (`create` then `set`), so an initializer cannot
depend on them. `SMBClient` builds its connection lazily on first use:

```swift
var _client: AMSMB2?
lazy var client: AMSMB2? = {
    if _client != nil { return _client }
    guard let url = _serverURL else { jsConsoleLog("Invalid server URL: …"); return nil }
    guard let user = user else { jsConsoleLog("`user` was not set"); return nil }
    guard let password = password else { jsConsoleLog("`password` was not set"); return nil }
    _client = AMSMB2(url: url, credential: URLCredential(user: user, password: password,
                                                         persistence: .forSession))
    return _client
}()
```

The exception is a `const` property, which JS guarantees is present in the creation properties:
`AddDiamondButton` reads `style` inside `initWithObjectId:properties:inContext:` because the
`PKAddPassButton` style cannot be changed after construction.

## Private helper properties

A property that JS should never touch is simply left out of `remoteObjectProperties` and, in
Objective-C, declared in the class extension in the `.m` file:

```objc
@interface DiamondLibrary ()
@property (nonatomic) BOOL logging;
@property (nonatomic) BOOL mock;
@property (nonatomic) BOOL activationFinishedListener;
@property (strong, nonatomic, readonly) PKPassLibrary* passLibrary;
@end
```
KVC still reaches them (that is how `mock` and the `…Listener` flags get set), while the public
header stays empty.
