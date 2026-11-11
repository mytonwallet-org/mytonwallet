import UIKit

/// Private UIKit and Core Animation names that rendering relies on where public API has no equivalent.
///
/// Names are stored reversed, so they do not appear as plain strings in the binary. Every lookup is optional:
/// when an iOS release removes a name, the caller gets nil and keeps its public fallback. `PrivateAPITests`
/// resolves every name on the iOS version the tests run on.
public enum PrivateAPI {
    struct Name: Sendable {
        private let reversed: String

        fileprivate init(reversed: String) {
            self.reversed = reversed
        }

        var string: String { String(reversed.reversed()) }
        var selector: Selector { NSSelectorFromString(string) }
        var objectClass: NSObject.Type? { NSClassFromString(string) as? NSObject.Type }
    }

    // MARK: Core Animation

    /// `CAFilter`
    static let filter = Name(reversed: "retliFAC")
    /// `+[CAFilter filterWithType:]`
    static let filterWithType = Name(reversed: ":epyThtiWretlif")
    /// The `CAFilter` type `colorMatrix`
    static let colorMatrixFilterType = Name(reversed: "xirtaMroloc")
    /// The `colorMatrix` filter's `inputColorMatrix`
    static let inputColorMatrix = Name(reversed: "xirtaMroloCtupni")
    /// `CABackdropLayer`, a layer that renders the content behind it
    static let backdropLayer = Name(reversed: "reyaLpordkcaBAC")
    /// `CAEmitterBehavior`
    static let emitterBehavior = Name(reversed: "roivaheBrettimEAC")
    /// `+[CAEmitterBehavior behaviorWithType:]`
    static let behaviorWithType = Name(reversed: ":epyThtiWroivaheb")

    // MARK: UIKit

    /// `-[UIScreen _displayCornerRadius]`
    static let displayCornerRadius = Name(reversed: "suidaRrenroCyalpsid_")
    /// Part of the description of the tint subview of a `UIVisualEffectView`
    static let visualEffectSubview = Name(reversed: "weivbuStceffElausiV")
    /// `_UINavigationBarPalette`, a view under the navigation bar that shares its background
    static let navigationBarPalette = Name(reversed: "ettelaPraBnoitagivaNIU_")
    /// `-[UINavigationItem _setBottomPalette:]`
    static let setBottomPalette = Name(reversed: ":ettelaPmottoBtes_")
    /// `_UINavigationParallaxTransition`, the animator of the system push and pop
    static let navigationParallaxTransition = Name(reversed: "noitisnarTxallaraPnoitagivaNIU_")
    /// `-[_UINavigationParallaxTransition initWithCurrentOperation:]`
    static let initWithCurrentOperation = Name(reversed: ":noitarepOtnerruChtiWtini")
    /// `-[UINavigationController _builtinInteractionController]`, iOS 26 and later
    static let builtinInteractionController = Name(reversed: "rellortnoCnoitcaretnInitliub_")
    /// `-setAnimationController:` of the builtin interaction controller
    static let setAnimationController = Name(reversed: ":rellortnoCnoitaminAtes")
    /// `-[UINavigationController _setUsingBuiltinAnimator:]`
    static let setUsingBuiltinAnimator = Name(reversed: ":rotaminAnitliuBgnisUtes_")

    // MARK: Liquid lens, iOS 26 and later

    /// `_UILiquidLensView`
    static let liquidLensView = Name(reversed: "weiVsneLdiuqiLIU_")
    static let liquidLensInitWithRestingBackground = Name(reversed: ":dnuorgkcaBgnitseRhtiWtini")
    static let liquidLensSetLiftedContainerView = Name(reversed: ":weiVreniatnoCdetfiLtes")
    static let liquidLensSetLiftedContentView = Name(reversed: ":weiVtnetnoCdetfiLtes")
    static let liquidLensSetOverridePunchoutView = Name(reversed: ":weiVtuohcnuPedirrevOtes")
    static let liquidLensSetLifted = Name(reversed: ":noitelpmoc:snoitaminAedisgnola:detamina:detfiLtes")
    static let liquidLensSetLiftedContentMode = Name(reversed: ":edoMtnetnoCdetfiLtes")
    static let liquidLensSetStyle = Name(reversed: ":elytStes")
    static let liquidLensSetWarpsContentBelow = Name(reversed: ":woleBtnetnoCspraWtes")
    static let liquidLensSetRestingBackgroundColor = Name(reversed: ":roloCdnuorgkcaBgnitseRtes")

    // MARK: Factories

    /// A Core Animation filter of `type` for a layer's `filters`, such as `gaussianBlur`, `variableBlur` or
    /// `displacementMap`. The filter's name is its type, so its inputs live at `filters.<type>.<input>`.
    public static func makeFilter(_ type: String) -> NSObject? {
        guard let filterClass = filter.objectClass,
              filterClass.responds(to: filterWithType.selector) else { return nil }
        return filterClass.perform(filterWithType.selector, with: type)?.takeUnretainedValue() as? NSObject
    }

    public static func makeBackdropLayer() -> CALayer? {
        (NSClassFromString(backdropLayer.string) as? CALayer.Type)?.init()
    }

    /// A `CAEmitterBehavior` of `type`, such as `wave`, `attractor` or `drag`, for a `CAEmitterLayer`'s
    /// `emitterBehaviors`
    public static func makeEmitterBehavior(_ type: String) -> NSObject? {
        guard let behaviorClass = emitterBehavior.objectClass,
              behaviorClass.responds(to: behaviorWithType.selector) else { return nil }
        return behaviorClass.perform(behaviorWithType.selector, with: type)?.takeUnretainedValue() as? NSObject
    }

    /// Shows `contentView` under the navigation bar of `navigationItem`'s controller, or removes the palette when `nil`.
    /// Returns false, leaving the item unchanged, when the palette is unavailable.
    @MainActor @discardableResult
    public static func setBottomPalette(of navigationItem: UINavigationItem, contentView: UIView?) -> Bool {
        guard let contentView else {
            guard navigationItem.responds(to: setBottomPalette.selector) else { return false }
            navigationItem.perform(setBottomPalette.selector, with: nil)
            return true
        }
        let initWithContentView = NSSelectorFromString("initWithContentView:")
        guard let paletteClass = navigationBarPalette.objectClass,
              paletteClass.instancesRespond(to: initWithContentView),
              navigationItem.responds(to: setBottomPalette.selector),
              let allocated = paletteClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let palette = allocated.perform(initWithContentView, with: contentView)?.takeUnretainedValue() else {
            return false
        }
        navigationItem.perform(setBottomPalette.selector, with: palette)
        return true
    }
}
