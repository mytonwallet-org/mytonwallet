import UIKit
import SwiftUI
import ContextMenuKit

private final class DemoBackdropView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let orbLayers = (0 ..< 3).map { _ in CAShapeLayer() }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.gradientLayer.colors = [
            UIColor(red: 0.98, green: 0.99, blue: 1.0, alpha: 1.0).cgColor,
            UIColor(red: 0.92, green: 0.96, blue: 0.99, alpha: 1.0).cgColor,
            UIColor(red: 0.98, green: 0.94, blue: 0.9, alpha: 1.0).cgColor
        ]
        self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.gradientLayer)

        let orbColors = [
            UIColor(red: 0.29, green: 0.69, blue: 0.95, alpha: 0.18).cgColor,
            UIColor(red: 0.99, green: 0.63, blue: 0.34, alpha: 0.18).cgColor,
            UIColor(red: 0.33, green: 0.77, blue: 0.56, alpha: 0.14).cgColor
        ]
        for (index, orbLayer) in self.orbLayers.enumerated() {
            orbLayer.fillColor = orbColors[index]
            self.layer.addSublayer(orbLayer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.gradientLayer.frame = self.bounds
        let orbFrames = [
            CGRect(x: self.bounds.width * 0.58, y: 56.0, width: 220.0, height: 220.0),
            CGRect(x: -40.0, y: self.bounds.height * 0.34, width: 200.0, height: 200.0),
            CGRect(x: self.bounds.width * 0.45, y: self.bounds.height * 0.68, width: 260.0, height: 260.0)
        ]
        for (index, orbLayer) in self.orbLayers.enumerated() {
            orbLayer.path = UIBezierPath(ovalIn: orbFrames[index]).cgPath
        }
    }
}

private final class DemoBubbleView: UIView {
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let footerLabel = UILabel()
    private let alignment: NSLayoutConstraint.Attribute

    init(title: String, body: String, footer: String, alignment: NSLayoutConstraint.Attribute, fillColor: UIColor) {
        self.alignment = alignment

        super.init(frame: .zero)

        self.translatesAutoresizingMaskIntoConstraints = false
        self.layer.cornerRadius = 28.0
        self.layer.cornerCurve = .continuous
        self.backgroundColor = fillColor
        self.layer.borderWidth = 1.0 / max(self.traitCollection.displayScale, 1.0)
        self.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.titleLabel.textColor = UIColor.black.withAlphaComponent(0.54)
        self.titleLabel.text = title.uppercased()

        self.bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        self.bodyLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .regular)
        self.bodyLabel.numberOfLines = 0
        self.bodyLabel.textColor = UIColor.black.withAlphaComponent(0.92)
        self.bodyLabel.text = body

        self.footerLabel.translatesAutoresizingMaskIntoConstraints = false
        self.footerLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .regular)
        self.footerLabel.textColor = UIColor.black.withAlphaComponent(0.48)
        self.footerLabel.text = footer

        self.addSubview(self.titleLabel)
        self.addSubview(self.bodyLabel)
        self.addSubview(self.footerLabel)

        NSLayoutConstraint.activate([
            self.titleLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 16.0),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 18.0),
            self.titleLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -18.0),

            self.bodyLabel.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 6.0),
            self.bodyLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 18.0),
            self.bodyLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -18.0),

            self.footerLabel.topAnchor.constraint(equalTo: self.bodyLabel.bottomAnchor, constant: 12.0),
            self.footerLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 18.0),
            self.footerLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -18.0),
            self.footerLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -16.0),

            self.widthAnchor.constraint(lessThanOrEqualToConstant: 290.0)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class RootViewController: UIViewController {
    private enum MenuPreset {
        case baseline
        case portal
        case longPress
        case scrolling
        case customRows
    }

    private let backdropView = DemoBackdropView()
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let statusLabel = UILabel()
    private let blurSwitch = UISwitch()
    private let blurValueLabel = UILabel()
    private var swiftUIDemoController: UIHostingController<SwiftUIContextMenuDemoView>?
    private weak var swiftUIDemoContainerView: UIView?

    private let tapBubble = DemoBubbleView(
        title: "Tap Trigger",
        body: "Tap this bubble to open the baseline menu. It includes separators, destructive actions, and a submenu with nested actions.",
        footer: "This matches the same reusable menu stack used below.",
        alignment: .trailing,
        fillColor: UIColor(red: 0.93, green: 0.97, blue: 1.0, alpha: 0.88)
    )
    private let portalBubble = DemoBubbleView(
        title: "UIKit Portal",
        body: "This bubble uses portal-backed source rendering from a plain UIKit view. It is the direct comparison point for the SwiftUI portal source below.",
        footer: "Use this to verify there is only one crisp source copy above the blur.",
        alignment: .leading,
        fillColor: UIColor(red: 0.95, green: 0.94, blue: 1.0, alpha: 0.9)
    )
    private let holdBubble = DemoBubbleView(
        title: "Hold And Drag",
        body: "Long-press here, keep holding, and drag into the menu. The current item stays live while the menu scrolls.",
        footer: "This is the interaction path that matters most for parity.",
        alignment: .leading,
        fillColor: UIColor(red: 1.0, green: 0.96, blue: 0.87, alpha: 0.9)
    )
    private let scrollingBubble = DemoBubbleView(
        title: "Scrollable Submenu",
        body: "Open a long reactions list with enough rows to exercise clipping, auto-scroll, and the left-edge submenu pop gesture.",
        footer: "Use a swipe from the left edge inside the menu to go back.",
        alignment: .trailing,
        fillColor: UIColor(red: 0.9, green: 0.98, blue: 0.91, alpha: 0.9)
    )
    private let customRowsBubble = DemoBubbleView(
        title: "Custom Rows",
        body: "Open a menu with SwiftUI-hosted custom rows. The top options behave like whole-row selections, while the address rows keep their own buttons.",
        footer: "This mirrors the first real integration gap from the wallet app.",
        alignment: .leading,
        fillColor: UIColor(red: 0.96, green: 0.93, blue: 1.0, alpha: 0.9)
    )

    private var interactions: [ContextMenuInteraction] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = "Context Menu"
        self.view.backgroundColor = .systemBackground

        self.backdropView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.blurValueLabel.translatesAutoresizingMaskIntoConstraints = false

        self.stackView.axis = .vertical
        self.stackView.spacing = 16.0
        self.stackView.alignment = .fill

        self.statusLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        self.statusLabel.textColor = .secondaryLabel
        self.statusLabel.numberOfLines = 0
        self.statusLabel.text = "Open a menu from tap or long press. Toggle the backdrop blur and exercise the submenu stack."

        self.blurSwitch.isOn = true
        self.blurSwitch.addTarget(self, action: #selector(self.blurSwitchChanged), for: .valueChanged)

        self.blurValueLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        self.blurValueLabel.textColor = .secondaryLabel

        self.view.addSubview(self.backdropView)
        self.view.addSubview(self.scrollView)
        self.scrollView.addSubview(self.stackView)

        NSLayoutConstraint.activate([
            self.backdropView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.backdropView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.backdropView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.backdropView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),

            self.scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),

            self.stackView.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor, constant: 24.0),
            self.stackView.leadingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.leadingAnchor, constant: 16.0),
            self.stackView.trailingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.trailingAnchor, constant: -16.0),
            self.stackView.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor, constant: -32.0)
        ])

        self.buildDemoLayout()
        self.installInteractions()
        self.updateBlurLabel()
    }

    private func buildDemoLayout() {
        let titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: 32.0, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.text = "Reusable iOS 26 context menu harness"

        let subtitleLabel = UILabel()
        subtitleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = "This screen hosts the extracted menu component in isolation: tap presentation, long-press drag selection, scrollable content, and submenu navigation."

        let blurRow = UIStackView()
        blurRow.axis = .horizontal
        blurRow.alignment = .center
        blurRow.spacing = 12.0
        let blurTitleLabel = UILabel()
        blurTitleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .medium)
        blurTitleLabel.text = "Backdrop blur"
        blurRow.addArrangedSubview(blurTitleLabel)
        blurRow.addArrangedSubview(UIView())
        blurRow.addArrangedSubview(self.blurValueLabel)
        blurRow.addArrangedSubview(self.blurSwitch)

        let bubbleSection = UIStackView()
        bubbleSection.axis = .vertical
        bubbleSection.spacing = 14.0
        bubbleSection.alignment = .fill

        let tapRow = self.rowContainer(for: self.tapBubble, trailing: true)
        let portalRow = self.rowContainer(for: self.portalBubble, trailing: false)
        let holdRow = self.rowContainer(for: self.holdBubble, trailing: false)
        let scrollingRow = self.rowContainer(for: self.scrollingBubble, trailing: true)
        let customRowsRow = self.rowContainer(for: self.customRowsBubble, trailing: false)
        bubbleSection.addArrangedSubview(tapRow)
        bubbleSection.addArrangedSubview(portalRow)
        bubbleSection.addArrangedSubview(holdRow)
        bubbleSection.addArrangedSubview(scrollingRow)
        bubbleSection.addArrangedSubview(customRowsRow)

        let swiftUIDemoContainer = self.makeSwiftUIDemoContainer()

        [titleLabel, subtitleLabel, blurRow, self.statusLabel, bubbleSection, swiftUIDemoContainer].forEach {
            self.stackView.addArrangedSubview($0)
        }
    }

    private func rowContainer(for bubble: DemoBubbleView, trailing: Bool) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bubble)

        if trailing {
            NSLayoutConstraint.activate([
                bubble.topAnchor.constraint(equalTo: container.topAnchor),
                bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 52.0)
            ])
        } else {
            NSLayoutConstraint.activate([
                bubble.topAnchor.constraint(equalTo: container.topAnchor),
                bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -52.0)
            ])
        }

        return container
    }

    private func installInteractions() {
        let tapInteraction = ContextMenuInteraction(triggers: [.tap]) { [weak self] _ in
            self?.makeConfiguration(preset: .baseline) ?? ContextMenuConfiguration(rootPage: ContextMenuPage(items: []))
        }
        tapInteraction.attach(to: self.tapBubble)

        let portalInteraction = ContextMenuInteraction(
            triggers: [.tap, .longPress],
            sourcePortal: ContextMenuSourcePortal(
                mask: .roundedAttachmentRect(cornerRadius: 28.0, cornerCurve: .continuous)
            )
        ) { [weak self] _ in
            self?.makeConfiguration(preset: .portal) ?? ContextMenuConfiguration(rootPage: ContextMenuPage(items: []))
        }
        portalInteraction.attach(to: self.portalBubble)

        let holdInteraction = ContextMenuInteraction(triggers: [.longPress]) { [weak self] _ in
            self?.makeConfiguration(preset: .longPress) ?? ContextMenuConfiguration(rootPage: ContextMenuPage(items: []))
        }
        holdInteraction.attach(to: self.holdBubble)

        let scrollingInteraction = ContextMenuInteraction(triggers: [.tap, .longPress]) { [weak self] _ in
            self?.makeConfiguration(preset: .scrolling) ?? ContextMenuConfiguration(rootPage: ContextMenuPage(items: []))
        }
        scrollingInteraction.attach(to: self.scrollingBubble)

        let customRowsInteraction = ContextMenuInteraction(triggers: [.tap, .longPress]) { [weak self] _ in
            self?.makeConfiguration(preset: .customRows) ?? ContextMenuConfiguration(rootPage: ContextMenuPage(items: []))
        }
        customRowsInteraction.attach(to: self.customRowsBubble)

        self.interactions = [tapInteraction, portalInteraction, holdInteraction, scrollingInteraction, customRowsInteraction]
    }

    private func makeSwiftUIDemoContainer() -> UIView {
        let rootView = SwiftUIContextMenuDemoView(
            portalConfiguration: { [weak self] in
                self?.makeSwiftUIConfiguration(title: "SwiftUI portal source") ?? ContextMenuConfiguration(rootPage: ContextMenuPage(items: []))
            },
            plainConfiguration: { [weak self] in
                self?.makeSwiftUIConfiguration(title: "SwiftUI plain source") ?? ContextMenuConfiguration(rootPage: ContextMenuPage(items: []))
            },
            portalSourceViewProvider: { [weak self] in
                self?.swiftUIDemoContainerView
            }
        )
        let hostingController = UIHostingController(rootView: rootView)
        self.swiftUIDemoController = hostingController

        self.addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
        self.swiftUIDemoContainerView = containerView

        return containerView
    }

    private func makeConfiguration(preset: MenuPreset) -> ContextMenuConfiguration {
        let backdrop: ContextMenuBackdropStyle = self.blurSwitch.isOn ? .defaultBlurred() : .dimmed(alpha: 0.08)
        let rootPage: ContextMenuPage
        switch preset {
        case .baseline:
            rootPage = self.makeBaselinePage()
        case .portal:
            rootPage = self.makePortalPage()
        case .longPress:
            rootPage = self.makeLongPressPage()
        case .scrolling:
            rootPage = self.makeScrollingPage()
        case .customRows:
            rootPage = self.makeCustomRowsPage()
        }
        let style: ContextMenuStyle
        switch preset {
        case .customRows:
            style = ContextMenuStyle(minWidth: 250.0, maxWidth: 286.0)
        default:
            style = .default
        }
        return ContextMenuConfiguration(rootPage: rootPage, backdrop: backdrop, style: style)
    }

    private func makeSwiftUIConfiguration(title: String) -> ContextMenuConfiguration {
        let backdrop: ContextMenuBackdropStyle = self.blurSwitch.isOn ? .defaultBlurred() : .dimmed(alpha: 0.08)
        let rootPage = ContextMenuPage(items: [
            .action(ContextMenuAction(title: "Open details", subtitle: title, icon: .system("arrow.up.right.square"), handler: { [weak self] in
                self?.setStatus("\(title): Open details")
            })),
            .submenu(ContextMenuSubmenu(
                title: "Quick actions",
                subtitle: "SwiftUI-driven submenu",
                icon: .system("sparkles"),
                makePage: { [weak self] in
                    self?.makeSwiftUISubmenuPage(title: title) ?? ContextMenuPage(items: [])
                }
            )),
            .separator,
            .action(ContextMenuAction(title: "Pin source", icon: .system("pin"), dismissesMenu: false, handler: { [weak self] in
                self?.setStatus("\(title): Pin toggled")
            })),
            .action(ContextMenuAction(title: "Remove", icon: .system("trash"), role: .destructive, handler: { [weak self] in
                self?.setStatus("\(title): Remove")
            }))
        ])
        return ContextMenuConfiguration(rootPage: rootPage, backdrop: backdrop)
    }

    private func makeSwiftUISubmenuPage(title: String) -> ContextMenuPage {
        ContextMenuPage(items: [
            .back(ContextMenuBackAction(title: "Back")),
            .separator,
            .action(ContextMenuAction(title: "Share source", icon: .system("square.and.arrow.up"), handler: { [weak self] in
                self?.setStatus("\(title): Share source")
            })),
            .action(ContextMenuAction(title: "Copy identifier", icon: .system("doc.on.doc"), handler: { [weak self] in
                self?.setStatus("\(title): Copy identifier")
            })),
            .action(ContextMenuAction(title: "Inspect layout", icon: .system("viewfinder"), handler: { [weak self] in
                self?.setStatus("\(title): Inspect layout")
            }))
        ])
    }

    private func makeBaselinePage() -> ContextMenuPage {
        ContextMenuPage(items: [
            .submenu(ContextMenuSubmenu(
                title: "12/18 reacted",
                subtitle: "Readers and reactions",
                icon: .system("face.smiling"),
                makePage: { [weak self] in
                    self?.makeReactionBreakdownPage() ?? ContextMenuPage(items: [])
                }
            )),
            .separator,
            .action(ContextMenuAction(title: "Reply", icon: .system("arrowshape.turn.up.left"), handler: { [weak self] in
                self?.setStatus("Reply selected")
            })),
            .action(ContextMenuAction(title: "Edit", icon: .system("square.and.pencil"), handler: { [weak self] in
                self?.setStatus("Edit selected")
            })),
            .action(ContextMenuAction(title: "Forward", icon: .system("arrowshape.turn.up.right"), handler: { [weak self] in
                self?.setStatus("Forward selected")
            })),
            .submenu(ContextMenuSubmenu(
                title: "More",
                icon: .system("ellipsis.circle"),
                makePage: { [weak self] in
                    self?.makeMoreActionsPage() ?? ContextMenuPage(items: [])
                }
            )),
            .separator,
            .action(ContextMenuAction(
                title: "Delete",
                icon: .system("trash"),
                role: .destructive,
                handler: { [weak self] in
                    self?.setStatus("Delete selected")
                }
            ))
        ])
    }

    private func makePortalPage() -> ContextMenuPage {
        ContextMenuPage(items: [
            .action(ContextMenuAction(title: "Open details", subtitle: "UIKit portal source", icon: .system("arrow.up.right.square"), handler: { [weak self] in
                self?.setStatus("UIKit portal: Open details")
            })),
            .submenu(ContextMenuSubmenu(
                title: "Quick actions",
                subtitle: "Portal-backed source",
                icon: .system("sparkles"),
                makePage: { [weak self] in
                    self?.makeSwiftUISubmenuPage(title: "UIKit portal source") ?? ContextMenuPage(items: [])
                }
            )),
            .separator,
            .action(ContextMenuAction(title: "Pin source", icon: .system("pin"), dismissesMenu: false, handler: { [weak self] in
                self?.setStatus("UIKit portal: Pin toggled")
            })),
            .action(ContextMenuAction(title: "Remove", icon: .system("trash"), role: .destructive, handler: { [weak self] in
                self?.setStatus("UIKit portal: Remove")
            }))
        ])
    }

    private func makeLongPressPage() -> ContextMenuPage {
        ContextMenuPage(items: [
            .action(ContextMenuAction(title: "Quick Reply", subtitle: "Dismisses after release", icon: .system("text.bubble"), handler: { [weak self] in
                self?.setStatus("Quick Reply selected by drag")
            })),
            .action(ContextMenuAction(title: "Copy", subtitle: "Stays lightweight while dragging", icon: .system("doc.on.doc"), handler: { [weak self] in
                self?.setStatus("Copy selected by drag")
            })),
            .submenu(ContextMenuSubmenu(
                title: "View reactions",
                subtitle: "Opens without dismissing",
                icon: .system("hand.thumbsup"),
                makePage: { [weak self] in
                    self?.makeReactionBreakdownPage() ?? ContextMenuPage(items: [])
                }
            )),
            .separator,
            .action(ContextMenuAction(title: "Translate", icon: .system("globe"), handler: { [weak self] in
                self?.setStatus("Translate selected")
            })),
            .action(ContextMenuAction(title: "Pin", icon: .system("pin"), dismissesMenu: false, handler: { [weak self] in
                self?.setStatus("Pin toggled without dismissing")
            })),
            .action(ContextMenuAction(
                title: "Delete for everyone",
                icon: .system("trash"),
                role: .destructive,
                handler: { [weak self] in
                    self?.setStatus("Delete for everyone selected")
                }
            ))
        ])
    }

    private func makeScrollingPage() -> ContextMenuPage {
        ContextMenuPage(items: [
            .submenu(ContextMenuSubmenu(
                title: "42 readers",
                subtitle: "Scrollable with auto-scroll",
                icon: .system("person.2"),
                makePage: { [weak self] in
                    self?.makeReadersPage(count: 42) ?? ContextMenuPage(items: [])
                }
            )),
            .submenu(ContextMenuSubmenu(
                title: "12 reactions",
                subtitle: "Nested submenu with a second level",
                icon: .system("heart.text.square"),
                makePage: { [weak self] in
                    self?.makeReactionBreakdownPage() ?? ContextMenuPage(items: [])
                }
            )),
            .separator,
            .action(ContextMenuAction(title: "Mute", icon: .system("bell.slash"), handler: { [weak self] in
                self?.setStatus("Mute selected")
            })),
            .action(ContextMenuAction(title: "Archive", icon: .system("archivebox"), handler: { [weak self] in
                self?.setStatus("Archive selected")
            }))
        ])
    }

    private func makeCustomRowsPage() -> ContextMenuPage {
        ContextMenuPage(items: [
            .custom(
                .swiftUI(
                    sizing: .fixed(height: 58.0),
                    interaction: .selectable(handler: { [weak self] in
                        self?.setStatus("Base currency changed to USD")
                    })
                ) { _ in
                    DemoCurrencyMenuRow(
                        title: "USD",
                        subtitle: "$14,480.12",
                        isSelected: true
                    )
                }
            ),
            .custom(
                .swiftUI(
                    sizing: .fixed(height: 58.0),
                    interaction: .selectable(handler: { [weak self] in
                        self?.setStatus("Base currency changed to EUR")
                    })
                ) { _ in
                    DemoCurrencyMenuRow(
                        title: "EUR",
                        subtitle: "EUR 13,412.05",
                        isSelected: false
                    )
                }
            ),
            .custom(
                .swiftUI(
                    sizing: .fixed(height: 58.0),
                    interaction: .selectable(handler: { [weak self] in
                        self?.setStatus("Base currency changed to GBP")
                    })
                ) { _ in
                    DemoCurrencyMenuRow(
                        title: "GBP",
                        subtitle: "GBP 11,504.88",
                        isSelected: false
                    )
                }
            ),
            .separator,
            .custom(
                .swiftUI(
                    sizing: .fixed(height: 60.0)
                ) { [weak self] context in
                    DemoAddressMenuRow(
                        title: "wallet.ton",
                        subtitle: "UQBx...4nKQ · TON",
                        onCopy: {
                            self?.setStatus("TON address copied")
                            context.dismiss()
                        },
                        onOpenExplorer: {
                            self?.setStatus("TON explorer opened")
                            context.dismiss()
                        }
                    )
                }
            ),
            .custom(
                .swiftUI(
                    sizing: .fixed(height: 60.0)
                ) { [weak self] context in
                    DemoAddressMenuRow(
                        title: "0xD3A4...7a11",
                        subtitle: "Ethereum",
                        onCopy: {
                            self?.setStatus("ETH address copied")
                            context.dismiss()
                        },
                        onOpenExplorer: {
                            self?.setStatus("ETH explorer opened")
                            context.dismiss()
                        }
                    )
                }
            ),
            .separator,
            .action(ContextMenuAction(title: "Share Wallet Link", icon: .system("square.and.arrow.up"), handler: { [weak self] in
                self?.setStatus("Wallet link shared")
            }))
        ])
    }

    private func makeReactionBreakdownPage() -> ContextMenuPage {
        ContextMenuPage(items: [
            .back(ContextMenuBackAction(title: "Back")),
            .separator,
            .action(ContextMenuAction(title: "Anna Petrova", subtitle: "Read 2m ago", icon: .system("heart.fill"), handler: { [weak self] in
                self?.setStatus("Anna selected")
            })),
            .action(ContextMenuAction(title: "Ilya Kuznetsov", subtitle: "Read 3m ago", icon: .system("heart.fill"), handler: { [weak self] in
                self?.setStatus("Ilya selected")
            })),
            .action(ContextMenuAction(title: "Marta Volnova", subtitle: "Reacted with 😂", icon: .system("face.smiling.inverse"), handler: { [weak self] in
                self?.setStatus("Marta selected")
            })),
            .action(ContextMenuAction(title: "Noah Levin", subtitle: "Reacted with 🔥", icon: .system("flame.fill"), handler: { [weak self] in
                self?.setStatus("Noah selected")
            })),
            .separator,
            .submenu(ContextMenuSubmenu(
                title: "All readers",
                subtitle: "Open a long scrollable list",
                icon: .system("list.bullet.rectangle"),
                makePage: { [weak self] in
                    self?.makeReadersPage(count: 42) ?? ContextMenuPage(items: [])
                }
            ))
        ])
    }

    private func makeMoreActionsPage() -> ContextMenuPage {
        ContextMenuPage(items: [
            .back(ContextMenuBackAction(title: "Back")),
            .separator,
            .action(ContextMenuAction(title: "Select", icon: .system("checkmark.circle"), handler: { [weak self] in
                self?.setStatus("Select selected")
            })),
            .action(ContextMenuAction(title: "Show in Folder", icon: .system("folder"), handler: { [weak self] in
                self?.setStatus("Show in Folder selected")
            })),
            .submenu(ContextMenuSubmenu(
                title: "Share",
                subtitle: "One level deeper",
                icon: .system("square.and.arrow.up"),
                makePage: { [weak self] in
                    self?.makeShareTargetsPage() ?? ContextMenuPage(items: [])
                }
            ))
        ])
    }

    private func makeShareTargetsPage() -> ContextMenuPage {
        ContextMenuPage(items: [
            .back(ContextMenuBackAction(title: "Back")),
            .separator,
            .action(ContextMenuAction(title: "Saved Messages", icon: .system("bookmark"), handler: { [weak self] in
                self?.setStatus("Shared to Saved Messages")
            })),
            .action(ContextMenuAction(title: "Notes", icon: .system("note.text"), handler: { [weak self] in
                self?.setStatus("Shared to Notes")
            })),
            .action(ContextMenuAction(title: "Files", icon: .system("folder.badge.plus"), handler: { [weak self] in
                self?.setStatus("Shared to Files")
            }))
        ])
    }

    private func makeReadersPage(count: Int) -> ContextMenuPage {
        let names = [
            "Anna Petrova", "Ilya Kuznetsov", "Marta Volnova", "Noah Levin", "Sasha Gray",
            "Lena Korotkova", "Daniel Fox", "Polina Sergeeva", "Iris Novak", "Maksim Belov",
            "Eva Mendez", "Tanya Smirnova", "Leo Martin", "Daria Vetrova", "Kirill Orlov",
            "Ava Miller", "Roman Petrov", "Mina Sokolova", "Denis Volk", "Elena Mironova",
            "Artem Denisov", "Alex Rivera", "Liza White", "Nikita Frolov", "Sonia Black",
            "Dmitry Kozlov", "Oleg Trofimov", "Nora Stone", "Vera Bessonova", "Anton Kiselev",
            "Maya Green", "Fedor Andreev", "Yana Romanova", "Tim Hall", "Olga Petrenko",
            "Stepan Larin", "Mira Costa", "Vlad Sorokin", "Nina Curtis", "Andrey Smolin",
            "Mila Fisher", "Pavel Nikitin"
        ]

        let readerItems: [ContextMenuItem] = names.prefix(count).enumerated().map { index, name in
            let minute = 2 + (index % 9)
            return .action(ContextMenuAction(
                title: name,
                subtitle: "Read \(minute)m ago",
                icon: .system(index.isMultiple(of: 3) ? "eye.fill" : "person.crop.circle"),
                handler: { [weak self] in
                    self?.setStatus("\(name) selected")
                }
            ))
        }

        let items: [ContextMenuItem] = [
            .back(ContextMenuBackAction(title: "Back")),
            .separator
        ] + readerItems

        return ContextMenuPage(items: items)
    }

    @objc private func blurSwitchChanged() {
        self.updateBlurLabel()
    }

    private func updateBlurLabel() {
        self.blurValueLabel.text = self.blurSwitch.isOn ? "On" : "Dim only"
    }

    private func setStatus(_ text: String) {
        self.statusLabel.text = "Last action: \(text)"
    }
}

private struct DemoCurrencyMenuRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0.0) {
            VStack(alignment: .leading, spacing: 2.0) {
                Text(title)
                    .font(.system(size: 17.0, weight: .regular))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 15.0, weight: .regular))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "checkmark")
                .font(.system(size: 15.0, weight: .semibold))
                .foregroundStyle(Color(uiColor: .tintColor))
                .opacity(isSelected ? 1.0 : 0.0)
                .frame(width: 18.0)
        }
        .foregroundStyle(Color(uiColor: .label))
        .padding(.horizontal, 16.0)
        .padding(.vertical, 10.0)
    }
}

private struct DemoAddressMenuRow: View {
    let title: String
    let subtitle: String
    let onCopy: () -> Void
    let onOpenExplorer: () -> Void

    var body: some View {
        HStack(spacing: 10.0) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.31, green: 0.66, blue: 0.95),
                            Color(red: 0.18, green: 0.46, blue: 0.86)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28.0, height: 28.0)
                .overlay(
                    Image(systemName: "link")
                        .font(.system(size: 13.0, weight: .semibold))
                        .foregroundStyle(.white)
                )

            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 2.0) {
                    HStack(spacing: 5.0) {
                        Text(title)
                            .font(.system(size: 17.0, weight: .regular))
                            .foregroundStyle(Color(uiColor: .label))
                            .lineLimit(1)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14.0, weight: .medium))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    .frame(height: 20.0)

                    Text(subtitle)
                        .font(.system(size: 13.0, weight: .regular))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .frame(height: 18.0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onOpenExplorer) {
                Image(systemName: "globe")
                    .font(.system(size: 16.0, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .tintColor))
                    .padding(10.0)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16.0)
        .padding(.vertical, 10.0)
    }
}
