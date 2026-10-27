import UIKit
import SwiftUI
import Dependencies
import Perception
import WalletCore
import WalletContext

/// Shared by UIKit and SwiftUI heroes. There is deliberately no touch-repulsion
/// API here: only the expanded card's play gesture can disturb its particles.
@MainActor
final class HeroParticlePrivacyEffect {
    let dust = CardSpoilerDustView(frame: .zero)
    let transition = CardElementTransition()
    private weak var target: UIView?
    weak var snapshotSource: UIView?
    var maskSize = CGSize(width: 132, height: 33)

    func install(in host: UIView, target: UIView) {
        self.target = target
        dust.settings = .hero
        transition.settings = .hero
        dust.animationActive = true
        transition.active = true
        host.addSubview(dust)
    }

    func layout(in host: UIView) {
        guard let target else { return }
        let center = target.convert(CGPoint(x: target.bounds.midX, y: target.bounds.midY), to: host)
        let field = CGRect(x: center.x - maskSize.width / 2, y: center.y - maskSize.height / 2,
                           width: maskSize.width, height: maskSize.height)
        dust.frame = host.bounds.union(field).insetBy(dx: -80, dy: -80)
        dust.fieldRect = dust.convert(field, from: host)
    }

    func update(hidden: Bool, color: UIColor, animated: Bool) {
        guard let target else { return }
        target.accessibilityElementsHidden = hidden
        dust.setColor(color)
        guard let snapshotSource else { return }
        transition.setConcealed(hidden, in: target, snapshotSource: snapshotSource, dust: dust, animated: animated)
    }

    func prepare(at point: CGPoint, in host: UIView) {
        guard let target else { return }
        transition.nextOrigin = target.convert(point, from: host)
    }

    func setActive(_ active: Bool) {
        dust.animationActive = active
        transition.active = active
    }

    func reset() { transition.reset(); dust.reset() }
}

@MainActor
final class HeroParticleHostingView: UIView {
    let effect = HeroParticlePrivacyEffect()
    private(set) var hosting: HostingView?
    private let revealButton = UIButton(type: .custom)
    var onReveal: (() -> Void)?
    private var concealed: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        revealButton.accessibilityLabel = lang("Tap to reveal")
        revealButton.addTarget(self, action: #selector(reveal(_:event:)), for: .touchUpInside)
        addSubview(revealButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func update<Content: View>(content: Content, hidden: Bool, color: UIColor) {
        let first = concealed == nil
        if let hosting {
            // Re-render before revealing so the latest amount, not a stale hidden
            // snapshot, is reconstructed. Numeric updates stay live when visible.
            if !hidden {
                hosting.contentView.configuration = UIHostingConfiguration { content }.margins(.all, 0)
            }
        } else {
            let hosting = HostingView { content }
            hosting.translatesAutoresizingMaskIntoConstraints = true
            insertSubview(hosting, at: 0)
            self.hosting = hosting
            effect.snapshotSource = hosting.contentView
            effect.install(in: self, target: hosting)
            bringSubviewToFront(revealButton)
        }
        concealed = hidden
        layoutIfNeeded()
        effect.layout(in: self)
        effect.update(hidden: hidden, color: color, animated: !first)
        revealButton.isHidden = !hidden
        invalidateIntrinsicContentSize()
    }

    func fittingSize(_ proposed: CGSize) -> CGSize {
        guard let content = hosting?.contentView else { return .zero }
        let natural = content.systemLayoutSizeFitting(proposed,
            withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .fittingSizeLevel)
        guard proposed.width > 0, natural.width > proposed.width else { return natural }
        return content.systemLayoutSizeFitting(proposed,
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hosting?.frame = bounds
        hosting?.layoutIfNeeded()
        revealButton.frame = bounds.union(CGRect(x: bounds.midX - effect.maskSize.width / 2,
            y: bounds.midY - effect.maskSize.height / 2, width: effect.maskSize.width, height: effect.maskSize.height))
        effect.layout(in: self)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        effect.setActive(window != nil)
    }
    @objc private func reveal(_ sender: UIButton, event: UIEvent?) {
        let point = event?.allTouches?.first?.location(in: self) ?? CGPoint(x: bounds.midX, y: bounds.midY)
        effect.prepare(at: point, in: self)
        onReveal?()
    }
}

private struct HeroParticleContent<Content: View>: UIViewRepresentable {
    var content: Content
    var hidden: Bool
    var color: UIColor
    var maskSize: CGSize
    var onReveal: () -> Void

    func makeUIView(context: Context) -> HeroParticleHostingView { HeroParticleHostingView(frame: .zero) }
    func updateUIView(_ view: HeroParticleHostingView, context: Context) {
        view.onReveal = onReveal
        view.effect.maskSize = maskSize
        view.update(content: content, hidden: hidden, color: color)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: HeroParticleHostingView, context: Context) -> CGSize? {
        let size = uiView.fittingSize(CGSize(width: proposal.width ?? UIView.layoutFittingExpandedSize.width,
                                           height: proposal.height ?? UIView.layoutFittingExpandedSize.height))
        // The whole fixed cloud remains tappable even for a one-digit amount.
        return CGSize(width: max(maskSize.width, size.width), height: max(maskSize.height, size.height))
    }
    static func dismantleUIView(_ uiView: HeroParticleHostingView, coordinator: ()) { uiView.effect.reset() }
}

private struct HeroSensitiveDataModifier: ViewModifier {
    var color: UIColor
    var maskSize: CGSize
    var isRevealed: Binding<Bool>?
    @Dependency(\.sensitiveData.isHidden) private var globallyHidden
    @State private var locallyRevealed = false

    private var revealed: Bool {
        get { isRevealed?.wrappedValue ?? locallyRevealed }
        nonmutating set {
            if let isRevealed {
                isRevealed.wrappedValue = newValue
            } else {
                locallyRevealed = newValue
            }
        }
    }

    func body(content: Content) -> some View {
        WithPerceptionTracking {
            HeroPrivacyLayout(concealed: globallyHidden && !revealed, maskWidth: maskSize.width) {
                // Retain the text's baseline and natural layout for the transition,
                // but reserve only the fixed mask width beside a token icon.
                content
                    .hidden()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .overlay {
                        HeroParticleContent(content: content, hidden: globallyHidden && !revealed,
                                            color: color, maskSize: maskSize) {
                            revealed = true
                        }
                    }
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateSensitiveData)) { _ in revealed = false }
            .onChange(of: globallyHidden) { _ in revealed = false }
            .task(id: revealed) {
                guard revealed, globallyHidden else { return }
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                revealed = false
            }
        }
    }
}

public extension View {
    func heroSensitiveData(color: UIColor = .label, maskSize: CGSize = CGSize(width: 132, height: 33), isRevealed: Binding<Bool>? = nil) -> some View {
        modifier(HeroSensitiveDataModifier(color: color, maskSize: maskSize, isRevealed: isRevealed))
    }
}

private struct HeroPrivacyLayout: Layout {
    var concealed: Bool
    var maskWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal)
        let line = subviews[0].dimensions(in: .unspecified)
        // Like a single-line Text, retain its font's line box when the glyphs
        // shrink horizontally. Shrinking the box too shifts AmountIconRow's icon.
        return CGSize(width: concealed ? maskWidth : size.width, height: concealed ? line.height : size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: proposal)
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        let dimensions = subviews[0].dimensions(in: .unspecified)
        return (bounds.height - dimensions.height) / 2 + dimensions[guide]
    }
}
