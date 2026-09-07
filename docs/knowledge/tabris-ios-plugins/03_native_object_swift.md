# 03 — The native object in Swift

## Minimal complete skeleton

```swift
import Foundation

@objc(SwiftObject) public class SwiftObject: BasicObject {

    // 1. properties readable/writable from JS
    @objc public var forward = true

    // 2. event-listener flag (see 07_events.md) — NOT a remote property
    @objc public var stepListener = false

    // 3. the type string that binds this class to its JS proxy
    @objc public override class func remoteObjectType() -> String! {
        return "com.eclipsesource.swiftobject"
    }

    // 4. whitelist of properties JS may READ
    @objc public override class func remoteObjectProperties() -> NSMutableSet! {
        let properties = super.remoteObjectProperties()
        properties?.add("forward")
        return properties
    }

    // 5. designated initializer — must be `required init!` with this exact signature
    required init!(objectId: String!, properties: [AnyHashable : Any]!, in context: TabrisContext!) {
        super.init(objectId: objectId, properties: properties, in: context)
        self.register(#selector(self.run(parameters:)), forCall: "run")
    }

    // 6. a method callable from JS
    @objc(run:) public func run(parameters: Dictionary<String, Any>) { /* ... */ }
}
```
Source: `~/git/tabris-plugin-diamond/src/ios/diamond/SwiftObject.swift`.

## Each element in detail

### `@objc(ClassName)`
Fixes the Objective-C class name. It must match the string in `TabrisPlugins.plist` exactly, because
registration goes through `NSClassFromString`. Without it Swift mangles the name
(`_TtC6Module5Class`) and startup throws `TabrisError(.resourceLoading)`.

### `public class X: BasicObject`
`BasicObject` conforms to `RemoteObject` and `TabrisDescriptionsProtocol`, and provides:
```objc
@property (strong, nonatomic, readonly) id<TabrisContext> context;
@property (assign, readonly) BOOL isDisposed;
- (void)registerSelector:(SEL)selector forCall:(NSString *)method;
- (id)fireEventNamed:(NSString *)eventName withAttributes:(NSDictionary *)attributes;
```
For a visual plugin subclass `Widget`, `WidgetContainer` or `Control` instead (`09_widgets.md`).

### `remoteObjectType()`
Abstract — `BasicObject`'s implementation calls `doesNotRecognizeSelector:`. Convention in all
reference plugins: reverse-DNS-ish `com.eclipsesource.<Name>`. Casing is arbitrary but must be
byte-identical to the JS `_nativeType` (`com.eclipsesource.smbclient` vs
`com.eclipsesource.OpenIdConnect` — both styles appear in the same codebase).

### `remoteObjectProperties()`
Always start from `super.remoteObjectProperties()` — the base returns a set containing `"children"`,
and `BasicWidget`/`Control` add the whole widget property surface.

**This set gates reads only.** `getWithMethod:` checks membership before reading; `setWithProperties:`
does not check anything and writes every key it receives via KVC. Practical effect: a property
missing from the set is still writable from JS but always reads back as `undefined`.

### `required init!(objectId:properties:in:)`
This is the Swift spelling of `-initWithObjectId:properties:inContext:`. The `!` (implicitly
unwrapped optional) form is required to satisfy the Objective-C protocol; `required` is needed
because the framework instantiates the class dynamically.

`properties` holds the creation properties passed to `_nativeCreate(type, properties)`. None of the
three reference plugins reads it directly in Swift — they let `super.init` apply them via KVC. The
Objective-C `AddDiamondButton` does read it, because a `const` property must be consumed before the
view is built:
```objc
PKAddPassButtonStyle style = [[properties stringForKey:@"style"] isEqualToString:@"blackOutline"]
    ? PKAddPassButtonStyleBlackOutline : PKAddPassButtonStyleBlack;
```

Register every callable method here. Do not do heavy work in the initializer — `SMBClient` builds
its client lazily so credentials set right after construction are picked up:
```swift
lazy var client: AMSMB2? = { /* reads serverURL / user / password */ }()
```

### `register(_:forCall:)`
Swift name of `registerSelector:forCall:`. It stores the selector in a dictionary keyed by the JS
method name, so the JS-side name and the Swift name are independent:
```swift
self.register(#selector(self.discover(properties:)), forCall: "discoverConfiguration")
```
Both spellings of `#selector` work:
- `#selector(self.run(parameters:))` — explicit, preferred;
- `#selector(self.getFreshTokens)` — resolves to the single `@objc` overload
  (`getFreshTokensWithProperties:`). Fragile if you ever add an overload.

The Objective-C form is `[self registerSelector:@selector(canAdd:) forCall:@"canAdd"];`.

### `@objc(run:)` on methods
Optional but recommended. Without it, `func run(parameters:)` becomes the selector
`runWithParameters:`; with it, `run:`. Either works — the framework invokes the selector object it
was handed — but the explicit form keeps native and JS names aligned and makes `#selector`
unambiguous. OIDC mixes both styles in one file.

## Structuring a bigger Swift plugin

OIDC splits parameter parsing out of the object into extensions on the SDK types, one file each,
all listed in `plugin.xml`:

```
src/ios/OpenIDConnect.swift                    the BasicObject subclass
src/ios/OIDAuthorizationRequest+Tabris.swift   convenience init(tabrisParameters:) throws
src/ios/OIDEndSessionRequest+Tabris.swift      convenience init(tabrisParameters:) throws
src/ios/OIDServiceConfiguration+Tabris.swift   var asTabrisObject: [String: String]
```

The pattern: a throwing `convenience init(tabrisParameters: Dictionary<String, Any>)` that validates
required keys, converts strings to `URL`, strips the consumed keys and forwards the remainder as
`additionalParameters`:

```swift
var additionalParameters = parameters
["authorizationEndpoint", "tokenEndpoint", "clientId", "redirectUrl",
 "responseType", "clientSecret", "scopes"].forEach { additionalParameters.removeValue(forKey: $0) }
guard let additionalParameters = additionalParameters as? [String: String] else {
    throw OpenIDConnect.OpenIDConnectError("All additional parameters must be strings.")
}
```

Errors are a nested `LocalizedError` struct so `error.localizedDescription` carries a useful message
across the bridge:

```swift
extension OpenIDConnect {
    struct OpenIDConnectError: LocalizedError {
        let errorDescription: String?
        init(_ errorDescription: String) { self.errorDescription = errorDescription }
    }
}
```

Delegate conformances also go into extensions (`OIDAuthStateChangeDelegate`,
`OIDAuthStateErrorDelegate`), each forwarding to a small `fire…` method.

## `description` override

Every reference class overrides `description` to `<ClassName objectId pointer>`:
```objc
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@ %p>", NSStringFromClass(self.class), self.objectId, self];
}
```
It is used as the log prefix (`10_console_and_logging.md`), so the console line identifies the exact
instance. Swift classes get an acceptable default and OIDC just uses `self.description`.
