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

public protocol WalletContextDelegate: NSObject {
    func bridgeIsReady()
    func walletIsReady(isReady: Bool)
    func switchToCapacitor()
    func restartApp()
    func handleDeeplink(url: URL) -> Bool
    var isWalletReady: Bool { get }
    var isAppUnlocked: Bool { get }
}

public class WalletContextManager {
    private init() {}
    
    public static weak var delegate: WalletContextDelegate? = nil
}

public let AirBundle = Bundle(for: WalletContextManager.self)
