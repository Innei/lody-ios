import ExpoModulesCore
import UIKit

public final class LodyAccentSubscriber: ExpoAppDelegateSubscriber {
  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    lodyApplyWindowAccent()
    return true
  }

  public func applicationDidBecomeActive(_ application: UIApplication) {
    lodyApplyWindowAccent()
    #if DEBUG
    GlassTransitionSpike.openIfRequested()
    #endif
  }
}
