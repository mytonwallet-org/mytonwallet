//
//  PreviewActivityCell.swift
//  UIComponents
//
//  Created by nikstar on 20.08.2025.
//

import UIKit
import WalletCore
import WalletContext
import SwiftUI

public struct WPreviewActivityCell: UIViewRepresentable {

    @MainActor public struct ConfigureOptions {
        var activity: ApiActivity
        var accountContext: AccountContext
        var tokenStore: _TokenStore

        public init(activity: ApiActivity, accountContext: AccountContext, tokenStore: _TokenStore) {
            self.activity = activity
            self.accountContext = accountContext
            self.tokenStore = tokenStore
        }
    }

    public var configureOptions: ConfigureOptions

    public init(_ configureOptions: ConfigureOptions) {
        self.configureOptions = configureOptions
    }

    public func makeUIView(context: Context) -> ActivityCell {
        let cell = ActivityCell()
        configure(cell)
        return cell
    }

    public func updateUIView(_ cell: ActivityCell, context: Context) {
        Task { @MainActor in
            configure(cell)
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView cell: ActivityCell, context: Context) -> CGSize? {
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            let targetSize = CGSize(width: proposedWidth, height: UIView.layoutFittingCompressedSize.height)
            let fitting = cell.systemLayoutSizeFitting(
                targetSize,
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            return CGSize(width: proposedWidth, height: fitting.height)
        }

        return cell.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }

    @MainActor
    private func configure(_ cell: ActivityCell) {
        cell.configurePreview(
            with: configureOptions.activity,
            accountContext: configureOptions.accountContext,
            tokenStore: configureOptions.tokenStore
        )
    }
}
