import UIKit

enum ContextMenuPrivatePortalRuntime {
    static var portalViewClass: UIView.Type? {
        NSClassFromString(Self.string(fromReversed: "weiVlatroPIU_")) as? UIView.Type
    }

    static let setSourceViewSelector = Self.selector(fromReversed: ":weiVecruoStes")
    static let setMatchesPositionSelector = Self.selector(fromReversed: ":noitisoPsehctaMtes")
    static let setMatchesTransformSelector = Self.selector(fromReversed: ":mrofsnarTsehctaMtes")
    static let setMatchesAlphaSelector = Self.selector(fromReversed: ":ahplAsehctaMtes")
    static let setAllowsHitTestingSelector = Self.selector(fromReversed: ":gnitseTtiHswollAtes")
    static let setForwardsClientHitTestingToSourceViewSelector = Self.selector(fromReversed: ":weiVecruoSoTgnitseTtiHtneilCsdrawroFtes")

    static func setProperty(_ value: Any?, selector: Selector, on view: UIView) {
        guard view.responds(to: selector) else {
            return
        }
        _ = view.perform(selector, with: value)
    }

    private static func selector(fromReversed value: String) -> Selector {
        NSSelectorFromString(Self.string(fromReversed: value))
    }

    private static func string(fromReversed value: String) -> String {
        String(value.reversed())
    }
}
