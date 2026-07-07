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
        if viewModel.isActive,
           let frame = viewModel.clearButtonFrame,
           frame.contains(point) {
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
    var clearButtonFrame: CGRect?

    @PerceptionIgnored
    var onChange: (String) -> () = { _ in }

    @PerceptionIgnored
    var onSubmit: (String) -> () = { _ in }

    @PerceptionIgnored
    var onActiveChange: (Bool) -> () = { _ in }
}

private struct ExploreSearchView: View {
    private enum Metrics {
        static let outerPadding: CGFloat = 16
    }

    let viewModel: ExploreSearchViewModel
    @FocusState private var isFocused
    @Namespace private var ns

    private static let textFieldHeight: CGFloat = 42
    private static let activeVerticalPadding: CGFloat = 4

    private var searchFieldPadding: EdgeInsets {
        let v = viewModel.isActive ? Self.activeVerticalPadding : 0
        return EdgeInsets(top: v,
                          leading: viewModel.isActive ? 16 : 12,
                          bottom: v,
                          trailing: 16)
    }

    private var searchBarHeight: CGFloat {
        let v = viewModel.isActive ? Self.activeVerticalPadding : 0
        return Self.textFieldHeight + v * 2
    }

    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 6) {
                searchField
                if viewModel.isActive {
                    cancelButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.2), value: viewModel.isActive)
            .animation(.smooth(duration: 0.2), value: viewModel.string.isEmpty)
            .frame(maxWidth: .infinity, alignment: viewModel.isActive ? .leading : .center)
            .padding(Metrics.outerPadding)
            .onChange(of: isFocused) { _ in
                updateActiveState()
            }
            .onChange(of: viewModel.string) { string in
                viewModel.onChange(string)
                updateActiveState()
            }
            .onSubmit { viewModel.onSubmit(viewModel.string) }
        }
    }

    /// Search (active) mode transitions:
    /// - gaining focus enters search mode;
    /// - losing focus while the stripped input is empty exits it;
    /// - losing focus while the input is non-empty keeps search mode (e.g. keyboard dismissed by
    ///   scrolling results or switching tabs);
    /// - clearing the input while unfocused (cancel button / clear-after-submit) exits it.
    private func updateActiveState() {
        let isEmpty = viewModel.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let newActive: Bool
        if isFocused {
            newActive = true
        } else if isEmpty {
            newActive = false
        } else {
            newActive = viewModel.isActive
        }
        guard newActive != viewModel.isActive else { return }
        withAnimation(.smooth(duration: newActive ? 0.25 : 0.2)) {
            viewModel.isActive = newActive
        }
        viewModel.onActiveChange(newActive)
    }

    @ViewBuilder
    private var searchField: some View {
        WithPerceptionTracking {
            let isActive = viewModel.isActive
            let prompt = Text(lang("Search app or enter address"))
                .font(isActive ? .system(size: 17, weight: .regular) : .system(size: 15, weight: .medium))
                .foregroundColor(isActive ? .secondary : .air.primaryLabel)

            @Perception.Bindable var vm = viewModel
            
            let searchFieldContent = HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(isActive ? .secondary : Color.air.primaryLabel)
                TextField(
                    text: $vm.string,
                    prompt: prompt,
                    label: { EmptyView() }
                )
                    .fixedSize(horizontal: !isActive, vertical: true)
                    .lineLimit(1)
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textContentType(.init(rawValue: ""))
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .writingToolsDisabled()
                    .frame(height: 42)
                if !viewModel.string.isEmpty {
                    inlineClearButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: isActive ? .infinity : nil, alignment: .leading)
            .padding(searchFieldPadding)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { if !isFocused { isFocused = true } })

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

    @ViewBuilder
    private var cancelButton: some View {
        WithPerceptionTracking {
            let size = searchBarHeight
            let buttonContent = Button {
                viewModel.string = ""
                isFocused = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())

            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                GlassEffectContainer {
                    buttonContent
                        .glassEffect(.regular, in: .circle)
                        .glassEffectID("clear", in: ns)
                }
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { viewModel.clearButtonFrame = $0 })
            } else {
                buttonContent
                    .background(ExploreSearchMaterialBackground())
                    .clipShape(Circle())
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { viewModel.clearButtonFrame = $0 })
            }
        }
    }

    @ViewBuilder
    private var inlineClearButton: some View {
        WithPerceptionTracking {
            Button {
                viewModel.string = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .contentShape(Circle())
                    .padding(-10)
            }
            .buttonStyle(.plain)
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

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    ExploreSearch()
}
#endif
