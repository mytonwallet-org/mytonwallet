import UIKit

enum ContextMenuPrivateMonochromaticRuntime {
    static let setAllowsTreatmentSelector = Self.selector(fromReversed: ":tnemtaerTcitamorhconoMswollAtes_")
    static let setEnableTreatmentSelector = Self.selector(fromReversed: ":tnemtaerTcitamorhconoMelbanEtes_")
    static let setTreatmentSelector = Self.selector(fromReversed: ":tnemtaerTcitamorhconoMtes_")

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
