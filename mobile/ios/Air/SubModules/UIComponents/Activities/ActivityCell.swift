
import Kingfisher
import UIKit
import WalletContext
import WalletCore
import Perception
import Dependencies
import SwiftNavigation

@Perceptible
public class ActivityCellViewModel {
    
    @PerceptionIgnored
    var activity: ApiActivity
    
    @PerceptionIgnored
    var tokenStore: _TokenStore
    @PerceptionIgnored
    @AccountContext var account: MAccount
    
    init(accountId: String?, activity: ApiActivity) {
        @Dependency(\.tokenStore) var tokenStore
        self.tokenStore = tokenStore
        self._account = AccountContext(accountId: accountId)
        self.activity = activity
    }
}

public class ActivityCell: WHighlightCell {

    @MainActor
    public protocol Delegate: AnyObject {
        func onSelect(transaction: ApiActivity)
    }
    
    class Layer: CALayer {
        override var cornerRadius: CGFloat {
            get { S.homeInsetSectionCornerRadius }
            set { _ = newValue }
        }
    }
    public override class var layerClass: AnyClass { Layer.self }

    static let regular14Font = UIFont.systemFont(ofSize: 14, weight: .regular)
    static let regular16Font = UIFont.systemFont(ofSize: 16, weight: .regular)
    static let medium16Font = UIFont.systemFont(ofSize: 16, weight: .medium)
    
    var skeletonView: ActivityCell.Skeleton? = nil

    let mainView = UIView()
    let firstTwoRows: UIView = .init()
    
    let iconView: IconView = .init(size: 40)
    
    let titleLabel: UILabel = .init()
    let scamBadge: UIImageView = .init()
    
    let detailsLabel: UILabel = .init()
    
    private let rightChevron: UIImageView = {
        let imageView = UIImageView(image: .airBundle("RightArrowIcon"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    var amountContainer: WSensitiveData<UILabel> = .init(cols: 12, rows: 2, cellSize: 9, cornerRadius: 5, theme: .adaptive, alignment: .trailing)
    var amountLabel: UILabel!
    var amountIcon1 = IconView(size: 18, borderWidth: 1, borderColor: WTheme.groupedItem)
    var amountIcon2 = IconView(size: 18, borderWidth: 1, borderColor: WTheme.groupedItem)
    var amountIcon2Constraints: [NSLayoutConstraint] = []
    
    var amount2Container: WSensitiveData<UILabel> = .init(cols: 9, rows: 2, cellSize: 7, cornerRadius: 4, theme: .adaptive, alignment: .trailing)
    var amount2Label: UILabel!
    
    var nftView: NftPreviewLarge = .init()
    var nftViewConstraints: [NSLayoutConstraint] = []
    
    var commentView: BubbleView = .init()
    var commentViewConstraints: [NSLayoutConstraint] = []
    var commentViewLeadingConstraint: NSLayoutConstraint!
    var commentViewTrailingConstraint: NSLayoutConstraint!
    private var firstTwoRowsTrailingConstraint: NSLayoutConstraint!
    private var firstTwoRowsTrailingToChevronConstraint: NSLayoutConstraint!

    var nftAndCommentConstraint: NSLayoutConstraint!
    
    weak var delegate: Delegate? = nil
    var activity: ApiActivity?
    var trackedValue: Double?

    var viewModel: ActivityCellViewModel!
    
    var observeAccountAndActivity: ObserveToken?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func prepareForReuse() {
        super.prepareForReuse()
        contentView.alpha = 1
        setShowsRightChevron(false)
    }
    
    @objc private func itemSelected() {
        if let activity, let delegate {
            delegate.onSelect(transaction: activity)
        }
    }

    func setupViews() {
        isExclusiveTouch = true
        selectionStyle = .none
        layer.cornerRadius = 20
        
        contentView.isUserInteractionEnabled = true
        contentView.backgroundColor = .clear
        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(itemSelected)))
        // setup whole cell as a vertical stack view
        
        mainView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainView)
        NSLayoutConstraint.activate([
            mainView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            mainView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            mainView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            mainView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10).withPriority(.init(999)), // affordance for cell separator
        ])

        // MARK: left icon
        mainView.addSubview(iconView)
        iconView.setChainSize(14, borderWidth: 1.333, borderColor: WTheme.background, horizontalOffset: 3, verticalOffset: 1)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: mainView.topAnchor),
            iconView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
        ])
        
        firstTwoRows.accessibilityIdentifier = "firstTwoRows"
        firstTwoRows.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(firstTwoRows)
        mainView.addSubview(rightChevron)
        rightChevron.isHidden = true
        
        firstTwoRowsTrailingConstraint = firstTwoRows.trailingAnchor.constraint(equalTo: mainView.trailingAnchor)
        firstTwoRowsTrailingToChevronConstraint = firstTwoRows.trailingAnchor.constraint(equalTo: rightChevron.leadingAnchor, constant: -10)
        firstTwoRowsTrailingToChevronConstraint.isActive = false
        NSLayoutConstraint.activate([
            firstTwoRows.topAnchor.constraint(equalTo: mainView.topAnchor),
            firstTwoRows.bottomAnchor.constraint(equalTo: mainView.bottomAnchor).withPriority(.init(500)),
            firstTwoRowsTrailingConstraint,
            firstTwoRows.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            
            rightChevron.trailingAnchor.constraint(equalTo: mainView.trailingAnchor),
            rightChevron.centerYAnchor.constraint(equalTo: firstTwoRows.centerYAnchor),
        ])

        // MARK: address
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        firstTwoRows.addSubview(titleLabel)
        titleLabel.font = ActivityCell.medium16Font
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: firstTwoRows.topAnchor, constant: 1.667),
            titleLabel.leadingAnchor.constraint(equalTo: firstTwoRows.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: firstTwoRows.trailingAnchor)
        ])
        
        scamBadge.translatesAutoresizingMaskIntoConstraints = false
        firstTwoRows.addSubview(scamBadge)
        scamBadge.contentMode = .center
        NSLayoutConstraint.activate([
            scamBadge.bottomAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor, constant: 2),
            scamBadge.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4.333),
        ])
        scamBadge.isHidden = true
        
        // MARK: type + time
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        firstTwoRows.addSubview(detailsLabel)
        NSLayoutConstraint.activate([
            detailsLabel.heightAnchor.constraint(equalToConstant: 18),
            detailsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1)
        ])
        detailsLabel.font = ActivityCell.regular14Font
        detailsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailsLabel.lineBreakMode = .byTruncatingMiddle

        // MARK: amount1
        amountLabel = WAmountLabel()
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountContainer.addContent(amountLabel)
        firstTwoRows.addSubview(amountContainer)
        NSLayoutConstraint.activate([
            amountLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            amountLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
        ])
        amountLabel.font = ActivityCell.regular16Font
        
        amountIcon1.translatesAutoresizingMaskIntoConstraints = false
        firstTwoRows.addSubview(amountIcon1)
        NSLayoutConstraint.activate([
            amountIcon1.leadingAnchor.constraint(equalTo: amountLabel.trailingAnchor, constant: 4),
            amountIcon1.bottomAnchor.constraint(equalTo: amountLabel.firstBaselineAnchor, constant: 3),
            amountIcon1.trailingAnchor.constraint(equalTo: firstTwoRows.trailingAnchor).withPriority(.defaultHigh), // overridden if amountIcon2 is visible
        ])

        amountIcon2.translatesAutoresizingMaskIntoConstraints = false
        firstTwoRows.addSubview(amountIcon2)
        amountIcon2Constraints = [
            amountIcon2.leadingAnchor.constraint(equalTo: amountIcon1.leadingAnchor, constant: 12),
            amountIcon2.centerYAnchor.constraint(equalTo: amountIcon1.centerYAnchor),
            amountIcon2.trailingAnchor.constraint(equalTo: firstTwoRows.trailingAnchor),
        ]
        amountIcon2.isHidden = true

        // MARK: amount2
        amount2Label = UILabel()
        amount2Label.font = ActivityCell.regular14Font
        amount2Label.translatesAutoresizingMaskIntoConstraints = false
        amount2Label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        amount2Container.addContent(amount2Label)
        firstTwoRows.addSubview(amount2Container)
        
        NSLayoutConstraint.activate([
            amount2Label.firstBaselineAnchor.constraint(equalTo: detailsLabel.firstBaselineAnchor),
            amount2Label.trailingAnchor.constraint(equalTo: amountIcon1.trailingAnchor).withPriority(.defaultHigh),
            amount2Label.leadingAnchor.constraint(greaterThanOrEqualTo: detailsLabel.trailingAnchor, constant: 6)
        ])
        amountIcon2Constraints.append(contentsOf: [
            amount2Label.trailingAnchor.constraint(equalTo: amountIcon2.trailingAnchor),
        ])
        amount2Label.font = ActivityCell.regular14Font
        amount2Label.textColor = WTheme.secondaryLabel

        NSLayoutConstraint.activate([
            firstTwoRows.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        amountContainer.isTapToRevealEnabled = false
        amount2Container.isTapToRevealEnabled = false
        
        // MARK: Nft
        
        nftView.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(nftView)
        nftViewConstraints = [
            nftView.topAnchor.constraint(equalTo: firstTwoRows.bottomAnchor, constant: 6),
            nftView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor).withPriority(.init(510)),
            nftView.leadingAnchor.constraint(equalTo: firstTwoRows.leadingAnchor),
            nftView.trailingAnchor.constraint(lessThanOrEqualTo: mainView.trailingAnchor),
        ]
        
        // MARK: Comment
        
        commentView.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(commentView)
        commentViewConstraints = [
            commentView.topAnchor.constraint(equalTo: firstTwoRows.bottomAnchor, constant: 6).withPriority(.init(910)),
            commentView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor),
            
            commentView.leadingAnchor.constraint(greaterThanOrEqualTo: firstTwoRows.leadingAnchor),
            commentView.trailingAnchor.constraint(lessThanOrEqualTo: mainView.trailingAnchor),
        ]
        commentViewLeadingConstraint = commentView.leadingAnchor.constraint(equalTo: firstTwoRows.leadingAnchor)
        commentViewTrailingConstraint = commentView.trailingAnchor.constraint(equalTo: mainView.trailingAnchor)
        
        // MARK: Shared constraints
        nftAndCommentConstraint = commentView.topAnchor.constraint(equalTo: nftView.bottomAnchor, constant: 6).withPriority(.init(920))
        
        updateTheme()
    }

    func updateTheme() {
        baseBackgroundColor = WTheme.groupedItem
        highlightBackgroundColor = WTheme.highlight
        skeletonView?.backgroundColor = WTheme.groupedItem
        detailsLabel.textColor = WTheme.secondaryLabel
        amount2Label.textColor = WTheme.secondaryLabel
    }
    
    private func setShowsRightChevron(_ shows: Bool) {
        rightChevron.isHidden = !shows
        firstTwoRowsTrailingConstraint.isActive = !shows
        firstTwoRowsTrailingToChevronConstraint.isActive = shows
    }

    
    // MARK: - Configure
    
    public func configure(with activity: ApiActivity, accountContext: AccountContext, delegate: Delegate, shouldFadeOutSkeleton: Bool, showsRightChevron: Bool = false) {
        
        if shouldFadeOutSkeleton {
            skeletonView?.layer.maskedCorners = contentView.layer.maskedCorners
            fadeOutSkeleton()
        } else if skeletonView?.alpha ?? 0 > 0 {
            skeletonView?.alpha = 0
            mainView.alpha = 1
        }
        self.activity = activity
        self.delegate = delegate
        setShowsRightChevron(showsRightChevron)

        self.configureViewModel(accountId: accountContext.accountId, activity: activity)
        
        iconView.config(with: activity)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        configureTitle(activity: activity)
        configureDetails(.init(activity: activity, accountContext: accountContext, isEmulation: false))
        configureAmount(.init(activity: activity, tokenStore: viewModel.tokenStore))
        configureAmount2(.init(activity: activity, tokenStore: viewModel.tokenStore))
        configureSensitiveData(activity: activity)
        configureNft(activity: activity)
        configureComment(activity: activity)
        
        nftAndCommentConstraint.isActive = !nftView.isHidden && !commentView.isHidden
        
        UIView.performWithoutAnimation {
            setNeedsLayout()
            layoutIfNeeded()
        }
        
        CATransaction.commit()
    }
    
    func configureViewModel(accountId: String, activity: ApiActivity) {
        if viewModel == nil {
            viewModel = ActivityCellViewModel(accountId: accountId, activity: activity)
            observeAccountAndActivity = observe { [weak self] in
                guard let self else { return }
                let activity = viewModel.activity
                if let chain = getChainBySlug(activity.slug), let peerAddress = activity.peerAddress {
                    _ = viewModel.$account.getLocalName(chain: chain, address: peerAddress)
                }
                configureDetails(.init(activity: activity, accountContext: viewModel.$account, isEmulation: false))
                configureAmount(.init(activity: activity, tokenStore: viewModel.tokenStore))
                configureAmount2(.init(activity: activity, tokenStore: viewModel.tokenStore))
            }
        } else {
            viewModel.$account.accountId = accountId
            viewModel.activity = activity
        }
    }
    
    public func updateToken() {
        if let activity {
            if (!amountIcon1.isHidden && amountIcon1.imageView.image == nil) || (!amountIcon2.isHidden && amountIcon2.imageView.image == nil) {
                configureAmount(.init(activity: activity, tokenStore: viewModel.tokenStore))
            }
            if !amount2Label.isHidden, case .transaction(let tx) = activity, let token = viewModel.tokenStore[tx.slug], token.price != self.trackedValue {
                configureAmount2(.init(activity: activity, tokenStore: viewModel.tokenStore))
            }
        }
    }
    
    func configureTitle(activity: ApiActivity, isEmulation: Bool = false) {
        if isEmulation {
            titleLabel.text = activity.displayTitle.future
        } else {
            titleLabel.text = activity.displayTitleResolvedOptimistic
        }
        
        if activity.isScamTransaction {
            if scamBadge.image == nil {
                scamBadge.image = .airBundle("ScamBadge")
            }
            scamBadge.isHidden = false
        } else {
            scamBadge.isHidden = true
        }
    }
    
    struct ConfigureDetailsOptions {
        var activity: ApiActivity
        var isMultichain = false
        var stakingState: ApiStakingState?
        var isEmulation: Bool
        var address: String = ""
        
        init(activity: ApiActivity, accountContext: AccountContext, isEmulation: Bool) {
            self.activity = activity
            self.isEmulation = isEmulation
            if  case .transaction(let transaction) = activity {
                isMultichain = accountContext.account.isMultichain
                if activity.shouldShowTransactionAnnualYield {
                    stakingState = accountContext.stakingData?.bySlug(activity.slug)
                }
                let chain = getChainBySlug(transaction.slug) ?? FALLBACK_CHAIN
                let vm = AddressViewModel.fromTransaction(transaction, chain: chain, addressKind: .peer).withLocalName(account: accountContext)
                if let name = vm.name {
                    self.address = name
                } else {
                    self.address = formatStartEndAddress(vm.address ?? "", prefix: 4, suffix: 4)
                }
            }
        }
    }
            
    func configureDetails(_ options: ConfigureDetailsOptions) {
        let activity = options.activity
        let attr = NSMutableAttributedString()
        
        switch activity {
        case .transaction(let transaction):
            if transaction.status == .failed {
                attr.append(NSAttributedString(string: lang("Failed")))
            }
            
            if activity.type == nil {
                if !attr.string.isEmpty {
                    attr.append(NSAttributedString(string: " · "))
                }
                if transaction.isIncoming {
                    attr.append(NSAttributedString(string: lang("$transaction_from", arg1: "")))
                } else {
                    attr.append(NSAttributedString(string: lang("$transaction_to", arg1: "")))
                }
                if options.isMultichain, let chain = getChainBySlug(activity.slug) {
                    let image = NSTextAttachment(image: .airBundle("ActivityAddress-\(chain)"))
                    image.bounds = .init(x: 0, y: -1.5, width: 13, height: 13)
                    attr.append(NSAttributedString(attachment: image))
                }
                attr.append(NSAttributedString(string: options.address, attributes: [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
                ]))
            } else if activity.shouldShowTransactionAnnualYield, let stakingState = options.stakingState {
                if !attr.string.isEmpty {
                    attr.append(NSAttributedString(string: " · "))
                }
                attr.append(NSAttributedString(string: "at "))
                attr.append(NSAttributedString(string: "\(stakingState.yieldType.rawValue) \(stakingState.annualYield.value)%", attributes: [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
                ]))
            } else {
                // TODO: auction bid, nft bought
            }
        case .swap(let swap):
            var status: String?
            switch swap.status {
            case .pending, .pendingTrusted:
                if swap.fromToken?.isOnChain ?? true {
                    status = lang("In Progress")
                } else {
                    if swap.cex?.status.uiStatus == .pending {
                        status = lang("Waiting for Payment")
                    } else {
                        status = lang("In Progress")
                    }
                }
            case .completed, .confirmed:
                break
            case .failed:
                status = lang("Failed swap")
            case .expired:
                status = lang("Expired swap")
            }
            if let status {
                attr.append(NSAttributedString(string: status))
            }
        }
        if !options.isEmulation {
            if !attr.string.isEmpty {
                attr.append(NSAttributedString(string: " · "))
            }
            let timestamp = stringForTimestamp(timestamp: Int32(clamping: activity.timestamp / 1000))
            attr.append(NSAttributedString(string: timestamp))
        }
        detailsLabel.textColor = WTheme.secondaryLabel
        detailsLabel.attributedText = attr
    }
    
    struct ConfigureAmountOptions {
        var activity: ApiActivity
        var transactionToken: ApiToken?
        var baseCurrency: MBaseCurrency
        
        init(activity: ApiActivity, tokenStore: _TokenStore) {
            if case .transaction(let transaction) = activity {
                transactionToken = tokenStore[transaction.slug]
            }
            self.baseCurrency = tokenStore.baseCurrency
            self.activity = activity
        }
    }
        
    func configureAmount(_ options: ConfigureAmountOptions) {
        let activity = options.activity
        let displayMode = activity.amountDisplayMode

        switch activity {
        case .transaction(let transaction):
            if displayMode != .hide, let token = options.transactionToken {
                let amount = TokenAmount(transaction.amount, token)
                let color: UIColor = transaction.type == .stake ? .air.textPurple : transaction.isIncoming ? WTheme.positiveAmount : WTheme.primaryLabel
                let amountString = amount.formatAttributed(
                    format: .init(
                        preset: .defaultAdaptive,
                        showPlus: displayMode == .noSign ? false : true,
                        showMinus: displayMode == .noSign ? false : true,
                        roundUp: false
                    ),
                    integerFont: UIFont.systemFont(ofSize: 16),
                    fractionFont: UIFont.systemFont(ofSize: 16),
                    symbolFont: UIFont.systemFont(ofSize: 16),
                    integerColor: color,
                    fractionColor: color,
                    symbolColor: color
                )
                amountLabel.attributedText = amountString
                amountIcon1.config(with: token, shouldShowChain: false)
            } else {
                amountLabel.text = nil
                amountIcon1.config(with: nil, shouldShowChain: false)
            }
            
        case .swap(let swap):
            if let fromToken = swap.fromToken, let toToken = swap.toToken {
                let fromAmount = swap.fromAmount.value
                let toAmount = swap.toAmount.value
                let swapFailed = swap.status == .failed || swap.status == .expired
                let swapInProgress = swap.status == .pending
                let swapDone = swap.status == .completed || swap.status == .confirmed
                
                let attr = NSMutableAttributedString()
                
                let fromDecimalAmount = DecimalAmount.fromDouble(fromAmount, fromToken)
                let from = fromDecimalAmount.formatted(.compact, showMinus: false)
                attr.append(NSAttributedString(string: from, attributes: [
                    .foregroundColor: swapFailed ? WTheme.error : WTheme.secondaryLabel,
                ]))
                
                let image = swapDone ? UIImage.airBundle("ActivitySwapChevron")
                                     : UIImage.airBundle("ActivitySwapChevron").withRenderingMode(.alwaysTemplate)
                let chevron = NSTextAttachment(image: image)
                chevron.bounds = .init(x: 0, y: -2, width: 16, height: 16)
                let chevronString = NSMutableAttributedString(attachment: chevron)
                if !swapDone {
                    chevronString.addAttributes([
                        .foregroundColor: swapFailed ? WTheme.error : WTheme.secondaryLabel
                    ], range: NSRange(location: 0, length: chevronString.length))
                }
                attr.append(chevronString)
                
                let toDecimalAmount = DecimalAmount.fromDouble(toAmount, toToken)
                let to = toDecimalAmount.formatted(.compact, showMinus: false)
                attr.append(NSAttributedString(string: to, attributes: [
                    .foregroundColor: swapFailed ? WTheme.error : swapInProgress ? WTheme.secondaryLabel : WTheme.positiveAmount,
                ]))
                attr.addAttributes([
                    .font: ActivityCell.regular16Font
                ], range: NSRange(location: 0, length: attr.length))
                amountLabel.attributedText = attr
                
                amountIcon1.config(with: fromToken, shouldShowChain: false)
                amountIcon2.config(with: toToken, shouldShowChain: false)
            } else {
                amountLabel.attributedText = nil
                amountIcon1.config(with: nil, shouldShowChain: false)
                amountIcon2.config(with: nil, shouldShowChain: false)
            }
        }
        
        amountLabel.isHidden = displayMode == .hide
        amountIcon1.isHidden = displayMode == .hide
        amountIcon2.isHidden = displayMode != .swap
        if displayMode == .swap {
            NSLayoutConstraint.activate(amountIcon2Constraints)
        } else {
            NSLayoutConstraint.deactivate(amountIcon2Constraints)
        }
    }
        
    func configureAmount2(_ options: ConfigureAmountOptions) {
        let activity = options.activity
        
        amount2Label.font = .systemFont(ofSize: 14)
        amount2Label.textColor = WTheme.secondaryLabel
        
        let displayMode = activity.amountDisplayMode
        amount2Label.isHidden = displayMode == .hide
        
        switch activity {
        case .transaction(let transaction):
            if displayMode != .hide, let token = options.transactionToken, let price = token.price {
                let amount: BaseCurrencyAmount = TokenAmount(transaction.amount, token).convertTo(options.baseCurrency, exchangeRate: price)
                let color = WTheme.secondaryLabel
                let amountString = amount.formatAttributed(
                    format: .init(
                        preset: .compact,
                        showMinus: false,
                        roundUp: false
                    ),
                    integerFont: UIFont.systemFont(ofSize: 14),
                    fractionFont: UIFont.systemFont(ofSize: 14),
                    symbolFont: UIFont.systemFont(ofSize: 14),
                    integerColor: color,
                    fractionColor: color,
                    symbolColor: color
                )
                amount2Label.attributedText = amountString
                self.trackedValue = token.price
            } else {
                amount2Label.text = nil
                self.trackedValue = nil
            }
        case .swap(let swap):
            let fromAmount = swap.fromAmount.value
            let toAmount = swap.toAmount.value
            
            if let ex = ExchangeRateHelpers.getSwapRate(fromAmount: fromAmount, toAmount: toAmount, fromToken: swap.fromToken, toToken: swap.toToken) {
                
                let attr = NSMutableAttributedString()
                
                attr.append(NSAttributedString(string: "\(ex.toToken.symbol) ≈ ", attributes: [
                    .foregroundColor: WTheme.secondaryLabel,
                    .font: UIFont.systemFont(ofSize: 14, weight: .regular)
                ]))
                
                let exchangeAmount = TokenAmount.fromDouble(ex.price, ex.fromToken)
                let exchangeRateString = exchangeAmount.formatAttributed(
                    format: .init(
                        preset: .compact,
                        roundUp: true
                    ),
                    integerFont: .systemFont(ofSize: 14, weight: .semibold),
                    fractionFont: .systemFont(ofSize: 10, weight: .semibold),
                    symbolFont: .systemFont(ofSize: 10, weight: .semibold),
                    integerColor: WTheme.secondaryLabel,
                    fractionColor: WTheme.secondaryLabel,
                    symbolColor: WTheme.secondaryLabel
                )
                attr.append(exchangeRateString)
                
                amount2Label.attributedText = attr
            } else {
                amount2Label.attributedText = nil
            }
            self.trackedValue = nil
        }
    }
    
    func configureSensitiveData(activity: ApiActivity?) {
        if let activity, activity.amountDisplayMode != .hide {
            let amountCols = 4 + abs(activity.id.hash % 8)
            let fiatAmountCols = 5 + (amountCols % 6)
            amountContainer.setCols(amountCols)
            amount2Container.setCols(fiatAmountCols)
            if let tx = activity.transaction, tx.isIncoming, tx.amount > 0, tx.nft == nil {
                amountContainer.setTheme(.color(WTheme.positiveAmount))
            } else {
                amountContainer.setTheme(.adaptive)
            }
            amountContainer.isDisabled = false
            amount2Container.isDisabled = false
        } else {
            amountContainer.isDisabled = true
            amount2Container.isDisabled = true
        }
    }
    
    func configureNft(activity: ApiActivity?) {
        
        if activity?.isScamTransaction != true, let nft = activity?.transaction?.nft {
            nftView.setNft(nft)
            nftView.isHidden = false
            NSLayoutConstraint.activate(nftViewConstraints)
        } else {
            nftView.isHidden = true
            NSLayoutConstraint.deactivate(nftViewConstraints)
        }
    }
    
    func configureComment(activity: ApiActivity?) {
        
        let hasComment: Bool
        let shouldShowComment = activity?.shouldShowTransactionComment == true
        let isIncoming = activity?.transaction?.isIncoming == true
        
        if shouldShowComment, let tx = activity?.transaction, let commment = tx.comment?.nilIfEmpty {
            commentView.setComment(commment, direction: isIncoming ? .incoming : .outgoing, isError: tx.status == .failed)
            hasComment = true
        } else if shouldShowComment, let tx = activity?.transaction, tx.encryptedComment != nil {
            commentView.setEncryptedComment(direction: isIncoming ? .incoming : .outgoing, isError: tx.status == .failed)
            hasComment = true
        } else {
            hasComment = false
        }
        
        commentView.isHidden = !hasComment
        if hasComment {
            NSLayoutConstraint.activate(commentViewConstraints)
            commentViewLeadingConstraint.isActive = isIncoming
            commentViewTrailingConstraint.isActive = !isIncoming
        } else {
            NSLayoutConstraint.deactivate(commentViewConstraints)
        }
    }
    
    public override var isHighlighted: Bool {
        didSet {
            let color = isHighlighted ? WTheme.highlight : WTheme.groupedItem
            amountIcon1.setBorder(width: 1, color: color)
            amountIcon2.setBorder(width: 1, color: color)
        }
    }
}
