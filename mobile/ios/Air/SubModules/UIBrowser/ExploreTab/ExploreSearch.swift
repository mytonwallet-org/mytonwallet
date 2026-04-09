//
//  ExploreSearch.swift
//  MyTonWalletAir
//
//  Created by nikstar on 27.10.2025.
//

import Perception
import SwiftUI
import UIComponents
import UIKit
import WalletContext

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    ExploreSearch()
}
#endif

final class ExploreSearch: HostingView {
    let viewModel: ExploreSearchViewModel

    init() {
        let viewModel = ExploreSearchViewModel()
        self.viewModel = viewModel
        super.init(ignoreSafeArea: false) {
            ExploreSearchView(viewModel: viewModel)
        }
    }

    override func hitTest(_ point: CGPoint, with _: UIEvent?) -> UIView? {
        let point = convert(point, to: nil)
        if let frame = viewModel.frame, frame.contains(point) {
            return contentView
        }
        return nil
    }
}

@Perceptible
final class ExploreSearchViewModel {
    var string: String = ""
    var isActive: Bool = false

    @PerceptionIgnored
    var frame: CGRect?

    @PerceptionIgnored
    var onChange: (String) -> () = { _ in }

    @PerceptionIgnored
    var onSubmit: (String) -> () = { _ in }
}

struct ExploreSearchView: View {
    private enum Metrics {
        static let outerPadding: CGFloat = 16
    }

    let viewModel: ExploreSearchViewModel
    @FocusState private var isFocused
    @Namespace private var ns

    private var searchFieldPadding: EdgeInsets {
        EdgeInsets(top: viewModel.isActive ? 4 : 0,
                   leading: viewModel.isActive ? 16 : 12,
                   bottom: viewModel.isActive ? 4 : 0,
                   trailing: viewModel.isActive ? 20 : 16)
    }

    var body: some View {
        WithPerceptionTracking {
            HStack {
                searchField
            }
            .frame(maxWidth: .infinity, alignment: viewModel.isActive ? .leading : .center)
            .padding(Metrics.outerPadding)
            .onChange(of: isFocused) { isFocused in
                withAnimation(.smooth(duration: isFocused ? 0.25 : 0.2)) {
                    viewModel.isActive = isFocused
                }
            }
            .onChange(of: viewModel.string) { string in
                viewModel.onChange(string)
            }
            .onSubmit { viewModel.onSubmit(viewModel.string) }
        }
    }

    @ViewBuilder
    private var searchField: some View {
        let prompt = Text(lang("Search app or enter address"))
            .font(viewModel.isActive ? .system(size: 17, weight: .regular) : .system(size: 15, weight: .medium))
            .foregroundColor(viewModel.isActive ? .secondary : .air.primaryLabel)

        let searchFieldContent = HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(viewModel.isActive ? .secondary : Color.air.primaryLabel)
            TextField(
                text: Binding(
                    get: { viewModel.string },
                    set: { viewModel.string = $0 }
                ),
                prompt: prompt,
                label: { EmptyView() }
            )
                .fixedSize(horizontal: !viewModel.isActive, vertical: true)
                .focused($isFocused)
                .multilineTextAlignment(.leading)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .frame(height: 42)
        }
        .frame(maxWidth: viewModel.isActive ? .infinity : nil, alignment: .leading)
        .padding(searchFieldPadding)

        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            GlassEffectContainer {
                searchFieldContent
                    .glassEffect()
                    .glassEffectID("4", in: ns)
                    .geometryGroup()
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { viewModel.frame = $0 })
        } else {
            searchFieldContent
                .background(ExploreSearchMaterialBackground())
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { viewModel.frame = $0 })
        }
    }
}

private struct ExploreSearchMaterialBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> ExploreSearchMaterialBackgroundView {
        ExploreSearchMaterialBackgroundView()
    }

    func updateUIView(_ uiView: ExploreSearchMaterialBackgroundView, context: Context) {
        uiView.applyEffect()
    }
}

private final class ExploreSearchMaterialBackgroundView: UIView {
    private let effectView = UIVisualEffectView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        applyEffect()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyCornerStyle()
    }

    func applyEffect() {
        effectView.effect = UIBlurEffect(style: .systemMaterial)
        applyCornerStyle()
    }

    private func applyCornerStyle() {
        let radius = bounds.height / 2
        effectView.layer.cornerRadius = radius
        effectView.layer.cornerCurve = .continuous
        effectView.layer.masksToBounds = true
    }

    private func setupViews() {
        backgroundColor = .clear
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.backgroundColor = .clear
        effectView.contentView.backgroundColor = .clear
        addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
