//
//  ConnectedAppsVC.swift
//  UISettings
//
//  Created by Sina on 8/30/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext


public class ConnectedAppsVC: WViewController {
    
    private var dapps: [ApiDapp]? = nil
    private let isModal: Bool
    
    public init(isModal: Bool) {
        self.isModal = isModal
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Load and SetupView Functions
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        WalletCoreData.add(eventObserver: self)
        loadDapps()
    }
    
    private var tableView: UITableView!
    private func setupViews() {
        title = lang("Connected Apps")
        
        addNavigationBar(
            title: title,
            closeIcon: isModal,
            addBackButton: isModal ? nil : { [weak self] in self?.navigationController?.popViewController(animated: true) },
        )
        
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(DisconnectAllCell.self, forCellReuseIdentifier: "DisconnectAll")
        tableView.register(DappCell.self, forCellReuseIdentifier: "Dapp")
        tableView.separatorStyle = .none
        tableView.delaysContentTouches = false
        tableView.contentInset.top = navigationBarHeight
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // full width back gesture recognizer interferes with delete gesture
        if let gestureRecognizer = tableView.gestureRecognizers?.first(where: { $0.description.starts(with: "<_UISwipeActionPanGestureRecognizer") }) {
            (navigationController as? WNavigationController)?.fullWidthBackGestureRecognizerRequireToFail(gestureRecognizer)
        }
        
        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.groupedBackground
        tableView.backgroundColor = view.backgroundColor
    }

    public override func scrollToTop(animated: Bool) {
        tableView?.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: animated)
    }
    
    private var emptyDappsView: HeaderView? = nil
    private func updateEmptyAssetsView() {
        guard let dapps else {
            // Loading assets
            emptyDappsView?.removeFromSuperview()
            emptyDappsView = nil
            return
        }
        if dapps.isEmpty {
            // Show empty assets view
            if emptyDappsView == nil {
                emptyDappsView = HeaderView(animationName: "NoResults",
                                            animationPlaybackMode: .loop,
                                            title: lang("You have no apps connected to this wallet."),
                                            description: nil,
                                            compactMode: true)
                emptyDappsView!.lblTitle.font = .systemFont(ofSize: 17, weight: .medium)
                emptyDappsView?.alpha = 0
                view.addSubview(emptyDappsView!)
                NSLayoutConstraint.activate([
                    emptyDappsView!.widthAnchor.constraint(equalToConstant: 200),
                    emptyDappsView!.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    emptyDappsView!.centerYAnchor.constraint(equalTo: view.centerYAnchor)
                ])
            }
            UIView.animate(withDuration: 0.3) {
                self.emptyDappsView?.alpha = 1
            }
        } else {
            // Not empty, hide empty assets view
            UIView.animate(withDuration: 0.3) {
                self.emptyDappsView?.alpha = 0
            } completion: { _ in
                self.emptyDappsView?.removeFromSuperview()
                self.emptyDappsView = nil
            }
        }
    }
    
    private func loadDapps() {
        Task {
            do {
                if let accountId = AccountStore.accountId {
                    let dapps = try await Api.getDapps(accountId: accountId)
                    self.dapps = dapps
                    tableView.reloadData()
                    updateEmptyAssetsView()
                }
            } catch {
                try? await Task.sleep(for: .seconds(3))
                loadDapps()
            }
        }
    }
    
    private func disconnectAllPressed() {
        showAlert(title: lang("Disconnect Dapps"),
                  text: lang("Are you sure you want to disconnect all websites?"),
                  button: lang("Disconnect"),
                  buttonStyle: .destructive,
                  buttonPressed: { [weak self] in
            self?.deleteAllDapps()
        }, secondaryButton: lang("Cancel"))
    }
    
    private func deleteAllDapps() {
        guard let accountId = AccountStore.accountId else { return }
        Task {
            do {
                try await DappsStore.deleteAllDapps(accountId: accountId)
            } catch {
                self.showAlert(error: error)
            }
        }
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateNavigationBarProgressiveBlur(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
    }
}


extension ConnectedAppsVC: UITableViewDelegate, UITableViewDataSource {
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        dapps?.count ?? 0 > 0 ? 1 : 0
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dapps?.count ?? 0 > 0 ? 1 + dapps!.count : 0
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "DisconnectAll", for: indexPath) as! DisconnectAllCell
            cell.configure(isInModal: false) { [weak self] in
                self?.disconnectAllPressed()
            }
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Dapp", for: indexPath) as! DappCell
            cell.configure(dapp: dapps![indexPath.row - 1],
                           isFirst: false,
                           isLast: indexPath.row == dapps!.count,
                           isInModal: false)
            return cell
        }
    }
    
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return lang("Logged in with MyTonWallet").uppercased()
        
    }
    
    public func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let dapps, indexPath.row - 1 < dapps.count else { return nil }
        let dapp = dapps[indexPath.row - 1]
        let deleteAction = UIContextualAction(style: .destructive, title: lang("Disconnect")) { [weak self] action, indexPath, callback  in
            self?.dapps?.removeAll(where: { $0 == dapp })
            Task { @MainActor in
                do {
                    try await DappsStore.deleteDapp(dapp: dapp)
                    callback(true)
                } catch {
                    callback(false)
                }
            }
        }
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }
}


extension ConnectedAppsVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCore.WalletCoreData.Event) {
        switch event {
        case .dappsCountUpdated:
            loadDapps()
            break
        default:
            break
        }
    }
}
