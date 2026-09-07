# Knowledge index: Implementing Tabris.js iOS plugins in Swift

A condensed, agent-oriented guide to the native (iOS) side of Tabris.js plugins: every JS↔iOS
communication mechanism, type registration, properties, methods, callbacks, events, data marshalling,
widgets, logging and app integration.

**Distilled from** three plugin repositories plus the Tabris iOS framework itself. Every claim in
these files is traceable to one of the sources below; anything inferred rather than read is marked
inline as unverified.

## Chapters

- [01_architecture.md](./01_architecture.md) — the two halves of a plugin, the six bridge operations (`create`/`set`/`get`/`call`/`listen`/`destroy`), the type-registration chain, object lifecycle, threading.
- [02_packaging_and_build.md](./02_packaging_and_build.md) — repository layout, `plugin.xml` element by element, `TabrisPlugins.plist`, bridging header, the `add-swift-support.js` Swift-version hook, CocoaPods, standalone Xcode dev project.
- [03_native_object_swift.md](./03_native_object_swift.md) — the `BasicObject` subclass in Swift: `@objc(Name)`, `remoteObjectType`, `remoteObjectProperties`, `required init!`, `register(_:forCall:)`, file structure for larger plugins.
- [04_javascript_module.md](./04_javascript_module.md) — `www/*.js`: `NativeObject` vs `Widget`, `_nativeCreate`/`_nativeCall`, `defineProperties`, `defineEvents`, the Promise wrapper, `_trigger` overrides.
- [05_properties.md](./05_properties.md) — the KVC/runtime mechanism, which type encodings are supported (and why `Int` is not), read gating vs write gating, set ordering, read-only computed properties, setters with side effects.
- [06_methods_and_callbacks.md](./06_methods_and_callbacks.md) — selector registration, when a synchronous return value reaches JS, `JSFunctionValue`, error-first callbacks, progress callbacks, validation style.
- [07_events.md](./07_events.md) — the `<name>Listener` flag contract, how `listen` sets it, `fireEventNamed:withAttributes:`, why an event can only return a boolean and the *event out, method in* workaround, payload conventions.
- [08_data_types.md](./08_data_types.md) — full conversion tables both directions, type-safe dictionary getters, binary data / `ArrayBuffer`, the JSContext problem, flattening SDK objects into dictionaries.
- [09_widgets.md](./09_widgets.md) — `Widget`/`WidgetContainer`/`Control` hierarchy, `defineWidgetView:`, the four view roles of `WidgetProtocol`, interaction, `const` properties, children.
- [10_console_and_logging.md](./10_console_and_logging.md) — `Console`/`ConsoleEntry`, `ConsoleEntryType` raw values, three logging patterns (`LogEntry`, custom entry type, plugin-wide category), what is worth logging.
- [11_context_and_ui.md](./11_context_and_ui.md) — `TabrisContext` members, `BasicObject+Shorthands`, presenting UI via `FloatingViewController`, receiving URL callbacks through the `ESNSApplicationOpenURL` notification, persisting state in JS.
- [12_checklist_and_pitfalls.md](./12_checklist_and_pitfalls.md) — step-by-step checklists for a new plugin / property / method / event, the failure modes that produce no error message, recurring design decisions.

## Sources

### Reference plugins
| Plugin | Path | Contributes |
|--------|------|-------------|
| SMB2 (`tabris-plugin-swift`) | `~/git/tabris-plugin-swift` | pure-Swift `BasicObject`, `JSFunctionValue` completion + progress callbacks, lazy client construction, CocoaPods dependency, `LogEntry` logging |
| OpenID Connect | `~/git/tabris-plugin-openidconnect` | pure-Swift, Promise-wrapped JS API, native events with delegate fan-in, computed read-only properties, `FloatingViewController` presentation, URL-callback notification, `NSKeyedArchiver` state hand-off, Swift-version Cordova hook, `docs/` API page |
| Diamond | `~/git/tabris-plugin-diamond` | mixed Objective-C + Swift, four native types in one plugin, a `Control` widget, synchronous object return values, manual `ArrayBuffer` construction, plugin-wide logging category, `mock` properties, standalone Xcode framework project + framework-download script |

### Framework
- `~/git/tabris-ios` — Tabris iOS framework sources. Used for the authoritative mechanics:
  `Tabris/Tabris/Classes/BasicObject.m` (property KVC/introspection, `listenWithProperties:`,
  `callWithProperties:method:`, `registerSelector:forCall:`, `destroy`),
  `ObjectDispatch.m` (operation → selector map), `TabrisBridge.m` (the six operations),
  `TabrisNotificationsDispatcher.m` (event delivery + return value),
  `JSValue+Tabris.m` (both conversion tables), `MainScope.swift` (`TabrisPlugins.plist` loading),
  `WidgetRegistry.m`.
- `Tabris.xcframework` public headers, **version 3.9** as vendored in
  `~/git/migration-guide/build/cordova/platforms/ios/Tabris/Tabris.xcframework/…/Headers/`
  (`BasicObject.h`, `RemoteObjectProtocol.h`, `Widget.h`, `BasicWidget.h`, `WidgetProtocol.h`,
  `Control.h`, `WidgetContainer*.h`, `JSFunctionValue.h`, `ArrayBuffer.h`, `Console.h`,
  `LogEntry.h`, `PublicTypes.h`, `TabrisContext.h`, `NSDictionary+TypeSafeGetters.h`,
  `BasicObject+Shorthands.h`, `BasicObject+Logging.h`, `FloatingViewController.h`,
  `ObjectRegistry.h`, `TypeConverter.h`).

The three plugins' READMEs state compatibility with Tabris.js 3.7.0; the framework headers and
sources consulted here are newer (3.9). Where the two disagree, the discrepancy is called out in the
text rather than smoothed over.

### No conversion cache
The skill's `sources/<name>/converted/` step is not applicable: all source material is plain-text
source code already on disk at the paths above, so there is nothing to convert and no cache that
could go stale relative to the repositories.
