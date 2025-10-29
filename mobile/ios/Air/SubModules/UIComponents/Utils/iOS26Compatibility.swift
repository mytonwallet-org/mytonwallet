//
//  iOS26Compatibility.swift
//  MyTonWalletAir
//
//  Created by nikstar on 24.10.2025.
//

import UIKit
import ObjectiveC.runtime
import WalletCore
import WalletContext

public let IOS_26_MODE_ENABLED: Bool = {
    return if #available(iOS 26, iOSApplicationExtension 26, *) {
        !(Bundle.main.infoDictionary?["UIDesignRequiresCompatibility"] as? Bool ?? false)
    } else {
        false
    }
}()

@MainActor
public func congigureIOS26Compativility() {
    if IOS_26_MODE_ENABLED {
        installSheetLayoutTransformReset()
    }
}

private func installSheetLayoutTransformReset() {

    struct Once { static var done = false }
    guard !Once.done else { return }
    Once.done = true

    let cls: AnyClass = UISheetPresentationController.self
    let sel = NSSelectorFromString(String("sweivbuStuoyaLweiVreniatnoc_".reversed()))
    let original = class_getInstanceMethod(cls, sel)
    let swizzled = class_getInstanceMethod(cls, #selector(UISheetPresentationController._swz_cvls))
    guard let original, let swizzled else { return }

    method_exchangeImplementations(original, swizzled)
}

extension UISheetPresentationController {
    @objc dynamic func _swz_cvls() {
        self._swz_cvls()
        // reset transform on drop shadow view to identity
        if detents.contains(where: { $0.identifier == .minimized }) {
            let sel = NSSelectorFromString(String("weiVwodahSpord".reversed()))
            if let shadow = self.perform(sel)?.takeUnretainedValue() as? UIView {
                shadow.transform = .identity
            }
        }
    }
}

public enum S {
    public static var insetSectionCornerRadius: CGFloat {
        IOS_26_MODE_ENABLED ? 26 : 10
    }

    public static var sectionItemHeight: CGFloat {
        IOS_26_MODE_ENABLED ? 52 : 44
    }

    public static var homeInsetSectionCornerRadius: CGFloat {
        IOS_26_MODE_ENABLED ? 26 : 16
    }

    public static var actionButtonCornerRadius: CGFloat {
        IOS_26_MODE_ENABLED ? 16 : 12
    }

    public static var headerTopAdjustment: CGFloat {
        IOS_26_MODE_ENABLED ? 6 : 0
    }

    public static var addressSectionCornerRadius: CGFloat {
        IOS_26_MODE_ENABLED ? 26 : 12
    }

    public static var featuredDappCornerRadius: CGFloat {
        IOS_26_MODE_ENABLED ? 22 : 14
    }

    public static var insetSectionHorizontalMargin: CGFloat {
        IOS_26_MODE_ENABLED ? 20 : 16
    }
}

