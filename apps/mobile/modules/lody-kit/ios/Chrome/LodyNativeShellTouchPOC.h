#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface LodyNativeShellTouchPOC : NSObject
+ (UIGestureRecognizer *)attachToView:(UIView *)view;
+ (void)detach:(UIGestureRecognizer *)handler fromView:(UIView *)view;
@end
NS_ASSUME_NONNULL_END
