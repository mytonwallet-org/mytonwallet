import SwiftUI
import UIKit
import WalletContext

private enum AgentHintsSectionMetrics {
    static let shadowRadius: CGFloat = 12
    static let shadowInset: CGFloat = -8
    static let gradientRotationDuration: TimeInterval = 12
    static let cardsInset = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
    static let cardSpacing: CGFloat = 12
    static let cardWidth: CGFloat = 300
    static let cardHeight: CGFloat = 66
    static let cardCornerRadius: CGFloat = 16
    static let cardBorderWidth: CGFloat = 1.5
    static let titleFont = UIFont.systemFont(ofSize: 15, weight: .bold)
    static let subtitleFont = UIFont.systemFont(ofSize: 15, weight: .regular)
    static let titleSubtitleSpacing: CGFloat = 0
    static let cardContentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)

    static func cardSize(for hint: AgentHint) -> CGSize {
        let titleWidth = hint.title.size(withAttributes: [.font: titleFont]).width
        let subtitleWidth = hint.subtitle.size(withAttributes: [.font: subtitleFont]).width
        let horizontalInsets = cardContentInsets.leading + cardContentInsets.trailing
        let width = min(cardWidth, ceil(max(titleWidth, subtitleWidth) + horizontalInsets))
        return CGSize(width: width, height: cardHeight)
    }
}

final class AgentHintsSectionView: UIView {
    private enum Section: Hashable {
        case main
    }

    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: AgentHintsSectionView.makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, AgentHint>!

    private var hints: [AgentHint] = []
    private var onHintTap: ((AgentHint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        updateShadowAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = CGPath(rect: bounds.insetBy(dx: 0, dy: AgentHintsSectionMetrics.shadowInset), transform: nil)
    }

    func configure(with hints: [AgentHint], onHintTap: @escaping (AgentHint) -> Void) {
        self.hints = hints
        self.onHintTap = onHintTap

        var snapshot = NSDiffableDataSourceSnapshot<Section, AgentHint>()
        snapshot.appendSections([.main])
        snapshot.appendItems(hints, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func setupViews() {
        backgroundColor = .clear
        clipsToBounds = false
        layer.shadowOpacity = 1
        layer.shadowRadius = AgentHintsSectionMetrics.shadowRadius
        dataSource = makeDataSource()

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.alwaysBounceVertical = false
        collectionView.decelerationRate = .fast
        collectionView.delegate = self
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateShadowAppearance()
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, AgentHint> {
        let hintRegistration = UICollectionView.CellRegistration<UICollectionViewCell, AgentHint> { cell, _, hint in
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    AgentHintCardContent(hint: hint, isHighlighted: state.isHighlighted)
                }
                .margins(.all, 0)
            }
        }

        return UICollectionViewDiffableDataSource<Section, AgentHint>(collectionView: collectionView) { collectionView, indexPath, hint in
            collectionView.dequeueConfiguredReusableCell(using: hintRegistration, for: indexPath, item: hint)
        }
    }

    private func updateShadowAppearance() {
        let backgroundColor = UIColor.air.background.resolvedColor(with: traitCollection)
        layer.shadowColor = backgroundColor.cgColor
    }

    private static func makeLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = AgentHintsSectionMetrics.cardSpacing
        layout.minimumInteritemSpacing = AgentHintsSectionMetrics.cardSpacing
        layout.sectionInset = UIEdgeInsets(
            top: AgentHintsSectionMetrics.cardsInset.top,
            left: AgentHintsSectionMetrics.cardsInset.leading,
            bottom: AgentHintsSectionMetrics.cardsInset.bottom,
            right: AgentHintsSectionMetrics.cardsInset.trailing
        )
        return layout
    }
}

extension AgentHintsSectionView: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard hints.indices.contains(indexPath.item) else { return }
        onHintTap?(hints[indexPath.item])
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard hints.indices.contains(indexPath.item) else {
            return CGSize(width: AgentHintsSectionMetrics.cardWidth, height: AgentHintsSectionMetrics.cardHeight)
        }
        return AgentHintsSectionMetrics.cardSize(for: hints[indexPath.item])
    }
}

private struct AgentHintCardContent: View {
    let hint: AgentHint
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AgentHintsSectionMetrics.titleSubtitleSpacing) {
            Text(hint.title)
                .font(Font(AgentHintsSectionMetrics.titleFont))
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(1)
                .truncationMode(.tail)

            Text(hint.subtitle)
                .font(Font(AgentHintsSectionMetrics.subtitleFont))
                .foregroundStyle(Color.air.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AgentHintsSectionMetrics.cardContentInsets.top)
        .padding(.leading, AgentHintsSectionMetrics.cardContentInsets.leading)
        .padding(.bottom, AgentHintsSectionMetrics.cardContentInsets.bottom)
        .padding(.trailing, AgentHintsSectionMetrics.cardContentInsets.trailing)
        .frame(height: AgentHintsSectionMetrics.cardHeight, alignment: .leading)
        .background {
            AgentHintAnimatedCardBackground()
        }
        .opacity(isHighlighted ? 0.82 : 1)
        .scaleEffect(isHighlighted ? 0.98 : 1)
        .animation(.smooth(duration: isHighlighted ? 0.12 : 0.18), value: isHighlighted)
    }
}

private struct AgentHintAnimatedCardBackground: View {
    var body: some View {
        TimelineView(.animation) { context in
            let rotationDegrees = AgentHintCardBackgroundStyle.rotationDegrees(at: context.date)
            let cardShape = RoundedRectangle(
                cornerRadius: AgentHintsSectionMetrics.cardCornerRadius,
                style: .continuous
            )

            cardShape
                .fill(AgentHintCardBackgroundStyle.baseFill)
                .overlay {
                    cardShape
                        .fill(AgentHintCardBackgroundStyle.backgroundGradient(rotatedBy: rotationDegrees))
                        .opacity(0.1)
                }
                .overlay {
                    cardShape
                        .strokeBorder(
                            AgentHintCardBackgroundStyle.borderGradient(rotatedBy: rotationDegrees),
                            lineWidth: AgentHintsSectionMetrics.cardBorderWidth
                        )
                }
        }
    }
}

private enum AgentHintCardBackgroundStyle {
    static let backgroundBaseAngleDegrees = 27.194
    static let backgroundEndpointRadius = 1.1

    static let baseFill = Color(
        uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                UIColor(
                    red: 35.0 / 255.0,
                    green: 39.0 / 255.0,
                    blue: 50.0 / 255.0,
                    alpha: 0.56
                )
            } else {
                UIColor(
                    red: 233.0 / 255.0,
                    green: 233.0 / 255.0,
                    blue: 234.0 / 255.0,
                    alpha: 0.16
                )
            }
        }
    )

    static let backgroundGradientStops = Gradient(stops: [
        .init(color: Color(.sRGB, red: 0, green: 136.0 / 255.0, blue: 1, opacity: 0.5), location: 0),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.5), location: 0.13),
        .init(color: Color(.sRGB, red: 182.0 / 255.0, green: 86.0 / 255.0, blue: 1, opacity: 0.2), location: 0.25),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.2), location: 0.375),
        .init(color: Color(.sRGB, red: 0, green: 136.0 / 255.0, blue: 1, opacity: 0.2), location: 0.5),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.5), location: 0.63),
        .init(color: Color(.sRGB, red: 182.0 / 255.0, green: 86.0 / 255.0, blue: 1, opacity: 0.2), location: 0.75),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.5), location: 0.88)
    ])

    static let borderGradientStops = Gradient(stops: [
        .init(color: Color(.sRGB, red: 0, green: 136.0 / 255.0, blue: 1, opacity: 1), location: 0),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.5), location: 0.13),
        .init(color: Color(.sRGB, red: 182.0 / 255.0, green: 86.0 / 255.0, blue: 1, opacity: 0.1), location: 0.25),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.1), location: 0.375),
        .init(color: Color(.sRGB, red: 0, green: 136.0 / 255.0, blue: 1, opacity: 0.1), location: 0.5),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.5), location: 0.63),
        .init(color: Color(.sRGB, red: 182.0 / 255.0, green: 86.0 / 255.0, blue: 1, opacity: 1), location: 0.75),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 1), location: 0.88),
        .init(color: Color(.sRGB, red: 0, green: 136.0 / 255.0, blue: 1, opacity: 1), location: 1)
    ])

    static func rotationDegrees(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: AgentHintsSectionMetrics.gradientRotationDuration)
        return elapsed / AgentHintsSectionMetrics.gradientRotationDuration * 360
    }

    static func backgroundGradient(rotatedBy degrees: Double) -> LinearGradient {
        let radians = (degrees + backgroundBaseAngleDegrees) * .pi / 180
        let dx = cos(radians) * backgroundEndpointRadius
        let dy = sin(radians) * backgroundEndpointRadius

        return LinearGradient(
            gradient: backgroundGradientStops,
            startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
            endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
        )
    }

    static func borderGradient(rotatedBy degrees: Double) -> AngularGradient {
        AngularGradient(
            gradient: borderGradientStops,
            center: .center,
            startAngle: .degrees(degrees),
            endAngle: .degrees(degrees + 360)
        )
    }
}

#if DEBUG
private enum AgentHintsSectionPreviewData {
    static let hints = [
        AgentHint(
            id: "preview-0",
            title: "Check the crypto market",
            subtitle: "including TON and major tokens",
            prompt: "Give me a quick crypto market overview."
        ),
        AgentHint(
            id: "preview-1",
            title: "Track my portfolio",
            subtitle: "with charts and token breakdown",
            prompt: "Analyze my wallet portfolio."
        ),
        AgentHint(
            id: "preview-2",
            title: "Show me staking options",
            subtitle: "for TON and MY rewards",
            prompt: "Explain staking in MyTonWallet."
        )
    ]
}

@available(iOS 18, *)
#Preview("Agent Prompts") {
    VStack(alignment: .leading, spacing: 20) {
        ScrollView(.horizontal) {
            HStack(spacing: AgentHintsSectionMetrics.cardSpacing) {
                ForEach(AgentHintsSectionPreviewData.hints, id: \.id) { hint in
                    AgentHintCardContent(hint: hint, isHighlighted: false)
                        .frame(width: AgentHintsSectionMetrics.cardSize(for: hint).width)
                }
            }
            .padding(.horizontal, AgentHintsSectionMetrics.cardsInset.leading)
        }
        .scrollIndicators(.hidden)

        AgentHintCardContent(
            hint: AgentHintsSectionPreviewData.hints[0],
            isHighlighted: true
        )
        .frame(width: AgentHintsSectionMetrics.cardSize(for: AgentHintsSectionPreviewData.hints[0]).width)
        .padding(.horizontal, AgentHintsSectionMetrics.cardsInset.leading)
    }
    .padding(.vertical, 24)
    .background(Color.air.background)
}
#endif
