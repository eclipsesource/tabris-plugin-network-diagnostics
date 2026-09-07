# 06 — Methods, return values and callbacks

## Registration and invocation

```swift
required init!(objectId: String!, properties: [AnyHashable : Any]!, in context: TabrisContext!) {
    super.init(objectId: objectId, properties: properties, in: context)
    self.register(#selector(self.connectShare(parameters:)), forCall: "connectShare")
}

@objc(connectShare:) public func connectShare(parameters: Dictionary<String, Any>) { … }
```

`callWithProperties:method:` looks the JS method name up in the registry and invokes the selector
with the whole properties dictionary as its single argument. An unregistered name is not an error —
it logs `Call of '<name>' on <Class> <objectId> Unhandled` and returns `nil`.

Every registered method therefore has the same shape: **one dictionary in**, at most one object out.

## Synchronous return values

`callSelector:withObject:` inspects the method signature and only captures a result when the
Objective-C return type encoding is `@`, i.e. an **object**. So:

- `NSNumber*`, `NSString*`, `NSArray*`, `NSDictionary*`, `NSData*` → reaches JS;
- `BOOL`, `NSInteger`, `double`, `void` → the return value is discarded.

Diamond exploits this throughout, wrapping booleans in `NSNumber`:

```objc
- (NSNumber*)isSupported { return @(self.currentDevice.isSupported); }
- (NSNumber*)canAdd:(NSDictionary*)parameters { … return @(canAddPaymentPass); }
- (NSArray*)list:(NSDictionary*)parameters { … return diamonds; }
```
```js
isSupported(parameters) { return this._nativeCall('isSupported', parameters); }
list(parameters)        { return this._nativeCall('list', parameters); }
```

The value is converted by `JSValue withNativeObject:inContext:` (`08_data_types.md`), so
`NSNumber` booleans arrive as JS booleans and `NSData` arrives as an `ArrayBuffer`.

In Swift, return `NSNumber`/`NSArray`/`NSDictionary`/`String` — a Swift `Bool` or `Int` return does
not bridge to an object encoding. None of the Swift reference implementations returns anything; they
are all callback-based.

**A synchronous return only works for work that is genuinely synchronous.** Diamond's `activate:`
returns `@1` to mean "accepted, started" and delivers the real outcome later through the
`activationFinished` event.

## `JSFunctionValue` — callbacks

A JS function inside the parameters dictionary is converted to a `JSFunctionValue`
(`Tabris/JSFunctionValue.h`):

```objc
@interface JSFunctionValue : NSObject
@property (nonatomic, readonly) JSContext* context;
@property (strong, nonatomic, readonly) JSValue* function;
+ (BOOL)valueIsJSFunction:(JSValue*)value;
- (id)initWithValue:(JSValue*)value;
- (id)callWithParameters:(NSArray*)parameters;
@end
```

Swift usage:
```swift
guard let completion = parameters["completion"] as? JSFunctionValue else {
    jsConsoleLog("Completion callback is missing in parameters list. …")
    return
}
completion.call(withParameters: [])                       // success, no payload
completion.call(withParameters: [error.localizedDescription])   // failure
completion.call(withParameters: [NSNull(), plainFiles])   // success with payload
```
Objective-C usage: `JSFunctionValue* fn = [parameters JSFunctionValueForKey:@"ctx"];`

The callback may be stored and called repeatedly — SMB2 keeps a `progress` callback and calls it per
chunk. It can also be called many times before the completion fires.

## Error-first convention

Both Swift plugins use the Node-style contract: **argument 0 is the error, or `NSNull`**.

`SMBClient` inline:
```swift
client.contentsOfDirectory(atPath: path, recursive: recursive, completionHandler: { result in
    switch result {
    case .success(let files):
        completion.call(withParameters: [NSNull(), files.map { $0.AMSMB2ResourceToTabrisObject() }])
    case .failure(let error):
        completion.call(withParameters: [error.localizedDescription])
    }
})
```

OIDC factors it into three overloads:
```swift
func getCompletion(_ properties: Dictionary<String, Any>) -> JSFunctionValue? {
    guard let completion = properties["completion"] as? JSFunctionValue else {
        logError("Completion callback is missing in parameters list."); return nil
    }
    return completion
}
func complete(with parameters: [Any], completion: JSFunctionValue?) {
    if completion != nil { completion!.call(withParameters: [NSNull()] + parameters) }
}
func complete(with error: Error, completion: JSFunctionValue?) {
    complete(with: error.localizedDescription, completion: completion)
}
func complete(with error: String, completion: JSFunctionValue?) {
    if completion != nil { completion!.call(withParameters: [error]) }
}
```

Paired with the JS Promise wrapper from `04_javascript_module.md`, every native method becomes an
`await`-able call and every native error becomes a rejected `Error`. This is the pattern to copy.

## The nested-parameters layout

OIDC's wrapper sends `{parameters: {...}, completion: fn}`, so the native method unwraps twice:

```swift
@objc(authenticate:) public func authenticate(properties: Dictionary<String, Any>) {
    do {
        guard let parameters = properties["parameters"] as? [String: Any] else {
            throw OpenIDConnectError("Parameters missing.")
        }
        …
    } catch {
        self.complete(with: error, completion: getCompletion(properties))
    }
}
```

The `do`/`catch` wrapping the whole body plus `complete(with: error, …)` in the `catch` means every
thrown error — including the ones from `OIDAuthorizationRequest(tabrisParameters:)` — becomes a
rejected Promise instead of a crash. Note that async work needs its own `catch` inside the closure;
`authenticate` repeats the pattern inside the `present` completion block.

## Progress callbacks

`uploadItem` shows an optional secondary callback whose presence also acts as a cancel flag —
AMSMB2 continues while the progress block returns `true`:

```swift
let progress = parameters["progress"] as? JSFunctionValue
client.uploadItem(at: sourceURL, toPath: destination, progress: { bytes in
    progress?.call(withParameters: [["bytes": bytes]])
    return progress != nil
}, completionHandler: { error in … })
```

## Validation style

Validate every parameter and report through the callback rather than crashing. `SMBClient` reports a
missing *callback* to the console (there is nowhere else to send it) and everything else through the
callback:

```swift
guard let completion = parameters["completion"] as? JSFunctionValue else {
    jsConsoleLog("Completion callback is missing in parameters list. `connectShare` method will not be executed.")
    return
}
guard let share = parameters["share"] as? String else {
    completion.call(withParameters: ["`share` parameter is missing. `connectShare` method will not be executed."])
    return
}
guard let client = client else {
    completion.call(withParameters: ["`client` does not exist. Did you set `user` and `password` and `serverURL` (with smb:// scheme)? …"])
    return
}
```

Optional parameters get a default in place: `let recursive = parameters["recursive"] as? Bool ?? false`.
