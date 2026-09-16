#import <UIKit/UIKit.h>

@interface VBVolumeHUD : UIView
@property (nonatomic, strong) UILabel *textLabel;
+ (instancetype)sharedHUD;
- (void)showWithValue:(float)value;
- (void)hide;
@end
