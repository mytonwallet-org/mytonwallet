import UIKit

enum ContextMenuPrivateSheetRuntime {
    private static let backdropViewSelector = Self.selector(fromReversed: "weiVgnimmiDdenifnoc_")
    private static let setBackdropColorSelector = Self.selector(fromReversed: ":roloCgnimmiDtes")
    private static let backdropColorSelector = Self.selector(fromReversed: "roloCgnimmid")

    static func backdropColor(on presentationController: NSObject) -> UIColor? {
        guard presentationController.responds(to: Self.backdropViewSelector),
              let backdropView = presentationController.perform(Self.backdropViewSelector)?
                .takeUnretainedValue() as? NSObject,
              backdropView.responds(to: Self.backdropColorSelector) else {
            return nil
        }
        return backdropView.perform(Self.backdropColorSelector)?.takeUnretainedValue() as? UIColor
    }

    @discardableResult
    static func setBackdropColor(_ color: UIColor, on presentationController: NSObject) -> Bool {
        guard presentationController.responds(to: Self.backdropViewSelector),
              let backdropView = presentationController.perform(Self.backdropViewSelector)?
                .takeUnretainedValue() as? NSObject,
              backdropView.responds(to: Self.setBackdropColorSelector) else {
            return false
        }
        _ = backdropView.perform(Self.setBackdropColorSelector, with: color)
        return true
    }

    private static func selector(fromReversed value: String) -> Selector {
        NSSelectorFromString(String(value.reversed()))
    }
}
