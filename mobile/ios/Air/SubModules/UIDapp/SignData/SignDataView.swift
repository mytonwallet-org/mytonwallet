
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

enum SignDataWarningKind: Hashable {
    case genericTrust
}

func signDataWarningKinds(
    payload _: SignDataPayload
) -> [SignDataWarningKind] {
    [.genericTrust]
}

struct SignDataViewOrPlaceholder: View {
    var update: ApiUpdate.DappSignData?
    var accountContext: AccountContext
    var onConfirm: () async -> ()
    var onCancel: () -> ()

    var body: some View {
        if let update {
            SignDataView(
                update: update,
                accountContext: accountContext,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
            .transition(.opacity.animation(.default))
        } else {
            SignDataPlaceholderView(accountContext: accountContext)
                .transition(.opacity.animation(.default))
        }
    }
}

struct SignDataView: View {

    var update: ApiUpdate.DappSignData
    var accountContext: AccountContext
    var onConfirm: () async -> ()
    var onCancel: () -> ()

    @State private var isSubmitting = false
    @Namespace private var ns

    var body: some View {
        InsetList {
            DappHeaderView(
                dapp: update.dapp,
                accountContext: accountContext,
            )
            .padding(.bottom, 16)
            switch update.payloadToSign {
            case .text(let text):
                makeText(payload: text)
            case .binary(let binary):
                makeBinary(payload: binary)
            case .cell(let cell):
                makeCell(payload: cell, parsedPreview: update.parsedPayloadToSign)
            case .eip712(let eip712):
                makeEip712(payload: eip712)
            }
            ForEach(
                signDataWarningKinds(payload: update.payloadToSign),
                id: \.self
            ) { warning in
                makeWarningView(warning)
            }

        }
        .coordinateSpace(name: ns)
        .safeAreaInset(edge: .bottom) {
            buttons
        }
    }
    
    @ViewBuilder
    func makeText(payload: SignDataPayloadText) -> some View {
        InsetSection {
            InsetCell {
                Text(verbatim: payload.text)
                    .textStyle(.body, scaling: .dynamic)
                    .lineSpacing(1)
                    .frame(minHeight: 22)
            }
        } header: {
            Text(lang("Message"))
        }
    }

    @ViewBuilder
    func makeBinary(payload: SignDataPayloadBinary) -> some View {
        InsetSection {
            InsetExpandableCell(content: payload.bytes)
        } header: {
            Text(lang("Binary Data"))
        }
    }

    @ViewBuilder
    func makeEip712(payload: SignDataPayloadEip712) -> some View {
        InsetSection {
            InsetCell {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lang("Primary type"))
                        .textStyle(.supportingStrong)
                        .foregroundStyle(Color.air.secondaryLabel)
                    Text(verbatim: payload.primaryType)
                        .textStyle(
                            .body,
                            content: .technical,
                            scaling: .dynamic
                        )
                        .lineSpacing(1)
                        .frame(minHeight: 22)
                }
            }
        } header: {
            Text(lang("EIP-712 typed data"))
        }
        InsetSection {
            InsetCell(verticalPadding: 14) {
                Eip712ObjectView(
                    object: payload.domain,
                    typeName: "EIP712Domain",
                    types: payload.types
                )
            }
        } header: {
            Text(lang("EIP-712 domain"))
        }
        InsetSection {
            InsetCell(verticalPadding: 14) {
                Eip712ObjectView(
                    object: payload.message,
                    typeName: payload.primaryType,
                    types: payload.types
                )
            }
        } header: {
            Text(lang("Message"))
        }
    }

    @ViewBuilder
    func makeCell(
        payload: SignDataPayloadCell,
        parsedPreview: ApiUpdate.DappSignData.ParsedSignDataCellPreview?
    ) -> some View {
        if let parsedPreview {
            makeParsedCell(preview: parsedPreview)
        }
        InsetSection {
            InsetCell {
                Text(verbatim: payload.schema)
                    .textStyle(
                        .body,
                        content: .technical,
                        scaling: .dynamic
                    )
                    .lineSpacing(1)
                    .frame(minHeight: 22)
            }
        } header: {
            Text(lang("Cell Schema"))
        }
        InsetSection {
            InsetCell {
                Text(verbatim: payload.cell)
                    .textStyle(
                        .body,
                        content: .technical,
                        scaling: .dynamic
                    )
                    .lineSpacing(1)
                    .frame(minHeight: 22)
            }
        } header: {
            Text(lang("Cell Data"))
        }
    }

    @ViewBuilder
    func makeParsedCell(preview: ApiUpdate.DappSignData.ParsedSignDataCellPreview) -> some View {
        InsetSection {
            InsetCell {
                Text(verbatim: preview.title)
                    .font(.system(size: 16, weight: .semibold))
            }
        } header: {
            Text(lang("Parsed Cell"))
        }
        InsetSection {
            InsetCell(verticalPadding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    ParsedCellFieldRow(
                        label: lang("Bits"),
                        value: String(preview.bits)
                    )
                    ParsedCellFieldRow(
                        label: lang("References"),
                        value: String(preview.refs)
                    )
                    if let hash = preview.hash {
                        ParsedCellFieldRow(
                            label: lang("Hash"),
                            value: shortenHash(hash)
                        )
                    }
                }
            }
        } header: {
            Text(lang("Cell Metadata"))
        }
        if let error = preview.error {
            InsetSection {
                InsetCell {
                    Text(verbatim: error)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.air.negativeAmount)
                        .textSelection(.enabled)
                }
            } header: {
                Text(lang("Parsing Error"))
            }
        }
        InsetSection {
            InsetCell(verticalPadding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(preview.fields.enumerated()), id: \.offset) { _, field in
                        ParsedCellFieldRow(
                            label: field.label,
                            value: field.value,
                            depth: field.depth,
                            isMuted: field.isMuted == true
                        )
                    }
                }
            }
        } header: {
            Text(lang("Cell Fields"))
        }
    }

    func shortenHash(_ hash: String) -> String {
        if hash.count <= 20 {
            return hash
        }
        return "\(hash.prefix(10))...\(hash.suffix(10))"
    }

    @ViewBuilder
    func makeWarningView(_: SignDataWarningKind) -> some View {
        WarningView(
            text: lang("$signature_warning"),
            kind: .warning,
        )
        .padding(.horizontal, 16)
    }

    var buttons: some View {

        HStack(spacing: 16) {
            Button(action: onCancel) {
                Text(lang("Cancel"))
            }
            .buttonStyle(.airSecondary)
            Button(action: confirm) {
                Text(lang("Sign"))
            }
            .buttonStyle(.airPrimary)
            .environment(\.isLoading, isSubmitting)
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private func confirm() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task { @MainActor in
            await onConfirm()
            isSubmitting = false
        }
    }
}

private struct ParsedCellFieldRow: View {
    var label: String
    var value: String
    var depth = 0
    var isMuted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.air.secondaryLabel)
            Text(verbatim: value)
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(isMuted ? Color.air.secondaryLabel : Color.air.primaryLabel)
                .textSelection(.enabled)
        }
        .padding(.leading, CGFloat(max(depth, 0)) * 10)
    }
}

private extension Encodable {
    var prettyJSONString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}

private let maxEip712Depth = 32

struct Eip712ObjectView: View {
    var object: [String: AnyCodable]
    var typeName: String
    var types: [String: [SignDataPayloadEip712TypeField]]

    var body: some View {
        Eip712ValueView(
            value: .dictionary(object),
            solidityType: typeName,
            types: types,
            depth: 0
        )
    }
}

private struct Eip712ValueView: View {
    var value: AnyCodable?
    var solidityType: String?
    var types: [String: [SignDataPayloadEip712TypeField]]
    var depth: Int

    var body: some View {
        if depth > maxEip712Depth {
            Eip712ScalarText(text: value?.eip712ScalarText ?? "")
        } else if let elementType = solidityType?.eip712ArrayElementType {
            Eip712ArrayView(
                values: value?.arrayValue ?? [],
                elementType: elementType,
                types: types,
                depth: depth
            )
        } else if let solidityType,
                  let fields = types[solidityType],
                  !fields.isEmpty,
                  let object = value?.dictionaryValue {
            Eip712StructView(
                object: object,
                fields: fields,
                types: types,
                depth: depth
            )
        } else if solidityType?.isEip712PrimitiveType == true {
            Eip712ScalarText(text: value?.eip712ScalarText ?? "")
        } else if let value {
            Eip712UnknownValueView(
                value: value,
                types: types,
                depth: depth
            )
        } else {
            Eip712ScalarText(text: "")
        }
    }
}

private struct Eip712StructView: View {
    var object: [String: AnyCodable]
    var fields: [SignDataPayloadEip712TypeField]
    var types: [String: [SignDataPayloadEip712TypeField]]
    var depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                Eip712FieldRow(name: field.name) {
                    Eip712ValueView(
                        value: object[field.name],
                        solidityType: field.type,
                        types: types,
                        depth: depth + 1
                    )
                }
            }
        }
        .padding(.leading, CGFloat(min(depth, 4)) * 10)
    }
}

private struct Eip712UnknownValueView: View {
    var value: AnyCodable
    var types: [String: [SignDataPayloadEip712TypeField]]
    var depth: Int

    var body: some View {
        switch value {
        case .dictionary(let object):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(object.keys.sorted(), id: \.self) { key in
                    Eip712FieldRow(name: key) {
                        Eip712ValueView(
                            value: object[key],
                            solidityType: nil,
                            types: types,
                            depth: depth + 1
                        )
                    }
                }
            }
            .padding(.leading, CGFloat(min(depth, 4)) * 10)
        case .array(let values):
            Eip712ArrayView(
                values: values,
                elementType: nil,
                types: types,
                depth: depth
            )
        default:
            Eip712ScalarText(text: value.eip712ScalarText)
        }
    }
}

private struct Eip712ArrayView: View {
    var values: [AnyCodable]
    var elementType: String?
    var types: [String: [SignDataPayloadEip712TypeField]]
    var depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "[\(index)]")
                        .textStyle(.supportingStrong, content: .technical)
                        .foregroundStyle(Color.air.secondaryLabel)
                    Eip712ValueView(
                        value: value,
                        solidityType: elementType,
                        types: types,
                        depth: depth + 1
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct Eip712FieldRow<Content: View>: View {
    var name: String
    var content: Content

    init(name: String, @ViewBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: name)
                .textStyle(.supportingStrong, content: .technical)
                .foregroundStyle(Color.air.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Eip712ScalarText: View {
    var text: String

    var body: some View {
        Text(verbatim: text)
            .textStyle(.calloutStrong, content: .technical)
            .lineSpacing(2)
            .foregroundStyle(Color.air.primaryLabel)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension AnyCodable {
    var arrayValue: [AnyCodable]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var eip712ScalarText: String {
        switch self {
        case .string(let value):
            value
        case .int(let value):
            String(value)
        case .double(let value):
            String(value)
        case .bool(let value):
            String(value)
        case .array, .dictionary:
            prettyJSONString
        case .null:
            ""
        }
    }
}

private extension String {
    var eip712ArrayElementType: String? {
        guard let openBracket = lastIndex(of: "["),
              hasSuffix("]") else {
            return nil
        }
        let suffix = self[openBracket...]
        let countText = suffix.dropFirst().dropLast()
        guard countText.allSatisfy(\.isNumber) else {
            return nil
        }
        return String(self[..<openBracket])
    }

    var isEip712PrimitiveType: Bool {
        if self == "bytes" || self == "string" || self == "address" || self == "bool" {
            return true
        }
        if hasPrefix("bytes") {
            return isFixedBytesSuffixValid(dropFirst(5))
        }
        if hasPrefix("uint") {
            return isIntegerSuffixValid(dropFirst(4), min: 0, max: 999)
        }
        if hasPrefix("int") {
            return isIntegerSuffixValid(dropFirst(3), min: 0, max: 999)
        }
        return false
    }

    private func isIntegerSuffixValid(_ suffix: Substring, min: Int, max: Int) -> Bool {
        if suffix.isEmpty {
            return min == 0
        }
        guard suffix.allSatisfy(\.isNumber),
              let value = Int(suffix) else {
            return false
        }
        return value >= min && value <= max
    }

    private func isFixedBytesSuffixValid(_ suffix: Substring) -> Bool {
        guard !suffix.isEmpty,
              suffix.allSatisfy(\.isNumber),
              suffix.first != "0",
              let value = Int(suffix) else {
            return false
        }
        return value >= 1 && value <= 32
    }
}

private struct SignDataPlaceholderView: View {
    var accountContext: AccountContext

    var body: some View {
        InsetList {
            DappHeaderView(
                dapp: ApiDapp.loadingStub,
                accountContext: accountContext
            )
            
            InsetSection {
                InsetCell {
                    Text(verbatim: "Some signing message")
                        .font17h22()
                        .skeletonPlaceholder(surface: .light)
                }
            } header: {
                Text(lang("Message"))
                    .skeletonPlaceholder(surface: .dark, cornerRadius: 8)
            }
            
        }
        .skeletonContainer()
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 16) {
                Button(action: {}) {
                    Text(lang("Cancel"))
                }
                .buttonStyle(.airSecondary)
                Button(action: {}) {
                    Text(lang("Sign"))
                }
                .buttonStyle(.airPrimary)
            }
            .padding(16)
            .disabled(true)
        }
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview("Placeholder") {
    SignDataPlaceholderView(accountContext: AccountContext(source: .current))
        .background(Color.air.sheetBackground)
}
#endif
