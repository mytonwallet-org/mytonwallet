//
//  iOS26Compatibility.swift
//  MyTonWalletAir
//
//  Created by nikstar on 24.10.2025.
//

import UIKit
import WalletCore
import WalletContext

public let IOS_26_MODE_ENABLED: Bool = {
    return if #available(iOS 26, iOSApplicationExtension 26, *) {
        !(Bundle.main.infoDictionary?["UIDesignRequiresCompatibility"] as? Bool ?? false)
    } else {
        false
    }
}()

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

    public static var menuCornerRadius: CGFloat {
        IOS_26_MODE_ENABLED ? 26 : 12
    }

    public static var insetSectionHorizontalMargin: CGFloat {
        IOS_26_MODE_ENABLED ? 20 : 16
    }
    
    public static func actionButtonSpacing(forButtonCount count: Int) -> CGFloat {
        guard IOS_26_MODE_ENABLED else { return 8 }
        switch count {
        case 2: return 48
        case 3: return 32
        default: return 16
        }
    }
}
