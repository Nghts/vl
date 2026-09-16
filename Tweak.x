#import "VBVolumeHUD.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------
// There's no per-app settings UI anymore (that was YouTube-specific), so this
// is a single global multiplier read from NSUserDefaults. Ship a Settings.bundle
// or a Preferences pane separately if you want a UI to change these values;
// for now they can be set with:
//   defaults write com.yourname.volumeboostall CustomVolumeScalar -float 3.0
// (on-device, or via a preference bundle plist under the same suite name).

static NSString *const kVolumeBoostEnabledKey = @"VolumeBoostAllEnabled";
static NSString *const kRememberVolumeEnabledKey = @"RememberVolumeEnabled";
static NSString *const kShowGestureIndicatorKey = @"ShowGestureIndicator";
static NSString *const kCustomVolumeScalarKey = @"CustomVolumeScalar";
static NSString *const kPrefsSuiteName = @"com.yourname.volumeboostall";

static BOOL cachedVolumeBoostEnabled = YES;
static BOOL cachedRememberVolumeEnabled = YES;
static BOOL cachedShowGestureIndicator = YES;
static float currentVolumeMultiplier = 1.0f;
static float cachedAudioMultiplier = 1.0f;
static BOOL preferencesLoaded = NO;

static NSHashTable *activeRenderers = nil;
static dispatch_once_t activeRenderersOnce;
static char kRendererRegisteredKey;
static char kGestureIndicatorKey;
static char kVolumePanRecognizerKey;
static char kVolumePanHandlerKey;

static const CGFloat kGestureRightInset = 44.0f;
static const CGFloat kGestureHitboxWidth = 84.0f;
static const CGFloat kGestureIndicatorWidth = 5.0f;
static const CGFloat kGestureIndicatorHeight = 62.0f;

static inline float ClampVolumeMultiplier(float multiplier) {
    if (multiplier < 0.0f) return 0.0f;
    if (multiplier > 20.0f) return 20.0f;
    return multiplier;
}

static inline float CalculateAudioMultiplier(float multiplier) {
    if (multiplier <= 1.0f) return multiplier;
    return powf(200.0f, (multiplier - 1.0f) / 19.0f);
}

static NSUserDefaults *PrefsDefaults(void) {
    static NSUserDefaults *defaults = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuiteName];
        if (!defaults) defaults = [NSUserDefaults standardUserDefaults];
    });
    return defaults;
}

static void LoadPreferencesIfNeeded(void) {
    if (preferencesLoaded) return;
    preferencesLoaded = YES;

    NSUserDefaults *defaults = PrefsDefaults();
    if ([defaults objectForKey:kVolumeBoostEnabledKey] != nil) {
        cachedVolumeBoostEnabled = [defaults boolForKey:kVolumeBoostEnabledKey];
    }
    if ([defaults objectForKey:kRememberVolumeEnabledKey] != nil) {
        cachedRememberVolumeEnabled = [defaults boolForKey:kRememberVolumeEnabledKey];
    }
    if ([defaults objectForKey:kShowGestureIndicatorKey] != nil) {
        cachedShowGestureIndicator = [defaults boolForKey:kShowGestureIndicatorKey];
    }
    if (cachedRememberVolumeEnabled && [defaults objectForKey:kCustomVolumeScalarKey] != nil) {
        currentVolumeMultiplier = ClampVolumeMultiplier([defaults floatForKey:kCustomVolumeScalarKey]);
    }
    cachedAudioMultiplier = CalculateAudioMultiplier(currentVolumeMultiplier);
}

static inline BOOL IsVolumeBoostEnabled(void) { return cachedVolumeBoostEnabled; }
static inline BOOL IsRememberVolumeEnabled(void) { return cachedRememberVolumeEnabled; }
static inline BOOL IsGestureIndicatorVisible(void) { return cachedShowGestureIndicator; }

// ---------------------------------------------------------------------------
// Generic fullscreen detection (app-agnostic — was YouTube-class-name based)
// ---------------------------------------------------------------------------

static BOOL VBWindowIsFullscreen(UIWindow *window) {
    if (!window) return NO;
    return window.bounds.size.width > window.bounds.size.height;
}

// ---------------------------------------------------------------------------
// Gesture indicator (unchanged mechanics, generalized trigger conditions)
// ---------------------------------------------------------------------------

static BOOL VBShouldShowGestureIndicator(UIWindow *window) {
    if (!window || !IsVolumeBoostEnabled() || !IsGestureIndicatorVisible() ||
        window.windowLevel != UIWindowLevelNormal) {
        return NO;
    }
    return YES;
}

static CGRect VolumeGestureHitbox(UIWindow *window) {
    if (!window) return CGRectZero;
    CGFloat width = window.bounds.size.width;
    CGFloat height = window.bounds.size.height;
    CGFloat hitboxHeight = MIN(300.0f, MAX(200.0f, height * 0.28f));
    CGFloat centerY = height * 0.50f;
    CGFloat x = MAX(0.0f, width - kGestureRightInset - kGestureHitboxWidth);
    CGFloat y = MAX(0.0f, centerY - hitboxHeight * 0.5f);
    CGFloat maxY = height - hitboxHeight;
    y = MIN(y, MAX(0.0f, maxY));
    return CGRectMake(x, y, kGestureHitboxWidth, hitboxHeight);
}

static CGRect VolumeGestureIndicatorFrame(UIWindow *window) {
    CGRect hitbox = VolumeGestureHitbox(window);
    CGFloat x = CGRectGetMidX(hitbox) - kGestureIndicatorWidth * 0.5f;
    CGFloat y = CGRectGetMidY(hitbox) - kGestureIndicatorHeight * 0.5f;
    return CGRectMake(x, y, kGestureIndicatorWidth, kGestureIndicatorHeight);
}

static void VBUpdateGestureIndicator(UIWindow *window) {
    if (!window || window.screen != [UIScreen mainScreen]) return;
    UIView *indicator = objc_getAssociatedObject(window, &kGestureIndicatorKey);
    BOOL shouldShow = VBShouldShowGestureIndicator(window);

    if (!indicator && shouldShow) {
        indicator = [[UIView alloc] initWithFrame:CGRectZero];
        indicator.userInteractionEnabled = NO;
        indicator.accessibilityElementsHidden = YES;
        if ([UIColor respondsToSelector:@selector(secondaryLabelColor)]) {
            indicator.backgroundColor = [UIColor secondaryLabelColor];
        } else {
            indicator.backgroundColor = [UIColor colorWithWhite:0.72f alpha:1.0f];
        }
        indicator.alpha = 0.72f;
        indicator.layer.cornerRadius = kGestureIndicatorWidth * 0.5f;
        objc_setAssociatedObject(window, &kGestureIndicatorKey, indicator,
                                  OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [window addSubview:indicator];
    }
    if (!indicator) return;

    indicator.hidden = !shouldShow;
    if (shouldShow) {
        indicator.frame = VolumeGestureIndicatorFrame(window);
        [window bringSubviewToFront:indicator];
    }
}

static void VBScheduleGestureIndicatorUpdate(UIWindow *window) {
    if (!window) return;
    dispatch_async(dispatch_get_main_queue(), ^{ VBUpdateGestureIndicator(window); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ VBUpdateGestureIndicator(window); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ VBUpdateGestureIndicator(window); });
}

static void VBRefreshGestureIndicators(void) {
    if (@available(iOS 13.0, *)) {
        UIApplication *application = [UIApplication sharedApplication];
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                VBUpdateGestureIndicator(window);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Renderer bookkeeping / volume math (unchanged from upstream)
// ---------------------------------------------------------------------------

static inline NSHashTable *RendererTable(void) {
    dispatch_once(&activeRenderersOnce, ^{
        activeRenderers = [NSHashTable weakObjectsHashTable];
    });
    return activeRenderers;
}

void VBRegisterRenderer(id renderer) {
    if (!renderer) return;
    if (objc_getAssociatedObject(renderer, &kRendererRegisteredKey)) return;
    objc_setAssociatedObject(renderer, &kRendererRegisteredKey, @YES,
                              OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSHashTable *table = RendererTable();
    @synchronized(table) { [table addObject:renderer]; }
}

void VBReapplyTrackedRenderers(void) {
    NSHashTable *table = RendererTable();
    NSArray *snapshot = nil;
    @synchronized(table) {
        if (table.count == 0) return;
        snapshot = [table allObjects];
    }
    for (id renderer in snapshot) {
        if ([renderer respondsToSelector:@selector(setVolume:)]) {
            [renderer setVolume:1.0f];
        }
    }
}

static inline float GetCustomVolumeMultiplier(void) { return currentVolumeMultiplier; }
static inline float GetLogarithmicAudioMultiplier(void) { return cachedAudioMultiplier; }

static void PersistCurrentVolumeIfNeeded(void) {
    if (!cachedRememberVolumeEnabled) return;
    [PrefsDefaults() setFloat:currentVolumeMultiplier forKey:kCustomVolumeScalarKey];
}

static BOOL SetCustomVolumeMultiplier(float multiplier) {
    multiplier = ClampVolumeMultiplier(multiplier);
    if (fabsf(multiplier - currentVolumeMultiplier) < 0.0001f) return NO;
    currentVolumeMultiplier = multiplier;
    cachedAudioMultiplier = CalculateAudioMultiplier(multiplier);
    VBReapplyTrackedRenderers();
    return YES;
}

// ---------------------------------------------------------------------------
// AVFoundation hooks — these fire in EVERY app since they're system frameworks
// ---------------------------------------------------------------------------

%hook AVPlayer
- (void)setVolume:(float)volume {
    VBRegisterRenderer(self);
    if (IsVolumeBoostEnabled()) volume *= GetLogarithmicAudioMultiplier();
    %orig(volume);
}
%end

%hook AVAudioPlayerNode
- (void)setVolume:(float)volume {
    VBRegisterRenderer(self);
    if (IsVolumeBoostEnabled()) volume *= GetLogarithmicAudioMultiplier();
    %orig(volume);
}
%end

%hook AVAudioPlayer
- (void)setVolume:(float)volume {
    VBRegisterRenderer(self);
    if (IsVolumeBoostEnabled()) volume *= GetLogarithmicAudioMultiplier();
    %orig(volume);
}
%end

%hook AVSampleBufferAudioRenderer
- (void)setVolume:(float)volume {
    VBRegisterRenderer(self);
    if (IsVolumeBoostEnabled()) volume *= GetLogarithmicAudioMultiplier();
    %orig(volume);
}
%end

// ---------------------------------------------------------------------------
// Named hook stub for lvsplayer's own player class.
//
// Fill in the real class name once you've pulled it from the binary, e.g.
// with `class-dump` or a Hopper/Ghidra disassembly of the lvsplayer app
// bundle's Mach-O. Search for classes implementing "setVolume:" that take
// a float. Once you have the name, uncomment and rename below — a direct
// %hook is more reliable than the runtime scanner further down because it
// doesn't depend on the method's type encoding being detectable at ctor time.
//
// %hook LVSPlayerAudioController   // <-- replace with the real class name
// - (void)setVolume:(float)volume {
//     VBRegisterRenderer(self);
//     if (IsVolumeBoostEnabled()) volume *= GetLogarithmicAudioMultiplier();
//     %orig(volume);
// }
// %end

// ---------------------------------------------------------------------------
// Generic fallback: scan loaded classes for any "- (void)setVolume:(float)"
// and swizzle them too. This is what catches lvsplayer (or anything else
// with a custom float-volume setter) without knowing its class name ahead
// of time. Classes already hooked above via %hook are skipped so they don't
// get double-multiplied.
// ---------------------------------------------------------------------------

static NSSet<NSString *> *VBAlreadyHookedClassNames(void) {
    static NSSet *set = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[
            @"AVPlayer", @"AVAudioPlayerNode", @"AVAudioPlayer",
            @"AVSampleBufferAudioRenderer"
        ]];
    });
    return set;
}

static BOOL VBMethodTakesSingleFloatArg(Method method) {
    // Type encoding for "- (void)setVolume:(float)volume" is roughly "v@:f".
    // We only check that there's exactly one argument beyond self/_cmd and
    // that it's a float ('f'), to avoid swizzling unrelated setVolume:
    // methods that take e.g. a double or an NSNumber.
    char argType[16];
    if (method_getNumberOfArguments(method) != 3) return NO;
    method_getArgumentType(method, 2, argType, sizeof(argType));
    return argType[0] == 'f';
}

static void VBGenericSetVolume(id self, SEL _cmd, float volume);
static IMP VBOriginalSetVolumeIMPForClass(Class cls);

// Store per-class original IMPs so the swizzle-replacement can call through.
static NSMapTable<Class, NSValue *> *VBOriginalIMPTable(void) {
    static NSMapTable *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = [NSMapTable strongToStrongObjectsMapTable];
    });
    return table;
}

static void VBGenericSetVolume(id self, SEL _cmd, float volume) {
    VBRegisterRenderer(self);
    float adjusted = volume;
    if (IsVolumeBoostEnabled()) adjusted *= GetLogarithmicAudioMultiplier();

    NSValue *boxedIMP = [VBOriginalIMPTable() objectForKey:[self class]];
    if (boxedIMP) {
        IMP original = [boxedIMP pointerValue];
        ((void (*)(id, SEL, float))original)(self, _cmd, adjusted);
    }
}

static void VBHookClassIfNeeded(Class cls) {
    if (!cls) return;
    const char *rawName = class_getName(cls);
    if (!rawName) return;
    NSString *className = @(rawName);
    if ([VBAlreadyHookedClassNames() containsObject:className]) return;

    // Skip if we've already swizzled this exact class.
    if ([VBOriginalIMPTable() objectForKey:cls]) return;

    SEL selector = @selector(setVolume:);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    if (!VBMethodTakesSingleFloatArg(method)) return;

    IMP originalIMP = method_getImplementation(method);
    [VBOriginalIMPTable() setObject:[NSValue valueWithPointer:originalIMP] forKey:cls];
    method_setImplementation(method, (IMP)VBGenericSetVolume);
}

static void VBScanAndHookCustomVolumeClasses(void) {
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return;

    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        // Only consider classes that declare setVolume: themselves (not
        // inherited), so we don't re-swizzle the same IMP through subclasses
        // of AVPlayer/AVAudioPlayer/etc.
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (!methods) continue;
        for (unsigned int m = 0; m < methodCount; m++) {
            if (method_getName(methods[m]) == @selector(setVolume:)) {
                VBHookClassIfNeeded(cls);
                break;
            }
        }
        free(methods);
    }
    free(classes);
}

// ---------------------------------------------------------------------------
// System-wide swipe gesture + HUD
// ---------------------------------------------------------------------------

@interface VBVolumePanGestureRecognizer : UIPanGestureRecognizer
@end
@implementation VBVolumePanGestureRecognizer
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)preventedGestureRecognizer {
    (void)preventedGestureRecognizer;
    return YES;
}
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventingGestureRecognizer {
    (void)preventingGestureRecognizer;
    return NO;
}
@end

@interface VBVolumeGestureHandler : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, assign) UIWindow *window;
@property(nonatomic, assign) float startMultiplier;
@end

@implementation VBVolumeGestureHandler

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    (void)gestureRecognizer;
    UIWindow *window = self.window;
    if (!window || !IsVolumeBoostEnabled()) return NO;
    if (window.screen != [UIScreen mainScreen] || window.windowLevel != UIWindowLevelNormal) {
        return NO;
    }
    CGPoint location = [touch locationInView:window];
    return CGRectContainsPoint(VolumeGestureHitbox(window), location);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (![gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) return YES;
    UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
    CGPoint velocity = [pan velocityInView:self.window];
    CGFloat horizontalVelocity = fabs(velocity.x);
    CGFloat verticalVelocity = fabs(velocity.y);
    if (horizontalVelocity < 6.0f && verticalVelocity < 6.0f) return NO;
    if (verticalVelocity >= horizontalVelocity * 0.55f) return YES;
    return velocity.x < 0.0f;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    (void)gestureRecognizer;
    (void)otherGestureRecognizer;
    return NO;
}

- (void)handleVolumePan:(UIPanGestureRecognizer *)pan {
    UIWindow *window = self.window;
    if (!window) return;
    switch (pan.state) {
        case UIGestureRecognizerStateBegan: {
            self.startMultiplier = GetCustomVolumeMultiplier();
            [pan setTranslation:CGPointZero inView:window];
            VBVolumeHUD *hud = [VBVolumeHUD sharedHUD];
            [NSObject cancelPreviousPerformRequestsWithTarget:hud selector:@selector(hide) object:nil];
            [hud showWithValue:self.startMultiplier];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [pan translationInView:window];
            float deltaMultiplier = -translation.y / 30.0f;
            float newMultiplier = ClampVolumeMultiplier(self.startMultiplier + deltaMultiplier);
            if (SetCustomVolumeMultiplier(newMultiplier)) {
                [[VBVolumeHUD sharedHUD] showWithValue:newMultiplier];
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            PersistCurrentVolumeIfNeeded();
            [[VBVolumeHUD sharedHUD] performSelector:@selector(hide) withObject:nil afterDelay:1.0];
            break;
        }
        default:
            break;
    }
}
@end

static void VBEnsureVolumeGestureRecognizer(UIWindow *window) {
    if (!window || window.screen != [UIScreen mainScreen]) return;
    if (objc_getAssociatedObject(window, &kVolumePanRecognizerKey)) return;

    VBVolumeGestureHandler *handler = [[VBVolumeGestureHandler alloc] init];
    handler.window = window;
    VBVolumePanGestureRecognizer *pan =
        [[VBVolumePanGestureRecognizer alloc] initWithTarget:handler action:@selector(handleVolumePan:)];
    pan.delegate = handler;
    pan.cancelsTouchesInView = YES;
    pan.delaysTouchesBegan = NO;
    pan.delaysTouchesEnded = NO;
    pan.minimumNumberOfTouches = 1;
    pan.maximumNumberOfTouches = 1;

    objc_setAssociatedObject(window, &kVolumePanHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(window, &kVolumePanRecognizerKey, pan, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [window addGestureRecognizer:pan];
}

static BOOL VBEventNeedsIndicatorRefresh(UIEvent *event) {
    NSSet<UITouch *> *touches = [event allTouches];
    if (touches.count == 0) return YES;
    for (UITouch *touch in touches) {
        if (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseEnded ||
            touch.phase == UITouchPhaseCancelled) {
            return YES;
        }
    }
    return NO;
}

%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    BOOL mainScreenWindow = self.screen == [UIScreen mainScreen];
    BOOL shouldRefresh = VBEventNeedsIndicatorRefresh(event);
    if (mainScreenWindow) {
        VBEnsureVolumeGestureRecognizer(self);
        if (shouldRefresh) VBUpdateGestureIndicator(self);
    }
    %orig(event);
    if (mainScreenWindow && shouldRefresh) VBScheduleGestureIndicatorUpdate(self);
}
%end

// ---------------------------------------------------------------------------
// Constructor: runs once per process this dylib gets loaded into (i.e. every
// UIApplication-based process, per the .plist filter). No more bundle-ID
// gate restricting this to YouTube.
// ---------------------------------------------------------------------------

%ctor {
    LoadPreferencesIfNeeded();

    // Give the app a moment to finish loading its own classes (including any
    // dynamically-loaded frameworks / plugins) before we scan for custom
    // volume setters. A short delay is more reliable than scanning at ctor
    // time immediately, since some classes register late.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        VBScanAndHookCustomVolumeClasses();
    });

    %init;
}
