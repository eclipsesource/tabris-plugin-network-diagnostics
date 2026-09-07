# 01 — Architecture: how a Tabris.js iOS plugin is wired

## Two halves of every plugin

| Half | Lives in | Base class | Job |
|------|----------|------------|-----|
| JavaScript proxy | `www/*.js` | `tabris.NativeObject` or `tabris.Widget` | public API for the app, declares properties/events, marshals calls |
| Native peer | `src/ios/*.swift` / `*.m` | `BasicObject` (non-visual) or `Widget`/`Control` (visual) | wraps the iOS SDK, owns state, fires events |

The two halves are bound by one string — the **remote object type** (e.g. `com.eclipsesource.smbclient`):
JS returns it from `get _nativeType()`, native returns it from `+ remoteObjectType`.

## The bridge: six operations

`TabrisBridge` (`tabris-ios/Tabris/Tabris/Classes/TabrisBridge.m`) exposes exactly six operations to JS.
`ObjectDispatch` maps each to a `BasicObject` selector:

| Operation | Triggered from JS by | Native selector | Returns a value to JS? |
|-----------|----------------------|-----------------|------------------------|
| `create` | `this._nativeCreate(type, properties)` | `initWithObjectId:properties:inContext:` | no |
| `set` | property assignment | `setWithProperties:` | no |
| `get` | property read | `getWithMethod:` | **yes** |
| `call` | `this._nativeCall(method, properties)` | `callWithProperties:method:` | **yes** |
| `listen` | `on()` / `off()` on a native event | `listenWithProperties:` | no |
| `destroy` | `dispose()` | `destroyWithProperties:` → `destroy` | no |

Everything a plugin does is one of these six. There is no other channel — a native-initiated
message is always an *event* (see `07_events.md`), which is itself a synchronous call into JS.

## Type registration chain

1. `plugin.xml` appends the **Objective-C class name** to `TabrisPlugins.plist` → `classes` array.
2. On startup `MainScope.addExternalRemoteObjects()` reads that plist
   (`tabris-ios/Tabris/Tabris/Classes/MainScope.swift`).
3. For each entry: `NSClassFromString(className)` → must cast to `RemoteObject.Type`,
   otherwise startup throws `TabrisError(code: .resourceLoading)`.
4. `widgetRegistry.addHandler(type)` stores the class keyed by `remoteObjectType()`.
5. The optional class method `setup()` is called once, right after registration.

Consequences:
- The plist string must be the **Objective-C** name. In Swift that means `@objc(SMBClient) public class SMBClient` — the `@objc(...)` argument is what `NSClassFromString` resolves.
- A typo in the plist or a missing `@objc(...)` is a startup failure, not a silent no-op.
- `remoteObjectType()` is abstract: `BasicObject`'s implementation calls `doesNotRecognizeSelector:`. Not overriding it crashes.

## Object lifecycle

- JS `new MyObject()` → `_nativeCreate` → framework allocates the native class via its designated
  initializer, passing the creation `properties` dictionary and the `TabrisContext`.
- The instance is held by `ObjectRegistry`, keyed by `objectId`.
- JS `dispose()` → `destroy` → `isDisposed = YES`, children destroyed recursively, detached from
  parent, removed from `ObjectRegistry`.
- `dealloc` additionally dismisses every `FloatingViewController` the object created.

## Threading

`fireEventNamed:withAttributes:` and the `get`/`call` return paths run through
`context.syncCodeDispatcher` — i.e. **synchronously on the JS thread**. Native completion handlers
that arrive on a background queue must hop to the main queue before touching the bridge; the sample
plugins do this either implicitly (SDK callbacks already on main) or via
`DispatchQueue.main.asyncAfter` (`SwiftObject.run`).

## Reference plugins used throughout this guide

| Plugin | Path | What it demonstrates |
|--------|------|----------------------|
| SMB2 (`tabris-plugin-swift`) | `~/git/tabris-plugin-swift` | pure-Swift `BasicObject`, `JSFunctionValue` callbacks, progress callbacks, CocoaPods dependency |
| OpenID Connect | `~/git/tabris-plugin-openidconnect` | pure-Swift, Promise-wrapped API, native events, computed read-only properties, URL-callback handling, Swift-version hook |
| Diamond | `~/git/tabris-plugin-diamond` | mixed Objective-C + Swift, a **widget** (`Control` subclass), multiple native types in one plugin, synchronous return values, `ArrayBuffer` transfer, standalone Xcode dev project |

Framework sources referenced: `~/git/tabris-ios` (Tabris iOS framework) and the public headers of
`Tabris.xcframework` (version 3.9 as vendored in `~/git/migration-guide`).
