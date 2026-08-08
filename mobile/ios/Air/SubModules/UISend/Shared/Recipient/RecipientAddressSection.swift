
import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Perception
import SwiftNavigation

struct RecipientAddressSection: View {
    
    var model: SendRecipientModel
    var validationState: SendRecipientValidationState? = nil
    var onPasteAction: (() -> Bool)? = nil
    
    var body: some View {
        @Perception.Bindable var model = model
        WithPerceptionTracking {
            InsetSection {
                InsetCell {
                    Cell(model: model, onPasteAction: onPasteAction)
                }
                .contentShape(.rect)
                .onTapGesture {
                    model.isFocused = true
                }
                .overlay {
                    if validationState != nil {
                        RoundedRectangle(
                            cornerRadius: S.insetSectionCornerRadius,
                            style: .continuous
                        )
                        .strokeBorder(Color.air.error, lineWidth: 1.5)
                        .allowsHitTesting(false)
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    Text(lang("Recipient Address"))
                    Spacer(minLength: 8)
                    if let validationState {
                        Text(lang(validationState.localizationKey))
                            .textStyle(.supporting)
                            .textCase(nil)
                            .foregroundStyle(Color.air.error)
                    }
                }
            }
            
            Group {
                if model.isFocused {
                    RecipientSuggestions(model: model)
                        .transition(.opacity.combined(with: .offset(y: -10)))
                }
            }
            .animation(.default, value: model.isFocused)
        }
    }
}

private struct Cell: View {
    
    var model: SendRecipientModel
    var onPasteAction: (() -> Bool)?
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            HStack {
                AddressTextField(
                    value: $model.textFieldInput,
                    isFocused: $model.isFocused,
                    onNext: onSubmit,
                    onPaste: onFieldPaste
                )
                .offset(y: 1)
                .background(alignment: .leading) {
                    if model.isEmpty {
                        Text(lang("Wallet address or domain"))
                            .foregroundStyle(Color(UIColor.placeholderText))
                    }
                }
                .opacity(!model.isEmpty && !model.isFocused ? 0 : 1)
                .overlay(alignment: .leading) {
                    if !model.isEmpty && !model.isFocused {
                        ResolvedAddressView(model: model)
                    }
                }
                
                if model.isEmpty {
                    HStack(spacing: 12) {
                        Button(action: onPaste) {
                            Text(lang("Paste"))
                        }
                        Button(action: onScan) {
                            Image.airBundle("ScanIcon")
                        }
                    }
                    .offset(x: 4)
                    .padding(.vertical, -1)
                } else {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .tint(Color.air.secondaryLabel)
                            .imageScale(.small)
                    }
                }
            }
            .buttonStyle(.borderless)
        }
    }
    
    func onSubmit() {
        model.isFocused = false
    }
    
    func onFieldPaste() {
        _ = onPasteAction?()
    }
    
    func onPaste() {
        if let pastedAddress = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !pastedAddress.isEmpty {
            model.textFieldInput = pastedAddress
            if onPasteAction?() != true {
                endEditing()
            }
        } else {
            AppActions.showToast(message: lang("Clipboard empty"))
        }
    }
    
    func onScan() {
        Task {
            endEditing()
            if let result = await AppActions.scanQR() {
                endEditing()
                model.onScanResult(result)
            }
        }
    }
    
    func onClear() {
        model.clear()
    }
}

struct ResolvedAddressView: View {
    
    var model: SendRecipientModel
    
    var body: some View {
        WithPerceptionTracking {
            if model.isEmpty || model.isFocused {
                EmptyView()
            } else {
                let display = model.displayComponents()
                
                HStack(spacing: 4) { 
                    if let primary = display.primary, display.secondary == nil {
                        MiddleTruncatedText(primary, textColor: .air.primaryLabel, separatorColor: .air.secondaryLabel)
                    } else {
                        if let primary = display.primary {
                            Text(primary)
                                .textStyle(.body, content: .technical)
                                .foregroundStyle(Color.air.primaryLabel)
                                .truncationMode(.middle)
                        }
                        if let secondary = display.secondary {
                            Text("·")
                                .textStyle(.body, content: .technical)
                                .foregroundStyle(Color.air.secondaryLabel)
                            Text(secondary)
                                .textStyle(.body, content: .technical)
                                .foregroundStyle(Color.air.secondaryLabel)
                        }
                    }
                }
                .animation(.default, value: display.primary)
                .animation(.default, value: display.secondary)
            }
        }
    }
}


#if DEBUG
@available(iOS 18, *)
#Preview {
    @Previewable @State var model = SendRecipientModel(
        account: AccountContext(source: .constant(DUMMY_ACCOUNT)),
        chain: DUMMY_ACCOUNT.firstChain
    )
    NavigationStack {
        InsetList {
            RecipientAddressSection(model: model)
        }
        .background(Color.air.groupedBackground)
        .navigationTitle("RecipientAddressSection")
        .navigationBarTitleDisplayMode(.inline)
    }
    
}
#endif
