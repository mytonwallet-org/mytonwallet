
import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception
import Dependencies
import UIKitNavigation

@Perceptible
class Container {
    var headerViewModel: HomeHeaderViewModel?
    var accountViewModel: AccountViewModel?
}

final class HomeCard: UICollectionViewCell {
    
    let container = Container()
    
    var cardBackground: UIView!
    var cardContentMaskingContainer: UIView!
    var cardContentMask: UIView!
    var cardContent: UIView!
    var collapsedContent: UIView!
    var miniatureContent: UIView!
    
    var observeToken: ObserveToken?
    
    override init(frame: CGRect) {
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup() {

//        backgroundColor = UIColor.red.withAlphaComponent(0.1)
        
        NSLayoutConstraint.activate([
            contentView.widthAnchor.constraint(equalToConstant: itemWidth),
            contentView.heightAnchor.constraint(equalToConstant: itemHeight).withPriority(.defaultHigh),
        ])
        
        collapsedContent = HostingView { [container] in
            CollapsedContentContainer(container: container)
        }
        contentView.addSubview(collapsedContent)
        NSLayoutConstraint.activate([
            collapsedContent.topAnchor.constraint(equalTo: contentView.topAnchor),
            collapsedContent.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collapsedContent.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collapsedContent.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        cardBackground = HostingView { [container] in
            BackgroundContainer(container: container)
        }
        contentView.addSubview(cardBackground)
        NSLayoutConstraint.activate([
            cardBackground.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        cardContentMaskingContainer = UIView()
        cardContentMaskingContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardContentMaskingContainer)
        NSLayoutConstraint.activate([
             cardContentMaskingContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
             cardContentMaskingContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
             cardContentMaskingContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
             cardContentMaskingContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        
        cardContentMask = UIView()
        cardContentMask.backgroundColor = .white
        cardContentMask.translatesAutoresizingMaskIntoConstraints = false
        cardContentMask.layer.cornerRadius = 26
        cardContentMask.layer.cornerCurve = .continuous
        cardContentMask.layer.masksToBounds = true

        cardContent = HostingView {
            CardContentContainer(container: container)
        }
        cardContentMaskingContainer.addSubview(cardContent)
        NSLayoutConstraint.activate([
            cardContent.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardContent.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardContent.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardContent.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        
        miniatureContent = HostingView {
            CardMiniatureContainer(container: container)
        }
        miniatureContent.isUserInteractionEnabled = false
        contentView.addSubview(miniatureContent)
        NSLayoutConstraint.activate([
            miniatureContent.topAnchor.constraint(equalTo: contentView.topAnchor),
            miniatureContent.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            miniatureContent.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            miniatureContent.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        
        cardContentMaskingContainer.mask = cardContentMask
//        cardBackground.alpha = 0.1
    }
    
    func configure(headerViewModel: HomeHeaderViewModel, accountViewModel: AccountViewModel) {
        self.container.headerViewModel = headerViewModel
        self.container.accountViewModel = accountViewModel
        cardContentMask.bounds = CGRect(x: 0, y: 0, width: itemWidth, height: itemHeight)
        cardContentMask.center = CGPoint(x: itemWidth/2, y: itemHeight/2)
        observeToken?.cancel()
        observeToken = observe { [weak self] in
            guard let self else { return }
            let isCollapsed = headerViewModel.isCollapsed
            UIView.animateAdaptive(duration: isCollapsed ? 0.3 : (IOS_26_MODE_ENABLED ? 0.4 : 0.3)) {
                self.applyTransform(headerViewModel: headerViewModel)
            }
            UIView.animate(withDuration: isCollapsed ? 0.25 : 0.05, delay: isCollapsed ? 0.1 : 0, options: isCollapsed ? [.curveEaseOut] : [.curveEaseIn]) {
                self.miniatureContent.alpha = isCollapsed ? 1 : 0
            }
        }
    }
    
    private func applyTransform(headerViewModel: HomeHeaderViewModel) {
        // background
        let ofs: CGFloat = itemHeight/2 - 17*CARD_RATIO + (IOS_26_MODE_ENABLED ? -114 : -116)
        let scale: CGFloat = 34/itemWidth
        // card content
        let r: CGFloat = homeCardFontSize/homeCollapsedFontSize
        let dx: CGFloat = 8
        let dy: CGFloat = 0.2667*itemHeight + (itemWidth > 400 ? 6 : 0) // TODO: this is not correct for all devices - there must be a fixed factor based on vertical size of content
        
        switch headerViewModel.state {
        case .expanded:
            self.cardBackground.transform = .identity
            self.cardContentMask.transform = .identity
            self.miniatureContent.transform = .identity
            self.cardContent.transform = .identity
            self.collapsedContent.transform = .identity
                .scaledBy(x: r, y: r)
                .translatedBy(x: -dx, y: -dy)
        case .collapsed:
            let t = CGAffineTransform.identity
                .translatedBy(x: 0, y: ofs)
                .scaledBy(x: scale, y: scale)
            self.cardBackground.transform = t
            self.cardContentMask.transform = t
            self.miniatureContent.transform = t
            self.cardContent.transform = .identity
                .translatedBy(x: dx, y: dy)
                .scaledBy(x: 1/r, y: 1/r)
            self.collapsedContent.transform = .identity
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        cardContentMask.bounds = CGRect(x: 0, y: 0, width: itemWidth, height: itemHeight)
        cardContentMask.center = CGPoint(x: itemWidth/2, y: itemHeight/2)
    }
}

private struct CollapsedContentContainer: View {
    var container: Container
    
    var body: some View {
        WithPerceptionTracking {
            if let headerViewModel = container.headerViewModel, let accountViewModel = container.accountViewModel {
                HomeHeaderCollapsedContent(headerViewModel: headerViewModel, accountViewModel: accountViewModel)
            }
        }
    }
}

private struct BackgroundContainer: View {
    
    var container: Container
    
    var body: some View {
        WithPerceptionTracking {
            if let headerViewModel = container.headerViewModel, let accountViewModel = container.accountViewModel {
                HomeCardBackground(headerViewModel: headerViewModel, accountViewModel: accountViewModel)
            }
        }
    }
}

private struct CardContentContainer: View {
    var container: Container
    
    var body: some View {
        WithPerceptionTracking {
            if let headerViewModel = container.headerViewModel, let accountViewModel = container.accountViewModel {
                HomeCardContent(headerViewModel: headerViewModel, accountViewModel: accountViewModel)
            }
        }
    }
}

private struct CardMiniatureContainer: View {
    var container: Container
    
    var body: some View {
        WithPerceptionTracking {
            if let headerViewModel = container.headerViewModel, let accountViewModel = container.accountViewModel {
                HomeCardMiniatureContent(headerViewModel: headerViewModel, accountViewModel: accountViewModel)
            }
        }
    }
}

#if DEBUG
@available(iOS 26, *)
#Preview(traits: .sizeThatFitsLayout) {
    let _ = UIFont.registerAirFonts()
    let headerViewModel = HomeHeaderViewModel(accountId: "0-mainnet")
    let accountViewModel = AccountViewModel(accountId: "0-mainnet")
    let cell = HomeCard()
//    let _ = cell.contentView.layer.borderColor = UIColor.red.cgColor
    let _ = cell.contentView.layer.borderWidth = 1
    let _ = cell.configure(headerViewModel: headerViewModel, accountViewModel: accountViewModel)
    let _ = cell.heightAnchor.constraint(equalToConstant: itemHeight).isActive = true
    let _ = cell.widthAnchor.constraint(equalToConstant: itemWidth).isActive = true
    cell
//    let _ = DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//        headerViewModel.state = .collapsed
//    }
//    let _ = DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
//        headerViewModel.state = .expanded
//    }
//    let _ = DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
//        headerViewModel.state = .collapsed
//    }
}
#endif

