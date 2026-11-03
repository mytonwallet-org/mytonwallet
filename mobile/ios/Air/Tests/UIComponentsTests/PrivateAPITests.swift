import Testing
import UIKit
@testable import UIComponents
import UIComponentsRuntime

/// Every name in `PrivateAPI` resolves on the iOS version the tests run on, so an iOS release that removes one
/// fails here rather than silently dropping to a fallback for users
@MainActor
struct PrivateAPITests {
    @Test
    func classesExist() {
        for name in [
            PrivateAPI.filter,
            PrivateAPI.backdropLayer,
            PrivateAPI.emitterBehavior,
            PrivateAPI.navigationBarPalette,
            PrivateAPI.navigationParallaxTransition,
        ] {
            #expect(name.objectClass != nil, "\(name.string)")
        }
    }

    @Test
    func methodsExist() throws {
        #expect(try #require(PrivateAPI.filter.objectClass).responds(to: PrivateAPI.filterWithType.selector))
        #expect(try #require(PrivateAPI.emitterBehavior.objectClass).responds(to: PrivateAPI.behaviorWithType.selector))
        #expect(try #require(PrivateAPI.navigationBarPalette.objectClass)
            .instancesRespond(to: NSSelectorFromString("initWithContentView:")))
        #expect(try #require(PrivateAPI.navigationParallaxTransition.objectClass)
            .instancesRespond(to: PrivateAPI.initWithCurrentOperation.selector))
        #expect(UIScreen.instancesRespond(to: PrivateAPI.displayCornerRadius.selector))
        #expect(UINavigationItem.instancesRespond(to: PrivateAPI.setBottomPalette.selector))
        #expect(UINavigationController.instancesRespond(to: PrivateAPI.setUsingBuiltinAnimator.selector))
    }

    @Test
    func factoriesMakeObjects() throws {
        for type in ["gaussianBlur", "variableBlur", "displacementMap", PrivateAPI.colorMatrixFilterType.string] {
            let filter = try #require(PrivateAPI.makeFilter(type), "\(type)")
            #expect(filter.value(forKey: "name") as? String == type)
        }
        let colorMatrix = try #require(PrivateAPI.makeFilter(PrivateAPI.colorMatrixFilterType.string))
        var matrix: [Float32] = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]
        let value = NSValue(bytes: &matrix, objCType: "{CAColorMatrix=ffffffffffffffffffff}")
        colorMatrix.setValue(value, forKey: PrivateAPI.inputColorMatrix.string)
        #expect(colorMatrix.value(forKey: PrivateAPI.inputColorMatrix.string) as? NSValue == value)
        #expect(PrivateAPI.makeBackdropLayer() != nil)
        for type in ["wave", "attractor", "drag"] {
            #expect(PrivateAPI.makeEmitterBehavior(type) != nil, "\(type)")
        }
        #expect(PrivateAPI.setBottomPalette(of: UINavigationItem(), contentView: UIView()))
    }

    @Test
    func blurEffectViewHasTintSubview() {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        #expect(view.subviews.contains { $0.description.contains(PrivateAPI.visualEffectSubview.string) })
    }

    @Test
    func liquidLensAndBuiltinInteractionExist() throws {
        guard #available(iOS 26, *) else { return }
        let lensClass = try #require(PrivateAPI.liquidLensView.objectClass)
        for name in [
            PrivateAPI.liquidLensInitWithRestingBackground,
            PrivateAPI.liquidLensSetLiftedContainerView,
            PrivateAPI.liquidLensSetLiftedContentView,
            PrivateAPI.liquidLensSetOverridePunchoutView,
            PrivateAPI.liquidLensSetLifted,
            PrivateAPI.liquidLensSetLiftedContentMode,
            PrivateAPI.liquidLensSetStyle,
            PrivateAPI.liquidLensSetWarpsContentBelow,
            PrivateAPI.liquidLensSetRestingBackgroundColor,
        ] {
            #expect(lensClass.instancesRespond(to: name.selector), "\(name.string)")
        }

        let navigationController = UINavigationController(rootViewController: UIViewController())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let controllerSelector = PrivateAPI.builtinInteractionController.selector
        #expect(navigationController.responds(to: controllerSelector))
        let controller = try #require(navigationController.perform(controllerSelector)?.takeUnretainedValue() as? NSObject)
        #expect(controller.responds(to: PrivateAPI.setAnimationController.selector))
    }

    /// `UIComponentsRuntime` keeps its own encoded names, since `UIComponents` builds on it; its entry points
    /// report whether they found them
    @Test
    func glassRuntimeFindsItsNames() {
        guard #available(iOS 26, *) else { return }
        #expect(WMakeLiquidLens() != nil)
        #expect(NSClassFromString("_UITabSelectionView") != nil)
        #expect(WInstallBarFlex(UIView()))
        let view = UIView()
        WSetTitleBlur(view, 1)
        #expect(view.layer.filters?.count == 1)
    }
}
