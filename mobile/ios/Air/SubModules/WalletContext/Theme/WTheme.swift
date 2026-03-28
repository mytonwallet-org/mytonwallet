import UIKit

@MainActor public var AirTintColor: UIColor = getAccentColorByIndex(nil)

public func getAccentColorByIndex(_ index: Int?) -> UIColor {
    if let index, index < ACCENT_COLORS.count {
        ACCENT_COLORS[index]
    } else {
        UIColor.airBundle("TC1_PrimaryColor")
    }
}

@MainActor public func changeThemeColors(to index: Int?) {
    AirTintColor = getAccentColorByIndex(index)
}
