//
//  WalletSettingsNavigationHeader.swift
//
//  Created by nikstar on 02.11.2025.
//

import UIKit
import WalletCore
import WalletContext
import UIComponents
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import UIKitNavigation

/// The only reason this is used is .contentTransition(.numericText()) transition
private struct ContentView: View {
    
    let viewModel: WalletSettingsViewModel
    let sensitiveRows: Int
    let sensitiveCols: Int
    var onMaskStateChanged: ((Bool) -> Void)? = nil
    
    @Dependency(\.accountStore.accountsById.values) private var accounts
    @Dependency(\.balanceDataStore) private var balanceDataStore
    
    var body: some View {
        WithPerceptionTracking {
            NavigationHeader {
                Text(viewModel.navigationHeaderTitle(in: accounts))
                    .fixedSize()
            } subtitle: {
                Text(viewModel.navigationHeaderBalance(from: balanceDataStore))
                    .fixedSize()
                    .id(viewModel.currentFilter)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .sensitiveData(
                        alignment: .center,
                        cols: sensitiveCols,
                        rows: sensitiveRows,
                        cellSize: nil,
                        theme: .adaptive,
                        cornerRadius: 4,
                        onMaskStateChanged: onMaskStateChanged
                    )
            }
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.3), value: viewModel.walletCount(in: accounts))
            .animation(.smooth(duration: 0.3), value: viewModel.totalBalance(from: balanceDataStore))
        }
    }
}

class WalletSettingsNavigationHeader: UIView {
    private let viewModel: WalletSettingsViewModel
    private var observeToken: ObserveToken?
    private var isMaskVisible: Bool = false
    
    @Dependency(\.accountStore.accountsById.values) private var accounts
    @Dependency(\.balanceDataStore) private var balanceDataStore
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        return label
    }()
    
    private let balanceLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .regular)
        return label
    }()
    
    private let sensitiveRows = 2
    private let sensitiveCols = 12
    private let balanceSensitiveContainer: WSensitiveData<UILabel>
    
    private lazy var hostingView = HostingView {
        ContentView(
            viewModel: viewModel,
            sensitiveRows: sensitiveRows,
            sensitiveCols: sensitiveCols,
            onMaskStateChanged: { [weak self] isMaskVisible in
                self?.isMaskVisible = isMaskVisible
                self?.relayout(animated: true)
            }
        )
    }
        
    init(viewModel: WalletSettingsViewModel) {
        self.viewModel = viewModel
        
        balanceSensitiveContainer = WSensitiveData(
            cols: sensitiveCols,
            rows: sensitiveRows,
            cellSize: balanceLabel.font.lineHeight / CGFloat(sensitiveRows),
            cornerRadius: 4,
            theme: .adaptive,
            alignment: .center
        )
        
        super.init(frame: .zero)
        
        balanceLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceSensitiveContainer.addContent(balanceLabel)
        balanceSensitiveContainer.onMaskStateChanged = { [weak self] _ in
            self?.relayout(animated: true)
        }
                
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
                        
        NSLayoutConstraint.activate([
            hostingView.centerXAnchor.constraint(equalTo: centerXAnchor),
            hostingView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        
        observeToken = observe { [weak self] in
            guard let self else { return }
            _ = viewModel.currentFilter
            _ = accounts
            _ = balanceDataStore
            updateContent()
        }
        
        updateContent()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    
    deinit {
        observeToken?.cancel()
    }
    
    private func updateContent() {
        update(
            title: viewModel.navigationHeaderTitle(in: accounts),
            balance: viewModel.navigationHeaderBalance(from: balanceDataStore)
        )
    }
    
    func update(title: String, balance: String) {
        titleLabel.text = title
        balanceLabel.text = balance
        relayout(animated: false)
    }
    
    private func relayout(animated: Bool) {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        
        if let superview {
            superview.setNeedsLayout()
            if animated {
                UIView.animate(withDuration: 0.3) {
                    superview.layoutIfNeeded()
                }
            } else {
                superview.layoutIfNeeded()
            }
        }
    }
        
    override var intrinsicContentSize: CGSize {
        let titleSize = titleLabel.intrinsicContentSize
        let subtitleSize: CGSize
        if isMaskVisible {
            subtitleSize = balanceSensitiveContainer.maskSize
        } else {
            subtitleSize = balanceLabel.intrinsicContentSize
        }
        return CGSize(
            width: ceil(max(titleSize.width, subtitleSize.width)),
            height: ceil(titleSize.height + 3 + subtitleSize.height)
        )
    }
}
