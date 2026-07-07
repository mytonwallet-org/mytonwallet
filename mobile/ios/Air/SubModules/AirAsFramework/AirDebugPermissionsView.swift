import SwiftUI
import UIKit
import UIComponents
import UISettings
import WalletContext
import WalletCore

@MainActor
public struct AirDebugPermissionsView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        PermissionsNavigationHost(onBack: { dismiss() })
            .ignoresSafeArea()
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
    }
}

@MainActor
private struct PermissionsNavigationHost: UIViewControllerRepresentable {
    let onBack: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBack: onBack)
    }

    func makeUIViewController(context: Context) -> WNavigationController {
        let permissionsVC = PermissionsVC(accountContext: AccountContext(source: .current))
        permissionsVC.navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.goBack)
        )

        return WNavigationController(rootViewController: permissionsVC)
    }

    func updateUIViewController(_ uiViewController: WNavigationController, context: Context) {
        context.coordinator.onBack = onBack
    }

    final class Coordinator: NSObject {
        var onBack: () -> Void

        init(onBack: @escaping () -> Void) {
            self.onBack = onBack
        }

        @objc func goBack() {
            onBack()
        }
    }
}
