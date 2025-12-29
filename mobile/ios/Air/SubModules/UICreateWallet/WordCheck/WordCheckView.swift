//
//  WordDisplayView.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.09.2025.
//

import SwiftUI
import WalletContext
import UIComponents
import Flow
import Perception

struct WordCheckView: View {
    
    var introModel: IntroModel
    var model: WordCheckModel
    
    @State private var isLoading = false

    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(spacing: 40) {
                    VStack(spacing: 20) {
                        WUIAnimatedSticker("animation_bill", size: 124, loop: false)
                            .frame(width: 124, height: 124)
                            .padding(.top, -8)
                        VStack(spacing: 20) {
                            title
                            description
                        }
                    }
                    grid
                        .opacity(model.hideAll ? 0 : 1)
                    if !isLoading {
                        error
                            .opacity(model.hideAll ? 0 : 1)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)).animation(.default))
                    } else {
                        Button(lang("Continue"), action: {})
                            .environment(\.isLoading, true)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)).animation(.default.delay(0.3)))
                            .buttonStyle(.airClearBackground)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .backportScrollBounceBehaviorBasedOnSize()
            .backportScrollClipDisabled()
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
            .allowsHitTesting(!model.interactionDisabled)
            .onChange(of: model.allSelected) { allSelected in
                if allSelected {
                    if !model.revealCorrect {
                        Task { @MainActor in
                            model.interactionDisabled = true
                            try? await Task.sleep(for: .seconds(0.5))
                            model.revealCorrect = true
                            try? await Task.sleep(for: .seconds(0.5))
                            model.interactionDisabled = false
                            if model.allCorrect {
                                isLoading = true
                                introModel.onCheckPassed()
                            } else {
                                withAnimation(.smooth(duration: 0.2)) {
                                    model.hideAll = true
                                }
                                try? await Task.sleep(for: .seconds(0.25))
                                model.resetKeepingIncorrect()
                                withAnimation(.smooth(duration: 1.50)) {
                                    model.hideAll = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    var title: some View {
        Text(langMd("Let's Check"))
            .multilineTextAlignment(.center)
            .font(.system(size: 32, weight: .semibold))
    }
    
    @ViewBuilder
    var description: some View {
        let ids = model.tests.map { String($0.id + 1) }
        let line1 = lang("$check_words_description").replacingOccurrences(of: "\n", with: " ")
        let line2 = lang("$mnemonic_check_words_list", arg1: ids.joined(separator: ", "))
        Text(LocalizedStringKey(line1 + "\n\n" + line2))
            .multilineTextAlignment(.center)
            .contentTransition(.numericText())
            .animation(.default, value: model.tests.map(\.id))
    }
    
    @ViewBuilder
    var grid: some View {
        @Perception.Bindable var model = model
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 24) {
            ForEach($model.tests) { $test in
                GridRow {
                    Text("\(test.id + 1).")
                        .foregroundColor(Color.air.secondaryLabel)
                    HFlow(spacing: 8) {
                        ForEach(test.words, id: \.self) { word in
                            let state: Item.State = test.selection != word ? .none : !model.revealCorrect ? .selected : word == test.correctWord.word ? .correct : .wrong
                            Item(
                                word: word,
                                state: state,
                                onTap: { test.selection = word }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 16, weight: .medium))
                }
            }
        }
        .animation(.spring, value: model.revealCorrect)
        .id(model.tests.map(\.words))
    }
    
    @ViewBuilder
    var error: some View {
        if model.showTryAgain {
            Text(lang("$mnemonic_check_error"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.red)
                .font(.system(size: 16, weight: .medium))
        }
    }
}


private struct Item: View {
    
    enum State {
        case none, selected, correct, wrong
    }
    
    var word: String
    var state: State
    var onTap: () -> ()
    
    @SwiftUI.State private var isTouching = false
    
    var textColor: Color {
        switch state {
        case .none: .air.primaryLabel
        case .selected: .blue
        case .correct: .green
        case .wrong: .red
        }
    }
    
    var borderColor: Color {
        switch state {
        case .none: .clear
        case .selected: .blue
        case .correct: .green
        case .wrong: .red
        }
    }
    
    var lineWidth: CGFloat {
        switch state {
        case .none:
            0
        default:
            1.667
        }
    }
    
    var body: some View {
        Text(verbatim: word)
            .foregroundStyle(textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                Color.air.groupedItem
            }
            .overlay {
                ContainerRelativeShape().strokeBorder(borderColor, lineWidth: lineWidth)
            }
            .clipShape(.rect(cornerRadius: 12))
            .containerShape(.rect(cornerRadius: 12))
            .onTapGesture {
                withAnimation(.spring) {
                    onTap()
                }
            }
            .highlightScale(isTouching, scale: 0.95, isEnabled: true)
            .touchGesture($isTouching)
    }
}
