#import "VBVolumeHUD.h"

@implementation VBVolumeHUD

+ (instancetype)sharedHUD {
    static VBVolumeHUD *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[VBVolumeHUD alloc] initWithFrame:CGRectMake(0, 0, 120, 44)];
        shared.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.65];
        shared.layer.cornerRadius = 12.0;
        shared.alpha = 0.0;
        shared.userInteractionEnabled = NO;
        shared.translatesAutoresizingMaskIntoConstraints = YES;

        UILabel *label = [[UILabel alloc] initWithFrame:shared.bounds];
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont boldSystemFontOfSize:18];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [shared addSubview:label];
        shared.textLabel = label;
    });
    return shared;
}

- (void)showWithValue:(float)value {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                window = ((UIWindowScene *)scene).windows.firstObject;
                if (window) break;
            }
        }
    }
    if (!window) return;

    if (self.superview != window) {
        [window addSubview:self];
    }
    self.center = CGPointMake(window.bounds.size.width / 2.0,
                               window.bounds.size.height * 0.15);
    self.textLabel.text = [NSString stringWithFormat:@"%.0f%%", value * 100.0];
    [window bringSubviewToFront:self];

    [UIView animateWithDuration:0.15 animations:^{
        self.alpha = 1.0;
    }];
}

- (void)hide {
    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 0.0;
    }];
}

@end
