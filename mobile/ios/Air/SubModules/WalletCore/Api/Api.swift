//
//  WalletBridge.swift
//  MyTonWallet
//
//  Created by Sina on 3/19/24.
//

import Foundation
import UIKit
import WalletContext

public class Api {
    
    // shared core api and bridge
    @MainActor static var shared: Api? = nil
    
    @MainActor public static var bridge: JSWebViewBridge {
        get throws {
            try Api.shared.orThrow("bridge not ready").webViewBridge
        }
    }
    
    @MainActor let webViewBridge = JSWebViewBridge()
    
    @MainActor private init() {
    }

    @MainActor public static func prepare(on vc: UIViewController) {
        shared = Api()
        vc.addChild(shared!.webViewBridge)
        vc.view.addSubview(shared!.webViewBridge.view)
    }
    
    @MainActor public static func stop() {
        shared?.webViewBridge.stop()
        shared?.webViewBridge.view.removeFromSuperview()
        shared?.webViewBridge.removeFromParent()
        shared = nil
    }
}
