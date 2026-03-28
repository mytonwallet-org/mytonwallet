import UIKit
import WalletContext

final class AgentScrollToBottomButton: UIButton {
    private var isButtonVisible = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "chevron.down")
        configuration.baseForegroundColor = UIColor.label
        configuration.background.backgroundColor = .air.groupedItem
        configuration.background.cornerRadius = 22
        self.configuration = configuration

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    func setVisible(_ isVisible: Bool, animated: Bool) {
        guard isVisible != isButtonVisible else { return }
        isButtonVisible = isVisible

        let changes = {
            self.alpha = isVisible ? 1 : 0
            self.transform = isVisible ? .identity : CGAffineTransform(scaleX: 0.85, y: 0.85)
        }

        if animated {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: changes
            )
        } else {
            changes()
        }
    }

    private func setupViews() {
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        accessibilityLabel = "Scroll to latest messages"
    }
}
