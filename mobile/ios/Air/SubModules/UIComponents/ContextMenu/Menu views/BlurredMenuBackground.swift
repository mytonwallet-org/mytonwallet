
import UIKit
import SwiftUI


public final class BlurredMenuBackground: UIView {
    
    let blur1: WBlurView = WBlurView()
    let blur2: UIVisualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular)) // .light might look better
    
    public init() {
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        addSubview(blur1)
        blur1.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blur1.topAnchor.constraint(equalTo: topAnchor),
            blur1.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur1.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur1.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        addSubview(blur2)
        blur2.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blur2.topAnchor.constraint(equalTo: topAnchor),
            blur2.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur2.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur2.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        blur2.backgroundColor = .airBundle("ContextMenuBlur")
    }
}
