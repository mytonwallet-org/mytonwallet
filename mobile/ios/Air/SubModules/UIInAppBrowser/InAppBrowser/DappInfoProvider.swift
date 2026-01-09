
import UIKit
import WebKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("DappInfoProvider")

struct DappInfo {
    var iconUrl: String
    var shortTitle: String
}

@MainActor final class DappInfoProvider: WalletCoreData.EventsObserver {
    
    var exploreSites: Dictionary<String, ApiSite> = [:]
    var connectedDapps: Dictionary<String, ApiDapp> = [:]
    
    init() {
        refresh()
        WalletCoreData.add(eventObserver: self)
    }
    
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged:
            loadDapps()
        case .dappsCountUpdated:
            loadDapps()
        default:
            break
        }
    }
    
    func refresh() {
        loadExploreSites()
        loadDapps()
    }
    
    func loadExploreSites() {
        Task { [weak self] in
            do {
                let result = try await Api.loadExploreSites(langCode: LocalizationSupport.shared.langCode)
                self?.exploreSites = result.sites.dictionaryByKey(\.url)
            } catch {
                log.error("failed to fetch explore sites \(error, .public)")
            }
        }
    }
    
    private func loadDapps() {
        Task {
            do {
                if let accountId = AccountStore.accountId {
                    let dapps = try await Api.getDapps(accountId: accountId)
                    self.connectedDapps = dapps.dictionaryByKey(\.url)
                }
            } catch {
                try? await Task.sleep(for: .seconds(3))
                loadDapps()
            }
        }
    }
    
    func getDappInfo(for url: URL?) -> DappInfo? {
        guard let url, let host = url.host(), !host.isEmpty else { return nil }
        for (_, app) in connectedDapps {
            if let url = URL(string: app.url), url.host() == host {
                return DappInfo(iconUrl: app.iconUrl, shortTitle: app.name)
            }
        }
        for (_, site) in exploreSites {
            if let url = URL(string: site.url), url.host() == host {
                return DappInfo(iconUrl: site.icon, shortTitle: site.name)
            }
        }
        return nil 
    }
}
