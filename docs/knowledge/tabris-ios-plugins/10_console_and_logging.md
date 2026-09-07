# 10 — Console and logging

## Why it matters

`print`/`NSLog` from a plugin is invisible to the app developer. The Tabris.js developer console is
the only channel that shows up next to the app's own `console.log` output. Enable it with
`<preference name="EnableDeveloperConsole" value="true" />` in the app's `config.xml`.

## The API

```objc
// Console.h
@protocol ConsoleEntry
@property (readonly) NSString* text;
@property (readonly) ConsoleEntryType type;
- (BOOL)isEqualToConsoleEntry:(id<ConsoleEntry>)consoleEntry;
@end

@protocol Console
- (void)display:(id<ConsoleEntry>)entry;
@end
```

The sink is `self.context.console` (`id<Console>`, weak, may be `nil`).

`ConsoleEntryType` (`PublicTypes.h`) — the raw values matter, because Swift code in the reference
plugins constructs the enum from them:

| Value | Case |
|-------|------|
| 1 | `Debugging` |
| 2 | `Message` |
| 3 | `Info` |
| 4 | `Warning` |
| 5 | `Error` |
| 6 | `Command` |
| 7 | `ReturnValue` |

`PublicTypes.h` also declares `LogLevel` (`LogLevelOff` 0 … `LogLevelTrace` 600, `LogLevelAll`),
used by `BasicObject+Logging.h`:
```objc
- (void)logLevel:(LogLevel)messageLogLevel message:(NSString *)format, ...;
- (void)log:(NSString*)message level:(LogLevel)messageLogLevel;
- (void)logCallToSelector:(SEL)aSelector arguments:(NSArray*)arguments;
- (void)log:(Class)aClass selector:(SEL)aSelector arguments:(NSArray*)arguments;
```
That category writes to the framework's internal logger, not the JS console. None of the three
reference plugins uses it — they all go through `context.console`.

## Option A — reuse `LogEntry` (simplest)

`LogEntry` is a ready-made `ConsoleEntry` with factory methods for each type
(`entryWithMessage:andType:`, `entryWithInfo:`, `entryWithWarning:`, `entryWithError:`,
`entryWithDebug:`, …). `SMBClient` does exactly this:

```swift
func jsConsoleLog(_ message: String, type: ConsoleEntryType = Error) {
    guard let logEntry = LogEntry(message: "[SMBClient] ".appending(message), andType: type) else { return }
    context.console?.display(logEntry)
}
```
Note `Error` here is the `ConsoleEntryType` case from `PublicTypes.h`, not `Swift.Error`.

Prefer this for new code — one function, no extra type.

## Option B — a custom `ConsoleEntry` type

`SwiftObject` and `OpenIDConnect` declare their own nested conformance:

```swift
class OpenIDConnectConsoleEntry: ConsoleEntry {
    let text: String
    let type: ConsoleEntryType

    init(text: String, type: ConsoleEntryType) {
        self.text = text
        self.type = type
    }

    func isEqual(to consoleEntry: ConsoleEntry) -> Bool {
        return text == consoleEntry.text && type == consoleEntry.type
    }
}
```
`isEqualToConsoleEntry:` imports into Swift as `isEqual(to:)`.

Then two levels, with info gated by a JS-settable property:

```swift
@objc public var infoLogging = false

func logInfo(_ message: String) {
    guard infoLogging else { return }
    let entry = OpenIDConnectConsoleEntry(text: message, type: ConsoleEntryType(rawValue: 3))   // Info
    self.context.console?.display(entry)
}

func logError(_ message: String) {
    let text = "[\(self.description)] ".appending(message)
    let entry = OpenIDConnectConsoleEntry(text: text, type: ConsoleEntryType(rawValue: 5))      // Error
    self.context.console?.display(entry)
}

func logError(_ error: Error) { logError(error.localizedDescription) }
```

Errors are always shown; info is opt-in via `appAuth.infoLogging = true`. Use `#function` to get the
call site for free:
```swift
logInfo("\(#function): \(String(describing: authState)), \(error?.localizedDescription ?? "nil")")
```

## Option C — a plugin-wide logging category (Objective-C, multi-class plugin)

Diamond has four native classes, so it puts one variadic logger on `BasicObject` and keeps a global
console reference that a property setter arms:

```objc
// DiamondLogging.h
extern id<Console> diamondConsole;
void jsDebug(NSString* message);

@interface BasicObject (DiamondLogging)
- (void)diamondLog:(NSString *)format, ...;
@end
```

```objc
// DiamondLogging.m
id<Console> diamondConsole = nil;
static NSString* pluginDebugMessagePrefix = @"[TPD]: ";

@interface DiamondConsoleMessage : NSObject<ConsoleEntry>
@property (strong, nonatomic, readwrite) NSString* text;
@property (nonatomic, readwrite) ConsoleEntryType type;
@end

@implementation DiamondConsoleMessage
+ (instancetype)with:(NSString*)text {
    DiamondConsoleMessage* message = [[DiamondConsoleMessage alloc] init];
    message.text = [pluginDebugMessagePrefix stringByAppendingString:text];
    message.type = Debugging;
    return message;
}
- (BOOL)isEqualToConsoleEntry:(nonnull id<ConsoleEntry>)consoleEntry {
    return [self.text isEqualToString:consoleEntry.text] && self.type == consoleEntry.type;
}
@end

@implementation BasicObject (DiamondLogging)
- (void)diamondLog:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString* newFormat = [NSString stringWithFormat:@"[%@]: %@", self, format];
    NSString* message = [[NSString alloc] initWithFormat:newFormat arguments:args];
    jsDebug(message);
    va_end(args);
}
@end

void jsDebug(NSString* message) { [diamondConsole display:[DiamondConsoleMessage with:message]]; }
```

Armed from a JS-settable property on the "main" class:
```objc
- (void)setLogging:(BOOL)logging {
    _logging = logging;
    diamondConsole = logging ? self.context.console : nil;
}
```
```js
diamondLibrary.logging = true;   // global for the whole plugin
```

Every line is prefixed twice — `[TPD]:` identifies the plugin and `[<ClassName objectId pointer>]:`
identifies the instance (which is why the `description` override from `03_native_object_swift.md`
matters). Free functions such as the PassKit converters call `jsDebug()` directly since they have no
`self`.

Trade-offs: one call site, works from anywhere including categories and free functions, and it
degrades to a no-op when `diamondConsole` is `nil`. The costs are a global variable and a category on
a framework class — fine for a plugin, not something to expose in a library.

## What to log

From the reference plugins, the lines that actually earn their place:

- object construction: `[self diamondLog:@"initializing"];`
- every method entry with its parameters: `[self diamondLog:@"run with parameters: %@", parameters];`
- each SDK precondition that failed: `[PKPassLibrary isPassLibraryAvailable] returned false`
- every missing or mistyped parameter, quoting the whole dictionary
- the "no listener" branch of an event
- the branch actually taken on version-conditional code:
  `@"Running on iOS 13.4 or higher, activating PKSecureElementPass"`
- completion results: `@"activatePaymentPass: %@ finished successfully: %i with error: %@"`

Guidance that follows: an error the app can act on goes through the callback or an event (type
`Error`); everything else is `Debugging`/`Info` behind an opt-in flag.
