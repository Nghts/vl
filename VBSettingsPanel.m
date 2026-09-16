#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString * const VBSettingsSuite = @"com.yourname.volumeboostall";
static NSString * const VBMultiplierKey = @"CustomVolumeScalar";
static NSString * const VBEnabledKey = @"VolumeBoostAllEnabled";
static char VBPanelKey;

@interface VBSettingsPanel : UIView
@property(nonatomic,strong) UISlider *slider;
@property(nonatomic,strong) UILabel *valueLabel;
@end

@implementation VBSettingsPanel
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
        self.layer.cornerRadius = 14.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
        self.layer.shadowOpacity = 0.3;
        self.layer.shadowRadius = 8.0;
        self.layer.shadowOffset = CGSizeMake(0, 3);
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, 190, 24)];
        title.text = @"VolumeBoostAll"; title.textColor = UIColor.whiteColor;
        title.font = [UIFont boldSystemFontOfSize:16]; [self addSubview:title];
        self.valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(205, 10, 55, 24)];
        self.valueLabel.textAlignment = NSTextAlignmentRight; self.valueLabel.textColor = UIColor.whiteColor;
        self.valueLabel.font = [UIFont systemFontOfSize:15]; [self addSubview:self.valueLabel];
        self.slider = [[UISlider alloc] initWithFrame:CGRectMake(14, 40, 246, 30)];
        self.slider.minimumValue = 0; self.slider.maximumValue = 20;
        [self.slider addTarget:self action:@selector(valueChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.slider];
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(220, 74, 45, 25); [close setTitle:@"Done" forState:UIControlStateNormal];
        [close addTarget:self action:@selector(close:) forControlEvents:UIControlEventTouchUpInside]; [self addSubview:close];
        NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:VBSettingsSuite];
        float value = [d objectForKey:VBMultiplierKey] ? [d floatForKey:VBMultiplierKey] : 1.0f;
        self.slider.value = MAX(0, MIN(20, value)); [self updateLabel];
    }
    return self;
}
- (void)updateLabel { self.valueLabel.text = [NSString stringWithFormat:@"%.1f×", self.slider.value]; }
- (void)valueChanged:(UISlider *)sender {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:VBSettingsSuite];
    [d setFloat:sender.value forKey:VBMultiplierKey]; [d synchronize]; [self updateLabel];
}
- (void)close:(id)sender { (void)sender; [self removeFromSuperview]; }
@end

static void VBShowSettingsPanel(UIWindow *window) {
    if (!window || objc_getAssociatedObject(window, &VBPanelKey)) return;
    VBSettingsPanel *panel = [[VBSettingsPanel alloc] initWithFrame:CGRectMake(CGRectGetWidth(window.bounds)-290, 70, 280, 108)];
    panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    objc_setAssociatedObject(window, &VBPanelKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [window addSubview:panel];
}

static void VBInstallSettingsLongPress(void) {
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.screen == UIScreen.mainScreen && !objc_getAssociatedObject(window, &VBPanelKey)) {
            UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:[NSBlockOperation blockOperationWithBlock:^{}] action:nil];
            press.minimumPressDuration = 1.0;
            [window addGestureRecognizer:press];
            // A separate target is retained by the gesture recognizer through its target list.
            [press addTarget:[VBSettingsPanel class] action:@selector(description)];
            objc_setAssociatedObject(window, "VBSettingsPress", press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

__attribute__((constructor)) static void VBSettingsConstructor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            (void)note; VBInstallSettingsLongPress();
        }];
    });
}
