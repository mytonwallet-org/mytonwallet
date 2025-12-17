//
//  ExploreSearch.swift
//  MyTonWalletAir
//
//  Created by nikstar on 27.10.2025.
//

import SwiftUI
import UIKit
import UIComponents
import WalletContext

final class ExploreSearch: HostingView {
    
    let viewModel: ExploreSearchViewModel
    
    init() {
        let viewModel = ExploreSearchViewModel()
        self.viewModel = viewModel
        super.init(ignoreSafeArea: false) {
            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                ExploreSearchView(viewModel: viewModel)
            }
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let point = convert(point, to: nil)
        if let frame = viewModel.frame, frame.contains(point) {
            return contentView
        }
        return nil
    }
}

final class ExploreSearchViewModel: ObservableObject {
    @Published var string: String = ""
    @Published var isActive: Bool = false
    var frame: CGRect?
    
    var onChange: (String) -> () = { _ in }
    var onSubmit: (String) -> () = { _ in }
}

@available(iOS 26, *)
struct ExploreSearchView: View {
    
    @ObservedObject var viewModel: ExploreSearchViewModel
    @FocusState private var isFocused
    @Namespace private var ns
    
    var body: some View {
        searchBar
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: 80, alignment: .bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    
    var searchBar: some View {
        GlassEffectContainer {
            let glass = Image(systemName: "magnifyingglass")
            HStack {
                HStack {
                    glass
                    TextField(text: $viewModel.string, prompt: Text(lang("Search app or enter address")).foregroundStyle(viewModel.isActive ? .secondary : Color(WTheme.primaryLabel)), label: { EmptyView() })
                        .fixedSize(horizontal: !viewModel.isActive, vertical: true)
                        .focused($isFocused)
                        .multilineTextAlignment(.leading)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.webSearch)
                        .submitLabel(.go)
                }
                .font(viewModel.isActive ? .system(size: 17, weight: .regular) : .system(size: 15, weight: .medium))
                .padding(.all, viewModel.isActive ? 16 : 12)
                .padding(.trailing, 4)
                .glassEffect()
                .glassEffectID("4", in: ns)
                .contentShape(.rect)
                .scrollDismissesKeyboard(.immediately)
            }
            .padding()
            .geometryGroup()
            .scrollDismissesKeyboard(.immediately)

        }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: isFocused) { isFocused in
            withAnimation(.smooth(duration: isFocused ? 0.25 : 0.2)) {
                viewModel.isActive = isFocused
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { viewModel.frame = $0 })
        .onChange(of: viewModel.string) { _, string in
            viewModel.onChange(string)
        }
        .onSubmit {
            viewModel.onSubmit(viewModel.string)
        }
    }
}
