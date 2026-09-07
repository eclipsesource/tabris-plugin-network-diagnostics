# 12 — Checklist and pitfalls

## New plugin from scratch

1. `package.json` — `name`, `cordova.id`, `cordova.platforms: ["ios"]`,
   keywords `ecosystem:cordova`, `ecosystem:tabris`.
2. `plugin.xml` — `id`, `version`, `<engines>`, one `<js-module>` + `<clobbers>` per type,
   `<config-file target="*TabrisPlugins.plist" parent="classes">` listing every Objective-C class
   name, `<header-file type="BridgingHeader">`, one `<source-file>` per Swift/ObjC file,
   `<podspec>` if there are dependencies.
3. `src/ios/Tabris-BridgingHeader.h` → `#import <Tabris/Tabris.h>`.
4. `hook/add-swift-support.js` + `xcode`/`semver` deps if the plugin is Swift and has no
   `use-frameworks` pod (copy from `tabris-plugin-openidconnect`).
5. Native class: `@objc(Name) public class Name: BasicObject`, override `remoteObjectType()` and
   `remoteObjectProperties()`, implement `required init!(objectId:properties:in:)`, register methods.
6. `www/Name.js`: `_nativeType`, constructor `super(properties)` or none at all (never
   `super(); this._nativeCreate(...)` — `NativeObject` creates the native peer itself, see
   `04_javascript_module.md`), `defineProperties`, `defineEvents`, method wrappers, `module.exports`.
7. `docs/<name>.md` — Methods / Properties / Events.
8. `example/` app with `spec="../"`, `EnableDeveloperConsole`, and a `build.fish`.
9. `.npmignore` excluding `example/`, `project/`, `.idea/`, `.vscode/`, `.gitignore`, `.github`.
10. `README.md` — integration snippet, the Tabris.js version it was tested against, supported
    platforms.

## Adding a property

- [ ] `@objc public var x: <Bool|String?|NSNumber?>` (never `Int`/`Double` — silently dropped)
- [ ] added to `remoteObjectProperties()` **if JS must read it**
- [ ] declared in `defineProperties` with `type`, and `default` where it matters
- [ ] `readonly: true` when native computes it; add `nocache: true` too
- [ ] `const: true` when the value can only be consumed in the initializer
- [ ] don't rely on it being set inside the initializer — read it lazily

## Adding a method

- [ ] `self.register(#selector(self.foo(parameters:)), forCall: "foo")` in the initializer
- [ ] `@objc(foo:) public func foo(parameters: Dictionary<String, Any>)`
- [ ] a return value only reaches JS if the return type is an **object** (`NSNumber`, `NSString`,
      `NSArray`, `NSDictionary`, `NSData`)
- [ ] async result → `JSFunctionValue` callback, error-first, wrapped in a JS Promise
- [ ] every parameter validated, failures reported through the callback, not by crashing
- [ ] JS wrapper method in `www/`

## Adding an event

- [ ] `@objc public var fooListener = false` (Swift) / `@property (nonatomic) BOOL fooListener;` (ObjC)
- [ ] **not** in `remoteObjectProperties()`
- [ ] `foo: {native: true}` in `defineEvents`
- [ ] fired only when the flag is set, always with a dictionary (`[:]` / `@{}` if empty)
- [ ] errors as `localizedDescription`, absent values as `NSNull`

## Pitfalls

**Registration**
- A JS constructor that calls `this._nativeCreate(...)` after `super()` → two registrations and two
  `create` operations on Tabris 3.8+ (the first native peer leaks) and the constructor's properties
  are dropped, because `_nativeCreate(param)` takes a single argument. The base class already creates
  the peer; write `super(properties)`.
- Missing `@objc(ClassName)` on a Swift class → `NSClassFromString` fails → startup throws
  `TabrisError(.resourceLoading)`, not a silent degradation.
- The plist entry, the `@objc(...)` name and the class name must all agree.
- `remoteObjectType()` not overridden → `doesNotRecognizeSelector:` (the base implementation is
  deliberately abstract).
- `remoteObjectType()` mismatched between native and JS `_nativeType` → the `create` operation finds
  no handler.

**Properties**
- Forgetting `@objc` → `class_getProperty` returns `NULL` → both set and get are dropped with only a
  `DebugLog` line.
- `Int`/`Double`/`CGFloat` properties → unsupported type encoding → dropped in both directions.
- Not calling `super.remoteObjectProperties()` → you lose `children` and, for widgets, the entire
  inherited property surface.
- Assuming `remoteObjectProperties` blocks writes — it does not; it only gates reads.
- Reading a property in the initializer that JS sets afterwards. Only `const` properties are
  guaranteed to be present there.
- Omitting `nocache: true` on a natively-computed property → JS serves a stale cached value.

**Methods**
- Returning `Bool`/`Int`/`void` and expecting the value in JS — only object return types survive.
- Calling an unregistered method name — no error, just `Call of '<name>' … Unhandled` in the log.
- Not checking for the `completion` `JSFunctionValue` before use.
- Firing a bridge call from a background queue. `fireEventNamed` and the `get`/`call` paths run
  synchronously on the JS thread; hop to main first.

**Events**
- Wrong flag name. It is derived mechanically: first character lowercased + `Listener`.
- A listener flag that is not `Bool`/`BOOL`, or not `@objc` → never set → the event never fires and
  nothing reports why.
- Expecting an event to return data. Only a boolean comes back; use the *event out, method in*
  pattern (`07_events.md`).
- Firing without the guard — wasteful, and it hides the "app is not listening" bug.

**UI**
- Presenting on `context.viewController` instead of a `FloatingViewController`.
- Not dismissing on the error paths.
- Losing the strong reference to the floating controller mid-flow.

**Build**
- No `SWIFT_VERSION` in the generated project → Swift files fail to compile. That is what
  `add-swift-support.js` exists for.
- A `.swift` file not listed in `<source-file>` → it is simply not part of the app target
  (Diamond's `SwiftObject.swift` is in this state on purpose).
- Editing sources under `platforms/ios` — they are regenerated. Edit the plugin repo and re-add it,
  or work in a standalone project like `src/ios/diamond.xcodeproj`.

## Recurring design decisions

| Question | What the reference plugins do |
|----------|-------------------------------|
| One native type or several? | Several when the domain has distinct objects with independent lifecycles (Diamond: library / workflow / button / device check). One when it is a single service (SMB2, OIDC). |
| Callback or event? | Callback for the result of a specific call; event for state the app did not ask for right now (`authStateChanged`, `activationFinished`, `select`). |
| Promise or raw callback? | Promise. One `nativeCall` wrapper in the JS module (`04_javascript_module.md`) makes the whole API `await`-able. |
| Where does persistence live? | In the app, in JS. The plugin serialises to `NSData` and hands it over (`11_context_and_ui.md`). |
| How are enums represented? | Strings both ways, with a named converter and an explicit fallback plus a log line. |
| How is mocking done? | A `mock` boolean property that swaps in a fake implementation — `DiamondLibrary.mock` short-circuits activation and `AddDiamondWorkflow.mock` substitutes `FakeAddPaymentPassViewController`, so the example app runs without a bank backend. |
| Single-use objects? | Refuse a second run natively (`if (self.ran)`) **and** dispose in JS `_trigger` on the terminal event. Document that the app must create a fresh instance. |
