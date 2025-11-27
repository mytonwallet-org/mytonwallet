//
//  MtwCardHighlight.swift
//  MyTonWalletAir
//
//  Created by nikstar on 19.11.2025.
//

import SwiftUI
import WalletCore
import WalletContext

public struct MtwCardForegroundStyle: ShapeStyle {
    
    var nft: ApiNft?
    
    public init(nft: ApiNft?) {
        self.nft = nft
    }
    
    public func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        switch nft?.metadata?.mtwCardType {
        case nil:
            return AnyShapeStyle(Color.white)
        case .standard:
            return AnyShapeStyle(nft?.metadata?.mtwCardTextType == .dark ? Color.black : Color.white)
        case .silver:
            return AnyShapeStyle(
                EllipticalGradient(
                    colors: [
                        Color(UIColor(hex: "272727")),
                        Color(UIColor(hex: "989898")),
                    ],
                    center: UnitPoint(x: 0.25, y: 0.5),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5
                )
            )
        case .gold:
            return AnyShapeStyle(
                EllipticalGradient(
                    colors: [
                        Color(UIColor(hex: "4C3403")),
                        Color(UIColor(hex: "B07D1D")),
                    ],
                    center: UnitPoint(x: 0.25, y: 0.5),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5
                )
            )
        case .platinum:
            return AnyShapeStyle(
                EllipticalGradient(
                    colors: [
                        Color(UIColor(hex: "FFFFFF")),
                        Color(UIColor(hex: "77777F")),
                    ],
                    center: UnitPoint(x: 0.25, y: 0.5),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5
                )
            )
        case .black:
            return AnyShapeStyle(
                EllipticalGradient(
                    colors: [
                        Color(UIColor(hex: "CECECF")),
                        Color(UIColor(hex: "444546")),
                    ],
                    center: UnitPoint(x: 0.25, y: 0.5),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5
                )
            )
        }
    }
}

