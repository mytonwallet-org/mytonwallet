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
}

public protocol WalletContextDelegate: NSObject {
    func bridgeIsReady()
    //func bridgeTerminated()
    func walletIsReady(isReady: Bool)
    func switchToCapacitor()
    func restartApp()
    func addAnotherAccount(wordList: [String], passedPasscode: String?) -> UIViewController
    func importAnotherAccount(passedPasscode: String?, isLedger: Bool) async -> UIViewController
    func viewAnyAddress() -> UIViewController
    func handleDeeplink(url: URL) -> Bool
    var isWalletReady: Bool { get }
    var isAppUnlocked: Bool { get }
    var isCapacitorAppAvailable: Bool { get }
}

public class WalletContextManager {
    private init() {}
    
    public static weak var delegate: WalletContextDelegate? = nil
}

public let AirBundle = Bundle(for: WalletContextManager.self)
