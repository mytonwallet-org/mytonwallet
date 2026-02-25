//
//  TokenChartCell.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/28/25.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

class TokenChartCell: FirstRowCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var chartContainerView: TokenExpandableChartView? = nil
    var height: CGFloat? { chartContainerView?.height }

    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    func setup(parentProcessorQueue: DispatchQueue,
               onHeightChange: @escaping () -> Void) {
        guard chartContainerView == nil else {
            return
        }
        chartContainerView = TokenExpandableChartView(parentProcessorQueue: parentProcessorQueue,
                                                      onHeightChange: onHeightChange)
        contentView.addSubview(chartContainerView!)
        NSLayoutConstraint.activate([
            chartContainerView!.topAnchor.constraint(equalTo: contentView.topAnchor),
            chartContainerView!.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            chartContainerView!.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            chartContainerView!.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
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
