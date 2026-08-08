import Foundation
import UIComponents
import WalletContext

enum DrawerAnimationExperiment {
    static let exposedMainWidthUserDefaultsKey = "experimental_drawerExposedMainWidth"
    static let parallaxFactorUserDefaultsKey = "experimental_drawerParallaxFactor"
    static let minimumScaleUserDefaultsKey = "experimental_drawerMinimumScale"
    static let openMainContentOpacityUserDefaultsKey = "experimental_drawerOpenMainContentOpacity"
    static let minimumDrawerOpacityUserDefaultsKey = "experimental_drawerMinimumOpacity"
    static let transitionDurationUserDefaultsKey = "experimental_drawerTransitionDuration"
    static let minimumTransitionDurationUserDefaultsKey = "experimental_drawerMinimumTransitionDuration"
    static let springDampingRatioUserDefaultsKey = "experimental_drawerSpringDampingRatio"
    static let overscrollReturnDurationUserDefaultsKey = "experimental_drawerOverscrollReturnDuration"

    static let defaultExposedMainWidth = 52.0
    static let defaultParallaxFactor = 0.08
    static let defaultMinimumScale = 1.0
    static let defaultOpenMainContentOpacity = 0.5
    static let defaultMinimumDrawerOpacity = 0.76
    static let defaultTransitionDuration = 0.42
    static let defaultMinimumTransitionDuration = 0.18
    static let defaultSpringDampingRatio = 0.92
    static let defaultOverscrollReturnDuration = 0.28

    static let didChangeNotification = Notification.Name("DrawerAnimationExperimentDidChange")

    static var configuration: DrawerContainerConfiguration {
        DrawerContainerConfiguration(
            maximumDrawerWidth: .greatestFiniteMagnitude,
            minimumExposedMainWidth: value(
                forKey: exposedMainWidthUserDefaultsKey,
                default: defaultExposedMainWidth,
                range: 16...200
            ),
            drawerBackgroundColor: .air.groupedBackground,
            openMainContentOpacity: value(
                forKey: openMainContentOpacityUserDefaultsKey,
                default: defaultOpenMainContentOpacity,
                range: 0...1
            ),
            drawerParallaxFactor: value(
                forKey: parallaxFactorUserDefaultsKey,
                default: defaultParallaxFactor,
                range: 0...0.3
            ),
            drawerMinimumScale: value(
                forKey: minimumScaleUserDefaultsKey,
                default: defaultMinimumScale,
                range: 0.85...1
            ),
            drawerMinimumOpacity: value(
                forKey: minimumDrawerOpacityUserDefaultsKey,
                default: defaultMinimumDrawerOpacity,
                range: 0...1
            ),
            transitionDuration: timeIntervalValue(
                forKey: transitionDurationUserDefaultsKey,
                default: defaultTransitionDuration,
                range: 0.1...1
            ),
            minimumTransitionDuration: timeIntervalValue(
                forKey: minimumTransitionDurationUserDefaultsKey,
                default: defaultMinimumTransitionDuration,
                range: 0.05...0.5
            ),
            springDampingRatio: value(
                forKey: springDampingRatioUserDefaultsKey,
                default: defaultSpringDampingRatio,
                range: 0.5...1
            ),
            overscrollReturnDuration: timeIntervalValue(
                forKey: overscrollReturnDurationUserDefaultsKey,
                default: defaultOverscrollReturnDuration,
                range: 0.1...0.8
            )
        )
    }

    static func notifyDidChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func reset() {
        let defaults = UserDefaults.standard
        defaults.set(defaultExposedMainWidth, forKey: exposedMainWidthUserDefaultsKey)
        defaults.set(defaultParallaxFactor, forKey: parallaxFactorUserDefaultsKey)
        defaults.set(defaultMinimumScale, forKey: minimumScaleUserDefaultsKey)
        defaults.set(defaultOpenMainContentOpacity, forKey: openMainContentOpacityUserDefaultsKey)
        defaults.set(defaultMinimumDrawerOpacity, forKey: minimumDrawerOpacityUserDefaultsKey)
        defaults.set(defaultTransitionDuration, forKey: transitionDurationUserDefaultsKey)
        defaults.set(defaultMinimumTransitionDuration, forKey: minimumTransitionDurationUserDefaultsKey)
        defaults.set(defaultSpringDampingRatio, forKey: springDampingRatioUserDefaultsKey)
        defaults.set(defaultOverscrollReturnDuration, forKey: overscrollReturnDurationUserDefaultsKey)
        notifyDidChange()
    }

    private static func timeIntervalValue(
        forKey key: String,
        default defaultValue: Double,
        range: ClosedRange<Double>
    ) -> TimeInterval {
        TimeInterval(value(forKey: key, default: defaultValue, range: range))
    }

    private static func value(
        forKey key: String,
        default defaultValue: Double,
        range: ClosedRange<Double>
    ) -> CGFloat {
        guard IS_DEBUG_OR_TESTFLIGHT_DEFAULT else { return CGFloat(defaultValue) }
        let storedValue = (UserDefaults.standard.object(forKey: key) as? NSNumber)?.doubleValue
        let resolvedValue = storedValue ?? defaultValue
        return CGFloat(min(max(resolvedValue, range.lowerBound), range.upperBound))
    }
}
