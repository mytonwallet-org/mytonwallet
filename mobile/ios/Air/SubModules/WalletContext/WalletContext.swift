//
//  WalletContext.swift
//  WalletContext
//
//  Created by Sina on 3/25/24.
//

import Foundation
import UIKit
import struct os.OSAllocatedUnfairLock

public typealias UnfairLock = OSAllocatedUnfairLock

public enum DeeplinkOpenSource: Equatable {
    case generic
    case exploreSearchBar
    case inAppBrowser
    case qrScan
}

public extension DeeplinkOpenSource {
    var canRouteOfframp: Bool {
        switch self {
        case .generic, .exploreSearchBar:
            true
        case .inAppBrowser, .qrScan:
            false
        }
    }
}

@MainActor public protocol WalletContextDelegate: NSObject, Sendable {
    func bridgeIsReady()
    func walletIsReady(isReady: Bool)
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
    
    @MainActor public static weak var delegate: WalletContextDelegate? = nil
}

#if SWIFT_PACKAGE
public let AirBundle = {
    let bundleName = "AirModules_WalletResources"
    let candidates = [
        Bundle.main.resourceURL,
        Bundle(for: WalletContextManager.self).resourceURL,
        Bundle.main.bundleURL,
        Bundle(for: WalletContextManager.self).bundleURL,
    ]

    for candidate in candidates {
        guard let bundleURL = candidate?.appendingPathComponent("\(bundleName).bundle") else {
            continue
        }
        if let bundle = Bundle(url: bundleURL) {
            return bundle
        }
    }

    if let bundle = Bundle.allBundles.first(where: { $0.bundleURL.lastPathComponent == "\(bundleName).bundle" }) {
        return bundle
    }

    return Bundle.main
}()
#else
public let AirBundle = Bundle(for: WalletContextManager.self)
#endif
