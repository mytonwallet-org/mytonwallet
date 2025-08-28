//
//  DeeplinkHandler.swift
//  MyTonWallet
//
//  Created by Sina on 5/14/24.
//

import Foundation
import UIKit
import UIInAppBrowser
import WalletContext

let SELF_PROTOCOL = "mtw://"
let SELF_UNIVERSAL_URLS = ["https://my.tt/",  "https://go.mytonwallet.org/"]

enum Deeplink {
    case tonConnect2(requestLink: String)
    case invoice(address: String, amount: BigInt?, comment: String?, binaryPayload: String?, token: String?, jetton: String?)
    case swap(from: String?, to: String?, amountIn: Double?)
    case buyWithCard
    case stake
    case url(config: InAppBrowserPageVC.Config)
    case switchToClassic
}

protocol DeeplinkNavigator: AnyObject {
    func handle(deeplink: Deeplink)
}

class DeeplinkHandler {
    private weak var deeplinkNavigator: DeeplinkNavigator? = nil
    init(deeplinkNavigator: DeeplinkNavigator) {
        self.deeplinkNavigator = deeplinkNavigator
    }
    
    func handle(_ url: URL) -> Bool {
        switch url.scheme {
        case "ton":
            handleTonInvoice(with: url)
            return true
        case "tc", "mytonwallet-tc":
            handleTonConnect(with: url)
            return true
        case "mtw":
            handleMTW(with: url)
            return true
        case "https", "http":
            switch url.host {
            case "connect.mytonwallet.org":
                handleTonConnect(with: url)
                return true
            case "go.mytonwallet.org":
                handleMTW(with: url)
                return true
            case "my.tt":
                handleMTW(with: url)
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
    
    private func handleTonConnect(with url: URL) {
        deeplinkNavigator?.handle(deeplink: Deeplink.tonConnect2(requestLink: url.absoluteString))
    }
    
    private func handleTonInvoice(with url: URL) {
        guard let parsedWalletURL = parseTonTransferUrl(url) else {
            return
        }
        
        deeplinkNavigator?.handle(deeplink: Deeplink.invoice(address: parsedWalletURL.address,
                                                             amount: parsedWalletURL.amount,
                                                             comment: parsedWalletURL.comment,
                                                             binaryPayload: parsedWalletURL.bin,
                                                             token: parsedWalletURL.token,
                                                             jetton: parsedWalletURL.jetton))
    }
    
    private func handleMTW(with url: URL) {
        
        var url = url
        
        if url.scheme == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            if let newUrl = components.url {
                url = newUrl
            }
        }
        
        if url.scheme == "https" {
            let urlString = url.absoluteString
            for universalUrl in SELF_UNIVERSAL_URLS {
                if urlString.starts(with: universalUrl) {
                    let newUrlString = urlString.replacing(universalUrl, with: SELF_PROTOCOL, maxReplacements: 1)
                    if let newUrl = URL(string: newUrlString) {
                        url = newUrl
                    }
                    break
                }
            }
        }
        
        switch url.host {
        case "classic":
            deeplinkNavigator?.handle(deeplink: .switchToClassic)
            
        case "swap", "buy-with-crypto":
            var from: String? = nil
            var to: String? = nil
            var amountIn: Double? = nil
            if let query = url.query, let components = URLComponents(string: "/?" + query), let queryItems = components.queryItems {
                for queryItem in queryItems {
                    if let value = queryItem.value {
                        if queryItem.name == "amountIn", !value.isEmpty, let amountValue = Double(value) {
                            amountIn = amountValue
                        } else if queryItem.name == "in", !value.isEmpty {
                            from = value
                        } else if queryItem.name == "out", !value.isEmpty {
                            to = value
                        }
                    }
                }
            }
            if url.host == "buy-with-crypto" {
                if to == nil, from != "toncoin" {
                    to = "toncoin"
                }
                if from == nil {
                    from = TRON_USDT_SLUG
                }
            }
            deeplinkNavigator?.handle(deeplink: Deeplink.swap(from: from, to: to, amountIn: amountIn))
            break
        case "transfer":
            handleTonInvoice(with: url)
            break
        case "buy-with-card":
            deeplinkNavigator?.handle(deeplink: Deeplink.buyWithCard)
            break
        case "stake":
            deeplinkNavigator?.handle(deeplink: Deeplink.stake)
            break
        case "giveaway":
            let pathname = url.absoluteString
            let regex = try! NSRegularExpression(pattern: "giveaway/([^/]+)")
            var giveawayId: String? = nil
            
            if let match = regex.firstMatch(in: pathname, range: NSRange(pathname.startIndex..., in: pathname)) {
                let giveawayIdRange = match.range(at: 1)
                if let giveawayIdRange = Range(giveawayIdRange, in: pathname) {
                    giveawayId = String(pathname[giveawayIdRange])
                }
            }
            let urlString = "https://giveaway.mytonwallet.io/\(giveawayId != nil ? "?giveawayId=\(giveawayId!)" : "")"
            let url = URL(string: urlString)!
            deeplinkNavigator?.handle(deeplink: .url(config: .init(url: url,
                                                                   title: "Giveaway",
                                                                   injectTonConnectBridge: true)))
        case "r":
            let pathname = url.absoluteString
            let regex = try! NSRegularExpression(pattern: "r/([^/]+)")
            var r: String? = nil
            
            if let match = regex.firstMatch(in: pathname, range: NSRange(pathname.startIndex..., in: pathname)) {
                let rIdRange = match.range(at: 1)
                if let rRange = Range(rIdRange, in: pathname) {
                    r = String(pathname[rRange])
                }
            }
            let urlString = "https://checkin.mytonwallet.org/\(r != nil ? "?r=\(r!)" : "")"
            let url = URL(string: urlString)!
            deeplinkNavigator?.handle(deeplink: .url(config: .init(url: url,
                                                                   title: "Checkin",
                                                                   injectTonConnectBridge: true)))
            break
        default:
            break
        }
    }
}
