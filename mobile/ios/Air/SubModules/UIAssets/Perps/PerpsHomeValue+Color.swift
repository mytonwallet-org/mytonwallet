import SwiftUI
import UIKit
import WalletContext

extension PerpsHomeValue.Tone {
    var uiColor: UIColor {
        switch self {
        case .neutral: .label
        case .positive: .air.positiveAmount
        case .negative: .air.negativeAmount
        }
    }
    var color: Color { Color(uiColor) }
}
