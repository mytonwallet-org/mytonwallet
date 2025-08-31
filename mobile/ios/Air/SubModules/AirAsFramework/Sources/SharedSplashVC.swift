
import UIKit

public final class SharedSplashVC: UIViewController {

    private var splashImageView = UIImageView(image: UIImage(named: "Splash"))
    
    public init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }

    private func setupViews() {
        splashImageView.contentMode = .scaleAspectFill
        
        splashImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splashImageView)
        NSLayoutConstraint.activate([
            splashImageView.topAnchor.constraint(equalTo: view.topAnchor),
            splashImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            splashImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splashImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}
