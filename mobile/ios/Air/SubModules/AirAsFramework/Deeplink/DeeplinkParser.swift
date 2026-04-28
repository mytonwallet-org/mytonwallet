
import Foundation
import UIInAppBrowser
import WalletCore
import WalletContext

extension Deeplink {
    init?(url: URL) {
        let deeplink: Deeplink? = switch url.scheme {
        case "ton":
            parseTonInvoiceUrl(url)
        case "tc":
            parseTonConnectUrl(url)
        case let scheme where scheme == TONCONNECT_PROTOCOL_SCHEME:
            parseTonConnectUrl(url)
        case "wc":
            parseWalletConnectUrl(url)
        case let scheme where scheme == SELF_PROTOCOL_SCHEME:
            parseMtwUrl(url)
        case "https", "http":
            switch url.host {
            case let host? where isTonConnectUniversalUrl(host: host, path: url.path):
                parseTonConnectUrl(url)
            case "walletconnect.com":
                if url.path == "/wc" {
                    parseWalletConnectUrl(url)
                } else {
                    nil
                }
            case let host? where SELF_UNIVERSAL_URL_HOSTS.contains(host):
                parseMtwUrl(url)
            default:
                nil
            }
        default:
            nil
        }
        if let deeplink {
            self = deeplink
        } else {
            return nil
        }
    }
}

private func isTonConnectUniversalUrl(host: String, path: String) -> Bool {
    guard let url = URL(string: TONCONNECT_UNIVERSAL_URL),
          let universalHost = url.host?.lowercased() else {
        return false
    }
    guard host.lowercased() == universalHost else {
        return false
    }
    let universalPath = url.path
    if universalPath.isEmpty {
        return true
    }
    return path == universalPath
}

private func parseTonConnectUrl(_ url: URL) -> Deeplink {
    Deeplink.tonConnect2(requestLink: url.absoluteString)
}

private func parseWalletConnectUrl(_ url: URL) -> Deeplink {
    Deeplink.walletConnect(requestLink: url.absoluteString)
}

private func parseTonInvoiceUrl(_ url: URL) -> Deeplink? {
    guard let parsedWalletURL = parseTonTransferUrl(url) else {
        return nil
    }
    return Deeplink.invoice(
        address: parsedWalletURL.address,
        amount: parsedWalletURL.amount,
        comment: parsedWalletURL.comment,
        binaryPayload: parsedWalletURL.bin,
        token: parsedWalletURL.token,
        jetton: parsedWalletURL.jetton,
        stateInit: parsedWalletURL.stateInit
    )
}

private func parseMtwUrl(_ url: URL) -> Deeplink? {
    
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
    case "agent":
        return .agent

    case "classic":
        return .switchToClassic
        
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
        return .swap(from: from, to: to, amountIn: amountIn)

    case "transfer":
        if url.pathComponents.count <= 1 {
            return .transfer
        } else {
            return parseTonInvoiceUrl(url)
        }

    case "send":
        return parseSendUrl(url)

    case "buy-with-card":
        return .buyWithCard
        
    case Deeplink.Sell.urlHost:
        return .sell(.init(url))

    case "stake":
        return .stake

    case "portfolio":
        return .portfolio

    case "settings":
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if let section = pathComponents.first?.nilIfEmpty {
            guard let settingsSection = AppSettingsSection(rawValue: section) else { return nil }
            return .settings(section: settingsSection)
        }
        return .settings(section: nil)

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
        return .url(config: InAppBrowserPageConfig(
                url: url,
                title: "Giveaway",
                injectDappConnect: true
        ))
        
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
        return .url(config: InAppBrowserPageConfig(
            url: url,
            title: "Checkin",
            injectDappConnect: true
        ))
        
    case "receive":
        return .receive
        
    case "explore":
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        return .explore(siteHost: pathComponents.first?.nilIfEmpty)

    case "token":
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if pathComponents.count >= 2 {
            // mtw://token/{chain}/{tokenAddress}
            guard let chain = ApiChain(rawValue: pathComponents[0]) else { return nil }
            let tokenAddress = pathComponents[1]
            return .tokenAddress(chain: chain, tokenAddress: tokenAddress)
        } else if pathComponents.count == 1 {
            // mtw://token/{slug}
            let slug = pathComponents[0]
            return .tokenSlug(slug: slug)
        } else {
            return nil
        }
    
    case "tx":
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { return nil }
        let chainString = pathComponents[0]
        let txId = pathComponents.dropFirst().joined(separator: "/")
        guard let chain = ApiChain(rawValue: chainString), chain.isSupported else { return nil }
        return .transaction(chain: chain, txId: txId)

    case "nft":
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard let nftAddress = pathComponents.first?.nilIfEmpty else { return nil }
        return .nftAddress(nftAddress: nftAddress)
        
    case "view":
        var addressOrDomainByChain: [String: String] = [:]
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for queryItem in queryItems {
            if let chain = ApiChain(rawValue: queryItem.name),
               chain.isSupported,
               let addressOrDomain = queryItem.value?.nilIfEmpty,
               chain.isValidAddressOrDomain(addressOrDomain) {
                addressOrDomainByChain[chain.rawValue] = addressOrDomain
            }
        }
        if let evmAddress = queryItems.first(where: { $0.name == ApiChain.viewAccountEvmParam })?.value?.nilIfEmpty,
           ApiChain.ethereum.isValidAddressOrDomain(evmAddress) {
            for chain in ApiChain.evmChains where addressOrDomainByChain[chain.rawValue] == nil {
                addressOrDomainByChain[chain.rawValue] = evmAddress
            }
        }
        return .view(addressOrDomainByChain: addressOrDomainByChain)

    default:
        return nil
    }
}

private func parseSendUrl(_ url: URL) -> Deeplink? {
    let pathComponents = url.pathComponents.filter { $0 != "/" }
    guard let target = pathComponents.first else { return nil }

    // Format: {chain}:{address}
    guard let colonIndex = target.firstIndex(of: ":") else { return nil }
    let chainString = String(target[target.startIndex..<colonIndex])
    let address = String(target[target.index(after: colonIndex)...])

    guard let chain = ApiChain(rawValue: chainString), chain.isSupported else { return nil }
    guard chain.isValidAddressOrDomain(address) else { return nil }

    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    var amount: BigInt?
    var comment: String?
    var binaryPayload: String?
    var tokenSlug: String?
    var stateInit: String?

    for item in queryItems {
        guard let value = item.value, !value.isEmpty else { continue }
        switch item.name {
        case "amount":
            amount = BigInt(value)
        case "text":
            comment = value
        case "bin":
            binaryPayload = value
        case "token":
            tokenSlug = value
        case "init", "stateInit":
            stateInit = value
        default:
            break
        }
    }

    return .send(
        chain: chain,
        address: address,
        amount: amount,
        comment: comment,
        binaryPayload: binaryPayload,
        tokenSlug: tokenSlug,
        stateInit: stateInit
    )
}

extension Deeplink {
    struct Sell {
        static let urlHost = "offramp"
        
        let transactionId: String?
        let baseCurrencyCode: String?
        let baseCurrencyAmount: String?
        let depositWalletAddress: String?
        let depositWalletAddressTag: String?

        init(_ url: URL) {
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            var transactionId: String?
            var baseCurrencyCode: String?
            var baseCurrencyAmount: String?
            var depositWalletAddress: String?
            var depositWalletAddressTag: String?

            for item in queryItems {
                guard let value = item.value, !value.isEmpty else { continue }
                switch item.name {
                case "transactionId": transactionId = value
                case "baseCurrencyCode": baseCurrencyCode = value
                case "baseCurrencyAmount": baseCurrencyAmount = value
                case "depositWalletAddress": depositWalletAddress = value
                case "depositWalletAddressTag": depositWalletAddressTag = value
                default: break
                }
            }
            
            self.transactionId = transactionId
            self.baseCurrencyCode = baseCurrencyCode
            self.baseCurrencyAmount = baseCurrencyAmount
            self.depositWalletAddress = depositWalletAddress
            self.depositWalletAddressTag = depositWalletAddressTag
        }
    }
}
