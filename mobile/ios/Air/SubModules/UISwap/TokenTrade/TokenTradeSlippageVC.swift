import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore

final class TokenTradeSlippageVC: WViewController {
    private let initialSlippage: BigInt
    private let onCommit: (BigInt) -> Void

    init(slippage: BigInt, onCommit: @escaping (BigInt) -> Void) {
        self.initialSlippage = slippage
        self.onCommit = onCommit
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Slippage")
        view.backgroundColor = .air.sheetBackground
        configureNavigationItemWithTransparentBackground()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        _ = addHostingController(TokenTradeSlippageView(slippage: initialSlippage) { [weak self] value in
            self?.onCommit(value)
            self?.dismiss(animated: true)
        }, constraints: .fill)
        let sheet = navigationController?.sheetPresentationController
        sheet?.detents = [.custom(identifier: .init("slippage")) { min(350, $0.maximumDetentValue) }]
        sheet?.prefersGrabberVisible = false
    }
}

enum TokenTradeSlippageScale {
    static let stops = ([BigInt(1)] + SWAP_SLIPPAGE_PRESETS + [MAX_SLIPPAGE_VALUE]).map {
        $0.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS)
    }

    static func position(for value: Double) -> Double {
        log(min(50, max(0.1, value)) / 0.1) / log(500)
    }

    static func value(at position: Double) -> Double {
        (0.1 * pow(500, min(1, max(0, position))) * 10).rounded() / 10
    }

    static func snappedValue(at position: Double, trackWidth: Double) -> Double {
        let position = min(1, max(0, position))
        if let stop = stops.min(by: { abs(Self.position(for: $0) - position) < abs(Self.position(for: $1) - position) }),
           abs(Self.position(for: stop) - position) * max(1, trackWidth) <= 8 {
            return stop
        }
        return value(at: position)
    }
}

private struct TokenTradeSlippageView: View {
    @State private var draft: BigInt?
    @State private var focused = false
    @State private var countsDown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    let onCommit: (BigInt) -> Void

    init(slippage: BigInt, onCommit: @escaping (BigInt) -> Void) {
        _draft = State(initialValue: slippage)
        self.onCommit = onCommit
    }

    private var isValid: Bool { draft.map { $0 > 0 && $0 <= MAX_SLIPPAGE_VALUE } ?? false }
    private var amountFont: UIFont { .compactRounded(ofSize: 40, weight: .bold) }
    private var amountText: String { formatBigIntText(draft ?? 0, tokenDecimals: SLIPPAGE_DECIMALS) }
    private var amountValue: Double { draft?.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS) ?? 0 }
    private var fieldWidth: CGFloat {
        let width = (amountText as NSString).size(withAttributes: [.font: amountFont]).width
        return ceil(width)
    }
    private func sliderValue(trackWidth: CGFloat) -> Binding<Double> {
        Binding(get: { TokenTradeSlippageScale.position(for: draft?.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS) ?? 5) },
                set: { select(BigInt(Int((TokenTradeSlippageScale.snappedValue(at: $0, trackWidth: trackWidth) * 10).rounded()))) })
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        rangeButton("Min", value: 1)
                        Spacer()
                        amountField
                        .padding(10)
                        .background(Color.air.background, in: .rect(cornerRadius: 22))
                        .contentShape(.rect)
                        .onTapGesture { focused = true }
                        .accessibilityElement(children: focused ? .contain : .ignore)
                        .accessibilityLabel(lang("Slippage"))
                        .accessibilityValue(amountText + "%")
                        .accessibilityAddTraits(focused ? [] : .isButton)
                        .accessibilityAction { focused = true }
                        Spacer()
                        rangeButton("Max", value: MAX_SLIPPAGE_VALUE)
                    }
                    VStack(spacing: 0) {
                        Slider(value: sliderValue(trackWidth: geometry.size.width - 60 - 28), in: 0...1)
                            .frame(height: 44)
                            .tint(Color(uiColor: UIColor(hex: "#0088FF")))
                            .accessibilityLabel(lang("Slippage"))
                            .accessibilityValue(formatBigIntText(draft ?? DEFAULT_SLIPPAGE, tokenDecimals: SLIPPAGE_DECIMALS) + "%")
                            .accessibilityIdentifier("tokenTrade.slippage.slider")
                            .accessibilityAdjustableAction { direction in
                                let value = draft ?? DEFAULT_SLIPPAGE
                                switch direction {
                                case .increment: select(min(MAX_SLIPPAGE_VALUE, value + 1))
                                case .decrement: select(max(1, value - 1))
                                @unknown default: break
                                }
                            }
                        presetStops
                    }
                    Spacer(minLength: 0)
                    TokenTradeContinueButton(configuration: .init(title: .text(lang("Done")), isEnabled: isValid, showLoading: false),
                                             tintColor: UIColor(hex: "#0088FF")) {
                        guard isValid, let draft else { return }
                        onCommit(draft)
                    }
                    .disabled(!isValid)
                    .frame(height: 52)
                }
                .padding(.horizontal, 30)
                .padding(.top, 12)
                .padding(.bottom, max(0, 28 - geometry.safeAreaInsets.bottom))
                .frame(minHeight: geometry.size.height)
            }
            .backportScrollBounceBehaviorBasedOnSize()
        }
    }

    private var presetStops: some View {
        GeometryReader { track in
            let stops = layoutDirection == .rightToLeft ? Array(TokenTradeSlippageScale.stops.reversed()) : TokenTradeSlippageScale.stops
            let centers = stops.map { value in
                let position = TokenTradeSlippageScale.position(for: value)
                return 14 + (track.size.width - 28) * (layoutDirection == .rightToLeft ? 1 - position : position)
            }
            ForEach(stops.indices, id: \.self) { index in
                let lower = index == 0 ? 0 : (centers[index - 1] + centers[index]) / 2
                let upper = index == stops.count - 1 ? track.size.width : (centers[index] + centers[index + 1]) / 2
                Button { select(BigInt(Int((stops[index] * 10).rounded()))) } label: {
                    Circle()
                        .fill(amountValue == stops[index] ? Color.air.tint : Color.air.secondaryLabel.opacity(0.35))
                        .frame(width: 4, height: 4)
                        .position(x: centers[index] - lower, y: 10)
                        .frame(width: upper - lower, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lang("Slippage"))
                .accessibilityValue(formatBigIntText(BigInt(Int((stops[index] * 10).rounded())), tokenDecimals: SLIPPAGE_DECIMALS) + "%")
                .accessibilityIdentifier("tokenTrade.slippage.preset.\(index)")
                .position(x: (lower + upper) / 2, y: 22)
            }
        }
        .frame(height: 44)
    }

    private var amountField: some View {
        animatedAmount
            .fixedSize()
            .accessibilityHidden(true)
            .overlay(alignment: .leading) {
                WUIAmountInput(amount: $draft, maximumFractionDigits: SLIPPAGE_DECIMALS,
                               font: amountFont, fractionFont: amountFont,
                               alignment: .right, isFocused: $focused, error: !isValid)
                    .frame(width: fieldWidth, height: amountFont.lineHeight)
                    .opacity(focused ? 1 : 0)
                    .allowsHitTesting(focused)
                    .accessibilityHidden(!focused)
                    .accessibilityLabel(lang("Slippage"))
                    .accessibilityIdentifier("tokenTrade.slippage.input")
            }
            .animation(focused || reduceMotion || !AppStorageHelper.animations ? nil : .easeInOut(duration: 0.2), value: draft)
    }

    private var animatedAmount: some View {
        ZStack {
            amountLabel
                .id(amountText)
                .transition(.asymmetric(
                    insertion: .move(edge: countsDown ? .top : .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
        }
        .clipped()
    }

    private var amountLabel: Text {
        let amount = Text(amountText)
            .font(Font(amountFont))
            .foregroundColor(focused ? .clear : isValid ? Color.air.primaryLabel : Color.air.error)
        let percent = Text("%")
            .font(.system(size: 32, weight: .heavy, design: .rounded))
            .foregroundColor(Color.air.secondaryLabel)
        return Text("\(amount)\(percent)")
    }

    private func select(_ value: BigInt) {
        countsDown = value < (draft ?? 0)
        focused = false
        draft = value
    }

    private func rangeButton(_ title: String, value: BigInt) -> some View {
        Button { select(value) } label: {
            Text(lang(title))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.air.primaryLabel)
                .frame(minWidth: 64, minHeight: 26)
                .background(Color.air.secondaryLabel.opacity(0.12), in: .capsule)
                .frame(height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
