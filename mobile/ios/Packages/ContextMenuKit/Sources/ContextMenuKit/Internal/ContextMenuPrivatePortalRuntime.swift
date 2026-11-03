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

    static let matchesPositionKey = Self.string(fromReversed: "noitisoPsehctam")
    static let hidesSourceViewKey = Self.string(fromReversed: "weiVecruoSsedih")

    static func setProperty(_ value: Any?, selector: Selector, on view: UIView) {
        guard view.responds(to: selector) else {
            return
        }
        _ = view.perform(selector, with: value)
    }

    /// Sets a `BOOL` property through key-value coding, which passes the property's setter the flag itself rather than
    /// an object
    static func setFlag(_ isOn: Bool, forKey key: String, on view: UIView) {
        let setter = NSSelectorFromString("set\(key.prefix(1).uppercased())\(key.dropFirst()):")
        guard view.responds(to: setter) else {
            return
        }
        view.setValue(isOn, forKey: key)
    }

    private static func selector(fromReversed value: String) -> Selector {
        NSSelectorFromString(Self.string(fromReversed: value))
    }

    private static func string(fromReversed value: String) -> String {
        String(value.reversed())
    }
}
