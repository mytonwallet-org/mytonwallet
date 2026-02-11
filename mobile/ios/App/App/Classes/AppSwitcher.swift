//
//  AppSwitcher.swift
//  MyTonWallet
//
//  Created by Sina on 10/15/24.
//

import UIKit
import WebKit
#if canImport(Capacitor)
import Capacitor
#endif
import AirAsFramework
import WalletContext
import UIComponents

private let log = Log("AppSwitcher")


@MainActor final class AppSwitcher: NSObject {
    
    let window: WWindow

    init(window: WWindow) {
        log.info("AppSwitcher.init")
        self.window = window
        AirLauncher.set(window: window)
    }
    
    func startTheApp() {
        let canSwitchToCapacitor = (UIApplication.shared.delegate as? AppDelegate)?.canSwitchToCapacitor ?? true
        log.info("startTheApp isOnTheAir=\(AirLauncher.isOnTheAir) canSwitchToCapacitor=\(canSwitchToCapacitor)")
        if AirLauncher.isOnTheAir || !canSwitchToCapacitor {
            Task(priority: .userInitiated) {
                await AirLauncher.soarIntoAir()
            }
        } else {
            #if canImport(Capacitor)
            let capBridgeVC = UIStoryboard(name: "Main", bundle: Bundle.main).instantiateViewController(withIdentifier: "capBridgeVC") as! CAPBridgeViewController
            addLongTapGesture(vc: capBridgeVC)
            window.rootViewController = capBridgeVC
            window.makeKeyAndVisible()
            #endif
        }
    }
    
    #if canImport(Capacitor)
    func addLongTapGesture(vc: CAPBridgeViewController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let webView = vc.webView {
                let longTap = UILongPressGestureRecognizer(target: self, action: #selector(self.onLongTap(_:)))
                longTap.minimumPressDuration = 5
                webView.addGestureRecognizer(longTap)
                
                #if DEBUG
                if #available(iOS 16.4, *) {
                    webView.isInspectable = true
                }
                #endif
            } else {
                self.addLongTapGesture(vc: vc)
            }
        }
    }
    
    @objc @MainActor func onLongTap(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            _showDebugView()
        }
    }
    #endif
}
