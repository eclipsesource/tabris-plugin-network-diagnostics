# 11 — `TabrisContext`, presenting UI, app integration

## `TabrisContext`

Every `BasicObject` holds `self.context` (`id<TabrisContext>`). The members a plugin realistically
uses (full list in `TabrisContext.h`):

| Member | Use |
|--------|-----|
| `console` | the JS developer console (`10_console_and_logging.md`) |
| `viewController` | the app's root view controller |
| `objectRegistry` | look up another remote object by id |
| `jsContext` | the JavaScriptCore context (low-level; prefer `JSFunctionValue.context`) |
| `syncCodeDispatcher` / `asyncCodeDispatcher` | dispatch onto the JS thread |
| `URLSession`, `HTTPClient`, `strictSSL`, `certificateValidator` | networking that honours the app's TLS settings |
| `statusBar`, `drawer` | status bar and drawer control |
| `fontHelper` | resolve a Tabris.js font description to a `UIFont` |
| `permissionProviderStore` | permission plumbing |
| `env`, `OSUtil`, `devTools`, `cameraProvider`, `notificationsDispatcher`, `tabrisImageCache`, `URLResolver` | the rest of the runtime |

Everything is `weak` and nullable — always `?.` / nil-check. The reference plugins only ever touch
`context.console`.

## `BasicObject+Shorthands`

Convenience wrappers that save you from digging into the context:

```objc
- (BOOL)askToOpenURL:(NSURL *)url completionHandler:(BooleanBlock)completion;
- (NSURL*)URLForString:(NSString *)string;
- (id<RemoteObject>)objectById:(NSString *)objectId;
- (FloatingViewController*)newFloatingViewController;
- (TabrisImage*)tabrisImageWithPropertiesObject:(NSObject*)propertiesObject;
- (FontHelper*)fontHelper;
- (id<StatusBarControl>)statusBar;
```

- `URLForString:` resolves relative and app-scheme URLs the way the rest of the framework does — use
  it instead of `NSURL(string:)` for anything that may come from the app bundle.
- `objectById:` is how one native object reaches another remote object.
- `tabrisImageWithPropertiesObject:` converts a Tabris.js image descriptor to a `TabrisImage`.

## Presenting native UI: `FloatingViewController`

A plugin must not push onto the app's navigation stack. Instead ask for a floating controller in its
own window:

```objc
@interface FloatingViewController : UIViewController
@property (nonatomic) UIWindowLevel windowLevel;
@property (strong, nonatomic) id<StatusBarControl> statusBar;
@property (nonatomic, copy) void (^viewDidLayoutSubviewsCallback)(UIView* view);
@end
```

`newFloatingViewController` creates one and registers it with the object, so `BasicObject.dealloc`
dismisses any that are still presented.

**Objective-C (Diamond)** — present the SDK's own controller:
```objc
self.floatingViewController = [self newFloatingViewController];
[self.floatingViewController presentViewController:viewController animated:true completion:^{
    [self fireIfNeeded:presentedAddDiamondViewEvent attributes:@{}];
}];
…
[self.floatingViewController dismissViewControllerAnimated:YES completion:^{
    self.floatingViewController = nil;
}];
```

**Swift (OIDC)** — the SDK needs a *presenting* controller, so a blank full-screen controller is
presented first and handed to AppAuth:
```swift
private var floatingViewController: FloatingViewController?

let blank = { () -> UIViewController in
    let vc = UIViewController()
    vc.modalPresentationStyle = .fullScreen
    return vc
}()

self.floatingViewController = newFloatingViewController()
guard let floatingViewController = self.floatingViewController else { return }

floatingViewController.present(blank, animated: false) {
    do {
        let request = try OIDAuthorizationRequest(tabrisParameters: parameters)
        self.userAgentSession = OIDAuthState.authState(
            byPresenting: request, presenting: self.blank, callback: authStateCompletion)
    } catch {
        self.complete(with: error, completion: self.getCompletion(properties))
        floatingViewController.dismiss(animated: false, completion: nil)
    }
}
```

Rules that fall out of both implementations:
- keep a strong reference for the lifetime of the presentation, and nil it in the dismiss completion;
- dismiss on **every** exit path, including the error paths (`animated: false` when nothing was ever
  shown to the user);
- fire a "UI is up" event (`presentedAddDiamondView`) so the app can react;
- offer an explicit `cancel` method that tears the UI down — `AddDiamondWorkflow.cancel:` synthesises
  an `NSError` and routes it through the same delegate callback as a real failure, so there is one
  teardown path:
  ```objc
  NSError* error = [NSError errorWithDomain:@"TabrisDiamondPluginError" code:-2
                                   userInfo:@{NSLocalizedDescriptionKey: @"JavaScript Application canceled the workflow."}];
  [self addPaymentPassViewController:nil didFinishAddingPaymentPass:nil error:error];
  ```

## Receiving app-level callbacks (URL schemes)

Cordova/Tabris owns the `UIApplicationDelegate`, so a plugin cannot implement
`application:openURL:options:`. The framework instead posts a notification, and a plugin subscribes
in its initializer:

```swift
NotificationCenter.default.addObserver(
    forName: NSNotification.Name(rawValue: "ESNSApplicationOpenURL"),
    object: UIApplication.shared,
    queue: nil) { notification in
        guard let url = notification.userInfo?["url"] as? URL,
              let result = notification.userInfo?["result"] as? NSMutableData else { return }

        self.userAgentSession?.resumeExternalUserAgentFlow(with: url)
        result.setData(Data(repeating: 1, count: 1))
    }

deinit { NotificationCenter.default.removeObserver(self) }
```

Mechanics:
- notification name `ESNSApplicationOpenURL`, posted on `UIApplication.shared`;
- `userInfo["url"]` is the incoming `URL`;
- `userInfo["result"]` is an `NSMutableData` **out-parameter** — write a non-empty value into it to
  report "handled". Leave it untouched for a URL that is not yours, so other observers still get a
  chance.
- always balance the observer in `deinit`.

OIDC's README notes that no `CFBundleURLSchemes` entry is needed for its flow, because AppAuth's
redirect URL uses the app's own bundle-id-based scheme, which Cordova already registers. A plugin
that needs a custom scheme would add it via `<config-file target="*-Info.plist">` in `plugin.xml`.

For outbound URLs use `askToOpenURL:completionHandler:` rather than `UIApplication.open` — it goes
through the client delegate, which the host app can override.

## Persisting state — do it in JavaScript

OIDC hands its whole serialised auth state to JS and lets the app store it:

```swift
let data = try NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: true)
complete(with: [data], completion: getCompletion(properties))
```
```swift
authState = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: authenticationStateData)
```
```js
secureStorage.setItem('authState', encodedState);   // app code, example/src/app.js
```

The plugin stays stateless across launches; the app decides where the bytes live (`secureStorage`,
a file, a backend). Pair it with an event (`authStateChanged`) so the app knows when to re-persist.
