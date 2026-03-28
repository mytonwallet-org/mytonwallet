//
//  TokenChartCell.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/28/25.
//

import UIKit
import UIActivityList
import UIComponents
import WalletCore
import WalletContext

final class TokenChartCell: FirstRowCell {
    private let horizontalInset = S.insetSectionHorizontalMargin

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private lazy var chartContainerView: TokenExpandableChartView? = nil
    override var height: CGFloat? {
        get { chartContainerView?.height }
        set {}
    }

    private func setupViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    func setup(onHeightChange: @escaping () -> Void) {
        guard chartContainerView == nil else {
            return
        }
        chartContainerView = TokenExpandableChartView(onHeightChange: onHeightChange)
        contentView.addSubview(chartContainerView!)
        NSLayoutConstraint.activate([
            chartContainerView!.topAnchor.constraint(equalTo: contentView.topAnchor),
            chartContainerView!.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            chartContainerView!.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            chartContainerView!.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
        ])
    }

    func configure(token: ApiToken,
                   historyData: [[Double]]?,
                   onPeriodChange: @escaping (ApiPriceHistoryPeriod) -> Void) {
        chartContainerView?.configure(token: token,
                                      historyData: historyData) { [weak self] period in
            guard let _ = self else { return }
            onPeriodChange(period)
        }
    }

}
