//
//  AppearanceVC.swift
//  UISettings
//
//  Created by Sina on 6/29/24.
//

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext

private let log = Log("AppearanceVC")

public class AppearanceVC: WViewController {
    
    // MARK: - View Model and UI Components
    private lazy var switchToClassic = HostingView {
        InsetSection {
            InsetButtonCell(alignment: .center) {
                log.info("switchToCapacitor")
                WalletContextManager.delegate?.switchToCapacitor()
            } label: {
                Text(lang("Switch to Legacy Version"))
                    .padding(.vertical, 1)
            }
        }
        .padding(.top, 24)
    }
    
    private lazy var colorThemeView: AppearanceColorThemeView = {
        let v = AppearanceColorThemeView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private var appThemeView: AppearanceAppThemeView = {
        let v = AppearanceAppThemeView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private var appIconView: AppearanceAppIconView = {
        let v = AppearanceAppIconView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private var otherSettingsView: AppearanceOtherSettingsView = {
        let v = AppearanceOtherSettingsView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var arrangedContentView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.addArrangedSubview(switchToClassic)
//        stackView.addArrangedSubview(colorThemeView, spacing: 18)
        stackView.addArrangedSubview(appThemeView, spacing: 33)
//        stackView.addArrangedSubview(appIconView, spacing: 28)
        stackView.addArrangedSubview(otherSettingsView, spacing: 28)
        return stackView
    }()
    
    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.addSubview(arrangedContentView)
        sv.alwaysBounceVertical = true
        sv.delegate = self
        NSLayoutConstraint.activate([
            arrangedContentView.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor),
            arrangedContentView.leftAnchor.constraint(equalTo: sv.contentLayoutGuide.leftAnchor),
            arrangedContentView.rightAnchor.constraint(equalTo: sv.contentLayoutGuide.rightAnchor),
            arrangedContentView.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor, constant: -16),
            arrangedContentView.widthAnchor.constraint(equalTo: sv.widthAnchor)
        ])
        return sv
    }()
    
    // MARK: - Load and SetupView Functions
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    private func setupViews() {
        title = lang("Appearance")

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leftAnchor.constraint(equalTo: view.leftAnchor),
            scrollView.rightAnchor.constraint(equalTo: view.rightAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        addNavigationBar(
            navHeight: 40,
            topOffset: -5,
            title: title,
            addBackButton: { [weak self] in
                guard let self else {return}
                navigationController?.popViewController(animated: true)
            })
        scrollView.contentInset.top = navigationBarHeight
        scrollView.verticalScrollIndicatorInsets.top += navigationBarHeight
        scrollView.contentOffset.y = -navigationBarHeight
        
        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.groupedBackground
    }

    public override func scrollToTop(animated: Bool) {
        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: animated)
    }
}

extension AppearanceVC: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        navigationBar?.showSeparator = scrollView.contentOffset.y + scrollView.contentInset.top + view.safeAreaInsets.top > 0
    }
}
