//
//  WalletContext.swift
//  WalletContext
//
//  Created by Sina on 3/25/24.
//

import Foundation
import UIKit
import struct os.OSAllocatedUnfairLock
import GRDB

public typealias UnfairLock = OSAllocatedUnfairLock

@MainActor public protocol MtwAppDelegateProtocol {
    func showDebugView()
    func switchToCapacitor()
    func switchToAir()
    var canSwitchToCapacitor: Bool { get }
    var isFirstLaunch: Bool { get }
}

public enum DeeplinkOpenSource {
    case generic
    case exploreSearchBar
}

public protocol WalletContextDelegate: NSObject {
    func bridgeIsReady()
    func walletIsReady(isReady: Bool)
    func switchToCapacitor()
    func restartApp()
    func handleDeeplink(url: URL, source: DeeplinkOpenSource) -> Bool
    var isWalletReady: Bool { get }
    var isAppUnlocked: Bool { get }
}

public extension WalletContextDelegate {
    func handleDeeplink(url: URL) -> Bool {
        handleDeeplink(url: url, source: .generic)
    }
}

public class WalletContextManager {
    private init() {}
    
    public static weak var delegate: WalletContextDelegate? = nil
}

public let AirBundle = Bundle(for: WalletContextManager.self)
