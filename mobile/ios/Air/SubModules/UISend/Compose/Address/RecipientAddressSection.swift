
import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Perception
import SwiftNavigation

struct RecipientAddressSection: View {
    
    var model: AddressInputModel
    
    var body: some View {
        @Perception.Bindable var model = model
        WithPerceptionTracking {
            InsetSection {
                InsetCell {
                    Cell(model: model)
                }
                .contentShape(.rect)
                .onTapGesture {
                    model.isFocused = true
                }
            } header: {
                Text(lang("Recipient Address"))
            }
            
            Group {
                if model.isFocused {
                    AddressSuggestions(model: model)
                        .transition(.opacity.combined(with: .offset(y: -10)))
                }
            }
            .animation(.default, value: model.isFocused)
        }
    }
}

private struct Cell: View {
    
    var model: AddressInputModel
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            HStack {
                AddressTextField(
                    value: $model.textFieldInput,
                    isFocused: $model.isFocused,
                    onNext: onSubmit
                )
                .offset(y: 1)
                .background(alignment: .leading) {
                    if model.source.isEmpty {
                        Text(lang("Wallet address or domain"))
                            .foregroundStyle(Color(UIColor.placeholderText))
                    }
                }
                .opacity(!model.source.isEmpty && !model.isFocused ? 0 : 1)
                .overlay(alignment: .leading) {
                    if !model.source.isEmpty && !model.isFocused {
                        ResolvedAddressView(model: model)
                    }
                }
                
                if model.source.isEmpty {
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
                            .tint(Color(WTheme.secondaryLabel))
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
    
    func onPaste() {
        if let pastedAddress = UIPasteboard.general.string, !pastedAddress.isEmpty {
            model.textFieldInput = pastedAddress
            endEditing()
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
        model.source = .constant("")
        model.textFieldInput = ""
    }
}

struct ResolvedAddressView: View {
    
    var model: AddressInputModel
    
    var body: some View {
        WithPerceptionTracking {
            if model.source.isEmpty || model.isFocused {
                EmptyView()
            } else {
                let display = model.displayComponents()
                HStack(spacing: 4) {
                    if let primary = display.primary {
                        Text(primary)
                            .foregroundStyle(Color.air.primaryLabel)
                            .truncationMode(.middle)
                    }
                    if let secondary = display.secondary {
                        Text("·")
                            .foregroundStyle(Color.air.secondaryLabel)
                        Text(secondary)
                            .foregroundStyle(Color.air.secondaryLabel)
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
    @Previewable @State var model = AddressInputModel(
        account: AccountContext(source: .constant(DUMMY_ACCOUNT)),
        token: TokenProvider(tokenSlug: DUMMY_ACCOUNT.firstChain.nativeToken.slug)
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
