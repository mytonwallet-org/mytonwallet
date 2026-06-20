//
//  DeviceUtils.swift
//  UIHome
//
//  Created by Sina on 7/11/24.
//

import UIKit

public extension UIDevice {
    var supportsOptionalLandscapeOrientation: Bool {
        guard userInterfaceIdiom == .phone else {
            return false
        }
        let screen = UIScreen.main
        let width = min(screen.bounds.width, screen.bounds.height)
        let height = max(screen.bounds.width, screen.bounds.height)
        return width >= 414 && height >= 896 && screen.nativeScale >= 3
    }
}
