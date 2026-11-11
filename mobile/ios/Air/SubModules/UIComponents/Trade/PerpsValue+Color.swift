import SwiftUI
import UIKit
import WalletContext
import WalletCore

extension PerpsValue.Tone {
    public var uiColor: UIColor {
        switch self {
        case .neutral: .label
        case .positive: .air.positiveAmount
        case .negative: .air.negativeAmount
        }
    }

    public var color: Color { Color(uiColor) }
}
