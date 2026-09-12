#import "LodyNativeShellTouchPOC.h"
#import <React/RCTSurfaceTouchHandler.h>

@implementation LodyNativeShellTouchPOC
+ (UIGestureRecognizer *)attachToView:(UIView *)view {
  RCTSurfaceTouchHandler *handler = [RCTSurfaceTouchHandler new];
  [handler attachToView:view];
  return handler;
}
+ (void)detach:(UIGestureRecognizer *)handler fromView:(UIView *)view {
  [(RCTSurfaceTouchHandler *)handler detachFromView:view];
}
@end
