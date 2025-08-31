//
//  AppSwitcher.swift
//  MyTonWallet
//
//  Created by Sina on 10/15/24.
//

import UIKit
import WebKit
import Capacitor
import AirAsFramework
import WalletContext
import UIComponents

private let log = Log("AppSwitcher")


class AppSwitcher: NSObject {
    
    let window: WWindow

    var webView: WKWebView? = nil
    
    init(window: WWindow) {
        log.info("AppSwitcher.init")
        self.window = window
        AirLauncher.set(window: window)
    }
    
    @MainActor func startTheApp() {
        log.info("startTheApp isOnTheAir=\(AirLauncher.isOnTheAir) isCapacitorAppAvailable=\(AirLauncher.isCapacitorAppAvailable)")
        if AirLauncher.isOnTheAir || !AirLauncher.isCapacitorAppAvailable {
            Task(priority: .userInitiated) {
                await AirLauncher.soarIntoAir()
            }
        } else {
            let capBridgeVC = UIStoryboard(name: "Main", bundle: Bundle.main).instantiateViewController(withIdentifier: "capBridgeVC") as! CAPBridgeViewController
            addLongTapGesture(vc: capBridgeVC)
            window.rootViewController = capBridgeVC
            window.makeKeyAndVisible()
        }
    }
    
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
}
