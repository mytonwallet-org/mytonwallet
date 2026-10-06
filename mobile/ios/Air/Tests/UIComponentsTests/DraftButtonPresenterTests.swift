import Testing
import UIKit
import WalletResources
@testable import UIComponents

@Suite("Draft Button Presenter")
@MainActor
struct DraftButtonPresenterTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test
    func `first load uses primary appearance without allowing activation`() {
        let button = WButton()
        button.isEnabled = false
        let presenter = DraftButtonPresenter(button: button)
        presenter.apply(loading)

        #expect(button.isEnabled)
        #expect(!button.isUserInteractionEnabled)
        #expect(button.accessibilityTraits.contains(.notEnabled))
        #expect(button.showLoading)
    }

    @Test
    func `empty input clears appearance history for the next load`() {
        let button = WButton()
        let presenter = DraftButtonPresenter(button: button)
        presenter.apply(.init(title: .text("Insufficient Balance"), isEnabled: false, showLoading: false))
        presenter.apply(.init(title: .text("Continue"), isEnabled: false, showLoading: false, resetsLoadingAppearance: true))
        #expect(!button.isEnabled)
        #expect(!button.isUserInteractionEnabled)

        presenter.apply(loading)
        #expect(button.isEnabled)
        #expect(button.showLoading)
        #expect(!button.isUserInteractionEnabled)
        #expect(button.accessibilityTraits.contains(.notEnabled))
    }

    @Test
    func `replacement stays visually enabled for the whole load but cannot be activated`() async throws {
        let button = WButton()
        let presenter = DraftButtonPresenter(button: button)
        presenter.apply(ready)
        presenter.apply(loading)

        #expect(button.isEnabled)
        #expect(!button.isUserInteractionEnabled)
        #expect(button.accessibilityTraits.contains(.notEnabled))
        #expect(button.showLoading)
        #expect(button.title(for: .normal) == "Continue")

        // Outlive the old one-second dimming timer.
        try await Task.sleep(for: .milliseconds(1_100))
        #expect(button.isEnabled)
        #expect(!button.isUserInteractionEnabled)
    }

    @Test
    func `definitive failure ends optimism immediately and a new load cannot restore it`() {
        let button = WButton()
        let presenter = DraftButtonPresenter(button: button)
        presenter.apply(ready)
        presenter.apply(loading)
        presenter.apply(.init(title: .text("Insufficient Balance"), isEnabled: false, showLoading: false))

        #expect(!button.isEnabled)
        #expect(!button.showLoading)
        #expect(button.title(for: .normal) == "Insufficient Balance")

        presenter.apply(loading)
        #expect(!button.isEnabled)
        #expect(!button.isUserInteractionEnabled)
    }

    @Test
    func `matching draft restores interaction and clears loading and disabled accessibility`() {
        let button = WButton()
        let presenter = DraftButtonPresenter(button: button)
        presenter.apply(ready)
        presenter.apply(loading)
        presenter.apply(ready)

        #expect(button.isEnabled)
        #expect(button.isUserInteractionEnabled)
        #expect(!button.accessibilityTraits.contains(.notEnabled))
        #expect(!button.showLoading)
    }

    @Test
    func `unchanged state reasserts interaction after visibility changes`() {
        let button = WButton()
        let presenter = DraftButtonPresenter(button: button)
        presenter.apply(ready)
        presenter.apply(loading)
        button.isUserInteractionEnabled = true
        presenter.apply(loading)

        #expect(!button.isUserInteractionEnabled)
        #expect(button.isEnabled)
    }

    @Test
    func `an error replaces an attributed swap title immediately`() {
        let button = WButton()
        let presenter = DraftButtonPresenter(button: button)
        presenter.apply(.init(title: .attributed(NSAttributedString(string: "Swap GRAM to TON"), identity: "swap"),
                              isEnabled: true, showLoading: false))
        presenter.apply(.init(title: .text("Invalid pair"), isEnabled: false, showLoading: false))

        #expect(button.attributedTitle(for: .normal) == nil)
        #expect(button.title(for: .normal) == "Invalid pair")
        #expect(!button.isEnabled)
    }
}

@MainActor private let ready = DraftButtonConfiguration(title: .text("Continue"), isEnabled: true, showLoading: false)
@MainActor private let loading = DraftButtonConfiguration(title: .text("Continue"), isEnabled: false, showLoading: true)
