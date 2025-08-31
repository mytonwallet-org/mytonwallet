//
//  ExploreVM.swift
//  UIBrowser
//
//  Created by Sina on 6/25/24.
//

import Foundation
import WalletCore
import WalletContext
@preconcurrency import WReachability
import OrderedCollections

private let log = Log("ExploreVM")


@MainActor protocol ExploreVMDelegate: AnyObject {
    func exploreSitsUpdated()
}


@MainActor class ExploreVM: WalletCoreData.EventsObserver {
    
    let reachability = try! Reachability()
    private var waitingForNetwork = false
    deinit {
        reachability.stopNotifier()
    }
    
    // MARK: - Initializer
    weak var delegate: ExploreVMDelegate?
    var exploreSites: OrderedDictionary<String, ApiSite> = [:]
    var exploreCategories: OrderedDictionary<Int, ApiSiteCategory> = [:]
    var connectedDapps: OrderedDictionary<String, ApiDapp> = [:]
    private var loadExploreSitesTask: Task<Void, Never>?
    
    init() {
        // Listen for network connection events
        reachability.whenReachable = { [weak self] reachability in
            guard let self else {return}
            if waitingForNetwork {
                refresh()
                waitingForNetwork = false
            }
        }
        reachability.whenUnreachable = { [weak self] _ in
            self?.waitingForNetwork = true
        }
        do {
            try reachability.startNotifier()
        } catch {
        }
        
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
        guard self.loadExploreSitesTask == nil || self.loadExploreSitesTask?.isCancelled == true else { return }
        self.loadExploreSitesTask = Task { [weak self] in
            do {
                let result = try await Api.loadExploreSites()
                self?.updateExploreSites(result)
            } catch {
                log.error("failed to fetch explore sites \(error, .public)")
                if self?.waitingForNetwork == false {
                    try? await Task.sleep(for: .seconds(3))
                    if !Task.isCancelled {
                        if self?.exploreSites == nil {
                            self?.refresh()
                        }
                    }
                }
            }
            if !Task.isCancelled {
                self?.loadExploreSitesTask = nil
            }
        }
    }
    
    func updateExploreSites(_ result: Api.ExploreSitesResult) {
        exploreSites = OrderedDictionary(result.sites.map { ($0.url, $0) }, uniquingKeysWith: { $1 })
        exploreCategories = OrderedDictionary(result.categories.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        DispatchQueue.main.async {
            self.delegate?.exploreSitsUpdated()
        }
    }
    
    private func loadDapps() {
        Task {
            do {
                if let accountId = AccountStore.accountId {
                    let dapps = try await Api.getDapps(accountId: accountId)
                    await self.updateDapps(dapps: dapps)
                }
            } catch {
                try? await Task.sleep(for: .seconds(3))
                loadDapps()
            }
        }
    }
    
    func updateDapps(dapps: [ApiDapp]) {
        self.connectedDapps = OrderedDictionary(dapps.map { ($0.url, $0) }, uniquingKeysWith: { $1 })
        self.delegate?.exploreSitsUpdated()
    }
}
