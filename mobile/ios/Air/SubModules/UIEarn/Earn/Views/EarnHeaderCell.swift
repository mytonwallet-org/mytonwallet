//
//  EarnHeaderCell.swift
//  UIEarn
//
//  Created by Sina on 5/13/24.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

class EarnHeaderCell: UITableViewCell, WThemedView {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let amountLabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .rounded(ofSize: 48, weight: .bold)
        lbl.text = "0"
        return lbl
    }()
    
    private var amountContainer: WSensitiveData<UIStackView> = .init(cols: 13, rows: 3, cellSize: 14, cornerRadius: 10, theme: .adaptive, alignment: .center)
    
    private lazy var amountView: UIStackView = {
        let v = UIStackView()
        v.semanticContentAttribute = .forceLeftToRight
        v.translatesAutoresizingMaskIntoConstraints = false
        v.axis = .horizontal
        v.addArrangedSubview(amountLabel)
        v.addArrangedSubview(UIView())
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(equalToConstant: 56)
        ])
        return v
    }()
    
    private lazy var yourBalanceHintLabel = {
        let lbl = UILabel()
        lbl.text = lang("Your staking balance")
        lbl.font = .systemFont(ofSize: 16)
        lbl.numberOfLines = 0
        lbl.textAlignment = .center
        lbl.text = lang("Your staking balance") + "\n"
        return lbl
    }()
    
    private lazy var addStakeButton = {
        let btn = WButton(style: .primary)
        btn.setTitle(lang("Add Stake"), for: .normal)
        btn.addTarget(self, action: #selector(addStakePressed), for: .touchUpInside)
        return btn
    }()
    
    private lazy var unstakeButton = {
        let btn = WButton(style: .secondary)
        btn.setTitle(lang("Unstake"), for: .normal)
        btn.addTarget(self, action: #selector(unstakePressed), for: .touchUpInside)
        return btn
    }()
    
    private let indicatorView = WActivityIndicator()
    
    private lazy var actionsStackView = {
        let v = UIStackView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.distribution = .fillEqually
        v.addArrangedSubview(addStakeButton)
        v.addArrangedSubview(unstakeButton, spacing: 12)
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(equalToConstant: 50)
        ])
        return v
    }()
    
    private var bottomCornersViewContainer: UIView!
    private var bottomCornersView: UIView!
    
    private lazy var stackView = {
        let v = UIStackView()
        v.alignment = .center
        v.distribution = .fill
        v.translatesAutoresizingMaskIntoConstraints = false
        v.axis = .vertical
        amountContainer.addContent(amountView)
        v.addArrangedSubview(amountContainer, spacing: 16)
        v.addArrangedSubview(yourBalanceHintLabel, spacing: 9)
        v.addArrangedSubview(actionsStackView, margin: .init(top: 14, left: 16, bottom: 16, right: 16))
        let actionsWidthAnchor = actionsStackView.widthAnchor.constraint(equalToConstant: 500)
        actionsWidthAnchor.priority = .defaultHigh
        NSLayoutConstraint.activate([
            actionsWidthAnchor,
            yourBalanceHintLabel.widthAnchor.constraint(equalTo: v.widthAnchor, constant: -64)
        ])
        v.alpha = 0
        return v
    }()
    
    private func setupViews() {
        backgroundColor = WTheme.sheetBackground
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
        ])
        
        // reversed bottom corner radius
        bottomCornersViewContainer = UIView()
        bottomCornersViewContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomCornersView = ReversedCornerRadiusView()
        bottomCornersView.translatesAutoresizingMaskIntoConstraints = false
        bottomCornersView.isUserInteractionEnabled = false
        bottomCornersViewContainer.addSubview(bottomCornersView)
        contentView.addSubview(bottomCornersViewContainer)
        NSLayoutConstraint.activate([
            bottomCornersView.leftAnchor.constraint(equalTo: bottomCornersViewContainer.leftAnchor),
            bottomCornersView.rightAnchor.constraint(equalTo: bottomCornersViewContainer.rightAnchor),
            bottomCornersView.topAnchor.constraint(equalTo: bottomCornersViewContainer.topAnchor),
            bottomCornersView.bottomAnchor.constraint(equalTo: bottomCornersViewContainer.bottomAnchor),
            bottomCornersViewContainer.widthAnchor.constraint(equalTo: contentView.widthAnchor),
            bottomCornersViewContainer.heightAnchor.constraint(equalToConstant: ReversedCornerRadiusView.defaultRadius),
            bottomCornersViewContainer.topAnchor.constraint(equalTo: stackView.bottomAnchor),
            bottomCornersViewContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 12)
        ])
        
        indicatorView.translatesAutoresizingMaskIntoConstraints = false
        indicatorView.stopAnimating(animated: false)
        indicatorView.isHidden = true
        contentView.addSubview(indicatorView)
        NSLayoutConstraint.activate([
            indicatorView.centerXAnchor.constraint(equalTo: stackView.centerXAnchor),
            indicatorView.centerYAnchor.constraint(equalTo: stackView.centerYAnchor),
        ])

        updateTheme()
    }

    public func updateTheme() {
        yourBalanceHintLabel.textColor = WTheme.secondaryLabel
        bottomCornersViewContainer.backgroundColor = WTheme.groupedItem
        bottomCornersView.backgroundColor = WTheme.sheetBackground
    }
    
    private func updateUnstakingInfo() {
        guard let unstakingAt else {return}
        let unstakingAtString = WStrings.Earn_UnstakeRequestInfo_Text(remainingTime: unstakingAt.remainingFromNow)
        yourBalanceHintLabel.text = lang("Your staking balance") + "\n" + unstakingAtString
        layoutIfNeeded()
    }
    
    private weak var earnVC: EarnVC? = nil
    private var unstakingAt: Date? = nil
    private var timer: Timer? = nil
    
    func configure(config: StakingConfig, delegate: EarnVC) {
        let token = config.baseToken
        if let state = config.stakingState {
            let stakingBalance = config.fullStakingBalance ?? 0
            amountLabel.attributedText = TokenAmount(stakingBalance, token).formatAttributed(
                format: .init(maxDecimals: 4),
                integerFont: .rounded(ofSize: 48, weight: .bold),
                fractionFont: .rounded(ofSize: 32, weight: .bold),
                symbolFont: .rounded(ofSize: 32, weight: .bold),
                integerColor: WTheme.primaryLabel,
                fractionColor: WTheme.primaryLabel,
                symbolColor: WTheme.secondaryLabel
            )
            unstakeButton.isHidden = stakingBalance == 0
            self.unstakingAt = config.unstakeTime
            if let amount = config.stakingState?.unstakeRequestAmount, amount > 0, unstakingAt != nil {
                self.updateUnstakingInfo()
                if timer == nil {
                    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                        self?.updateUnstakingInfo()
                    }
                }
            } else {
                timer?.invalidate()
                yourBalanceHintLabel.text = lang("Your staking balance") + "\n"
            }
            self.earnVC = delegate
            if stackView.alpha == 0 {
                UIView.animate(withDuration: 0.5) { [weak self] in
                    guard let self else {return}
                    stackView.alpha = 1
                }
            }
            amountView.isHidden = false
            indicatorView.isHidden = true
            indicatorView.stopAnimating(animated: true)
        } else {
            amountView.isHidden = true
            indicatorView.startAnimating(animated: true)
            indicatorView.isHidden = false
        }
    }
    
    @objc func addStakePressed() {
        earnVC?.stakeUnstakePressed(isStake: true)
    }
    
    @objc func unstakePressed() {
        earnVC?.stakeUnstakePressed(isStake: false)
    }
}
