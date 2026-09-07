# 09 — Widgets (visual plugins)

## Class hierarchy

```
NSObject
└─ BasicObject                  non-visual remote object
   └─ BasicWidget               layout, bounds, background, font, enabled, visible, opacity, …
      └─ Widget                 + clientLayout, -defineWidgetView:
         └─ WidgetContainer     + addWidgetView: / removeWidgetView:
            └─ Control          + interactiveWhenEnabled, -adjustUserInteraction
```

Which to subclass:

| Base | Use for |
|------|---------|
| `Widget` | a leaf view that takes no children |
| `WidgetContainer` | a view that hosts Tabris.js children |
| `Control` | an interactive leaf control (buttons, inputs) — this is what `AddDiamondButton` uses |

`BasicWidget` already declares the whole Tabris.js widget property surface (`bounds`,
`absoluteBounds`, `foreground`, `textColor`, `font`, `data`, `enabled`, `visible`, `layoutData`,
`opacity`, `transform`, `background`, `backgroundImage`, `cornerRadius`, `elevation`, `padding`,
`clipChildren`) plus `- (NSString *)screenshot`. You inherit all of it; only add what is specific to
your widget.

## Complete widget example

Header — note the base class is the only content:
```objc
#import <UIKit/UIKit.h>
#import <Tabris/Tabris.h>

@interface AddDiamondButton : Control
@end
```

Implementation:
```objc
static NSString* AddDiamondButtonSelectEvent = @"select";

@interface AddDiamondButton()
@property (strong, nonatomic) PKAddPassButton* button;
@property (assign, nonatomic) BOOL selectListener;
@end

@implementation AddDiamondButton

+ (NSString *)remoteObjectType { return @"com.eclipsesource.AddDiamondButton"; }

+ (NSMutableSet *)remoteObjectProperties {
    NSMutableSet* set = [super remoteObjectProperties];
    [set addObject:@"style"];
    return set;
}

- (instancetype)initWithObjectId:(NSString *)objectId
                      properties:(NSDictionary *)properties
                       inContext:(id<TabrisContext>)context {
    self = [super initWithObjectId:objectId properties:properties inContext:context];
    if (self) {
        PKAddPassButtonStyle style = [[properties stringForKey:@"style"] isEqualToString:@"blackOutline"]
            ? PKAddPassButtonStyleBlackOutline : PKAddPassButtonStyleBlack;
        self.button = [[PKAddPassButton alloc] initWithAddPassButtonStyle:style];
        [self.button addTarget:self
                        action:@selector(buttonTouchedUpInside:)
              forControlEvents:UIControlEventTouchUpInside];

        [self defineWidgetView:self.button];       // <- the essential call

        self.interactiveWhenEnabled = YES;
        [self adjustUserInteraction];
    }
    return self;
}

- (void)buttonTouchedUpInside:(id)sender {
    if (self.selectListener) {
        [self fireEventNamed:AddDiamondButtonSelectEvent withAttributes:@{}];
    }
}
@end
```

JS side — the whole file:
```js
class AddDiamondButton extends tabris.Widget {
  get _nativeType() { return 'com.eclipsesource.AddDiamondButton'; }
}

tabris.NativeObject.defineEvents(AddDiamondButton.prototype, {
  select: {native: true}
});

tabris.NativeObject.defineProperties(AddDiamondButton.prototype, {
  style: { type: 'string', choice: ['black', 'blackOutline'], default: 'black', const: true }
});

module.exports = AddDiamondButton;
```

App usage — a widget behaves like any built-in one:
```js
let blackButton = new es.AddDiamondButton({style: 'black'});
blackButton.on('select', () => { … });
stack.append(blackButton);
```

## `defineWidgetView:`

```objc
- (void)defineWidgetView:(UIView*)widgetView;   // Widget.h
```
Hands the framework the `UIView` this widget represents. Everything else — embedding into the parent,
constraints, `transform`, screenshots, background drawing — is derived from it. Call it once, in the
initializer, after the view is fully constructed.

`BasicWidget` exposes the result as `@property (readonly) UIView *definedWidgetView`.

## The four view roles (`WidgetProtocol.h`)

A widget can return a *different* view for each responsibility. Defaults are usually right; override
only when they are not:

| Method | Purpose | Default |
|--------|---------|---------|
| `viewToEmbed` | inserted into the parent's hierarchy; target of transforms, constraints, screenshots | the defined widget view |
| `viewForEmbedding` | where children are added when this widget is a parent | `nil` — no subviews accepted (a leaf) |
| `viewForGestureRecognizers` | gesture recognizers and `highlightOnTouch` attach here | `viewToEmbed` |
| `viewForDrawing` | `highlightOnTouch` overlay (historically corner radius, background, opacity, shadow) | `definedWidgetView` |

The header's own example: `Toolbar` can have children (`Actions`) but `UIBarButtonItem`s are not
`addSubview:`-able, so it returns `nil` from `viewForEmbedding` while still owning children.

There is also `boundsReferenceCoordinateSystem` — set it when the default `bounds` is wrong because
an ancestor view (e.g. a `UICollectionViewCell` wrapping a cell widget) is not yet on screen.

## Interaction

```objc
@interface Control : WidgetContainer
@property (assign, nonatomic) BOOL interactiveWhenEnabled;
- (void)adjustUserInteraction;
- (BOOL)shouldEnableUserInteraction;
@end
```

Set `interactiveWhenEnabled = YES` for a control that must receive touches whenever `enabled` is
true, then call `adjustUserInteraction` once so the current state is applied. `Control` re-applies it
on relevant property changes.

## `const` properties

A property the underlying `UIView` cannot change after construction — `PKAddPassButton`'s style, for
example — should be `const: true` on the JS side. JS then only allows it in the constructor, so the
value is guaranteed to be present in the `properties` dictionary of the initializer. Combine it with
`choice: [...]` to validate in JS instead of natively.

## Children

To accept Tabris.js children, subclass `WidgetContainer` and implement:
```objc
- (void)addWidgetView:(id <WidgetProtocol>)widget;
- (void)removeWidgetView:(id <WidgetProtocol>)widget;
```
The `children` key is part of `remoteObjectProperties` from the very base (`BasicObject` returns
`[NSMutableSet setWithObject:@"children"]`) and is maintained by `-setChildren:`, which diffs the old
and new arrays and calls `attachChildWithIdentifier:` / `detachChildWithIdentifier:` accordingly.
`depth` is propagated automatically, and `destroy` destroys children recursively.

None of the three reference plugins implements a container — `AddDiamondButton` is the only widget
and it is a leaf.
