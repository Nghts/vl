#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString * const VBSettingsSuite = @"com.yourname.volumeboostall";
static NSString * const VBMultiplierKey = @"CustomVolumeScalar";
static char VBPanelKey;
static char VBLongPressKey;

@interface VBSettingsPanel : UIView
@property(nonatomic,strong) UISlider *slider;
@property(nonatomic,strong) UILabel *valueLabel;
@end

@implementation VBSettingsPanel
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
        self.layer.cornerRadius = 14.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
        self.layer.shadowOpacity = 0.3;
        self.layer.shadowRadius = 8.0;
        self.layer.shadowOffset = CGSizeMake(0, 3);

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, 190, 24)];
        title.text = @"VolumeBoostAll";
        title.textColor = UIColor.whiteColor;
        title.font = [UIFont boldSystemFontOfSize:16];
        [self addSubview:title];

        self.valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(205, 10, 55, 24)];
        self.valueLabel.textAlignment = NSTextAlignmentRight;
        self.valueLabel.textColor = UIColor.whiteColor;
        self.valueLabel.font = [UIFont systemFontOfSize:15];
        [self addSubview:self.valueLabel];

        self.slider = [[UISlider alloc] initWithFrame:CGRectMake(14, 40, 246, 30)];
        self.slider.minimumValue = 0.0f;
        self.slider.maximumValue = 20.0f;
        self.slider.continuous = YES;
        [self.slider addTarget:self action:@selector(valueChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.slider];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(220, 74, 45, 25);
        [close setTitle:@"Done" forState:UIControlStateNormal];
        [close addTarget:self action:@selector(close:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:close];

        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:VBSettingsSuite];
        float value = [defaults objectForKey:VBMultiplierKey] ? [defaults floatForKey:VBMultiplierKey] : 1.0f;
        self.slider.value = MAX(0.0f, MIN(20.0f, value));
        [self updateLabel];
    }
    return self;
}
- (void)updateLabel {
    self.valueLabel.text = [NSString stringWithFormat:@"%.1f×", self.slider.value];
}
- (void)valueChanged:(UISlider *)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:VBSettingsSuite];
    [defaults setFloat:sender.value forKey:VBMultiplierKey];
    [defaults synchronize];
    [self updateLabel];
}
- (void)close:(id)sender {
    (void)sender;
    UIWindow *window = self.window;
    objc_setAssociatedObject(window, &VBPanelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self removeFromSuperview];
}
@end

@interface VBSettingsLongPressTarget : NSObject
@property(nonatomic,assign) __unsafe_unretained UIWindow *window;
@end

@implementation VBSettingsLongPressTarget
- (void)showPanel:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIWindow *window = self.window;
    if (!window || objc_getAssociatedObject(window, &VBPanelKey)) return;
    CGFloat x = MAX(10.0f, CGRectGetWidth(window.bounds) - 290.0f);
    VBSettingsPanel *panel = [[VBSettingsPanel alloc] initWithFrame:CGRectMake(x, 70.0f, 280.0f, 108.0f)];
    panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    objc_setAssociatedObject(window, &VBPanelKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [window addSubview:panel];
    [window bringSubviewToFront:panel];
}
@end

static void VBInstallSettingsLongPress(void) {
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.screen != UIScreen.mainScreen || objc_getAssociatedObject(window, &VBLongPressKey)) continue;
        VBSettingsLongPressTarget *target = [VBSettingsLongPressTarget new];
        target.window = window;
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:target action:@selector(showPanel:)];
        press.minimumPressDuration = 1.0;
        press.cancelsTouchesInView = NO;
        objc_setAssociatedObject(window, &VBLongPressKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [window addGestureRecognizer:press];
    }
}

__attribute__((constructor)) static void VBSettingsConstructor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        VBInstallSettingsLongPress();
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            (void)note;
            VBInstallSettingsLongPress();
        }];
    });
}
