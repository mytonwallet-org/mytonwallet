import WalletContext

public struct ExplainSwapFeeInput {
    public var swapType: SwapType
    public var tokenIn: ApiToken
    public var networkFee: MDouble?
    public var realNetworkFee: MDouble?
    public var ourFee: MDouble?
    public var dieselStatus: DieselStatus?
    public var dieselFee: MDouble?
    public var nativeTokenInBalance: BigInt?
    
    public init(
        swapType: SwapType,
        tokenIn: ApiToken,
        networkFee: MDouble?,
        realNetworkFee: MDouble?,
        ourFee: MDouble?,
        dieselStatus: DieselStatus?,
        dieselFee: MDouble?,
        nativeTokenInBalance: BigInt?
    ) {
        self.swapType = swapType
        self.tokenIn = tokenIn
        self.networkFee = networkFee
        self.realNetworkFee = realNetworkFee
        self.ourFee = ourFee
        self.dieselStatus = dieselStatus
        self.dieselFee = dieselFee
        self.nativeTokenInBalance = nativeTokenInBalance
    }
}

public struct SwapFeeDetails: Equatable, Hashable, Codable, Sendable {
    public var precision: MFee.FeePrecision
    public var terms: MFee.FeeTerms
    public var networkTerms: MFee.FeeTerms
    
    public init(precision: MFee.FeePrecision, terms: MFee.FeeTerms, networkTerms: MFee.FeeTerms) {
        self.precision = precision
        self.terms = terms
        self.networkTerms = networkTerms
    }
}

public struct ExplainedSwapFee: Equatable, Hashable, Codable, Sendable {
    public var isGasless: Bool
    public var fullFee: SwapFeeDetails?
    public var realFee: SwapFeeDetails?
    public var fullNetworkFee: MFee?
    public var realNetworkFee: MFee?
    public var excessFee: BigInt?
    public var shouldShowOurFee: Bool
    
    public init(
        isGasless: Bool,
        fullFee: SwapFeeDetails? = nil,
        realFee: SwapFeeDetails? = nil,
        fullNetworkFee: MFee? = nil,
        realNetworkFee: MFee? = nil,
        excessFee: BigInt? = nil,
        shouldShowOurFee: Bool
    ) {
        self.isGasless = isGasless
        self.fullFee = fullFee
        self.realFee = realFee
        self.fullNetworkFee = fullNetworkFee
        self.realNetworkFee = realNetworkFee
        self.excessFee = excessFee
        self.shouldShowOurFee = shouldShowOurFee
    }
    
    public var networkFeeDetails: ExplainedTransferFee? {
        guard fullNetworkFee != nil || realNetworkFee != nil else { return nil }
        return ExplainedTransferFee(
            isGasless: isGasless,
            canTransferFullBalance: false,
            fullFee: fullNetworkFee,
            realFee: realNetworkFee,
            excessFee: excessFee
        )
    }
}

public func explainSwapFee(_ input: ExplainSwapFeeInput) -> ExplainedSwapFee {
    let shouldShowOurFee = input.swapType == .onChain
    let tokenIn = input.tokenIn
    let nativeToken = TokenStore.tokens[tokenIn.nativeTokenSlug]
    let nativeDecimals = nativeToken?.decimals ?? 0
    let networkFee = input.networkFee.map { doubleToBigInt($0.value, decimals: nativeDecimals) }
    let realNetworkFee = input.realNetworkFee.map { doubleToBigInt($0.value, decimals: nativeDecimals) }
    let ourFee = input.ourFee.map { doubleToBigInt($0.value, decimals: tokenIn.decimals) } ?? .zero
    let isStarsDiesel = input.dieselStatus == .starsFee
    let dieselDecimals = isStarsDiesel ? 0 : tokenIn.decimals
    let dieselFee = input.dieselFee.map { doubleToBigInt($0.value, decimals: dieselDecimals) }
    let nativeTokenInBalance = input.nativeTokenInBalance
    let excessFee: BigInt? = if let networkFee, let realNetworkFee {
        max(.zero, networkFee - realNetworkFee)
    } else {
        nil
    }
    let isExact = excessFee == .zero
    
    if shouldSwapBeGasless(
        swapType: input.swapType,
        tokenIn: tokenIn,
        networkFee: networkFee,
        dieselStatus: input.dieselStatus,
        nativeTokenInBalance: nativeTokenInBalance
    ) {
        return explainGaslessSwapFee(
            tokenIn: tokenIn,
            networkFee: networkFee,
            realNetworkFee: realNetworkFee,
            ourFee: ourFee,
            dieselFee: dieselFee,
            nativeTokenInBalance: nativeTokenInBalance,
            isExact: isExact,
            shouldShowOurFee: shouldShowOurFee,
            isStarsDiesel: isStarsDiesel
        )
    }
    
    return explainGasfullSwapFee(
        tokenIn: tokenIn,
        networkFee: networkFee,
        realNetworkFee: realNetworkFee,
        ourFee: ourFee,
        isExact: isExact,
        shouldShowOurFee: shouldShowOurFee
    )
}

private func explainGasfullSwapFee(
    tokenIn: ApiToken,
    networkFee: BigInt?,
    realNetworkFee: BigInt?,
    ourFee: BigInt,
    isExact: Bool,
    shouldShowOurFee: Bool
) -> ExplainedSwapFee {
    var result = ExplainedSwapFee(isGasless: false, shouldShowOurFee: shouldShowOurFee)
    if let networkFee {
        let networkTerms = MFee.FeeTerms(token: nil, native: networkFee, stars: nil)
        let fullPrecision: MFee.FeePrecision = isExact ? .exact : .lessThan
        let fullTerms = addOurFeeToTerms(networkTerms, ourFee: ourFee, isOurFeeNative: tokenIn.isNative)
        result.fullFee = .init(precision: fullPrecision, terms: fullTerms, networkTerms: networkTerms)
        result.fullNetworkFee = .init(precision: fullPrecision, terms: networkTerms, nativeSum: networkFee)
    }
    if let realNetworkFee {
        let networkTerms = MFee.FeeTerms(token: nil, native: realNetworkFee, stars: nil)
        let realPrecision: MFee.FeePrecision = isExact ? .exact : .approximate
        let realTerms = addOurFeeToTerms(networkTerms, ourFee: ourFee, isOurFeeNative: tokenIn.isNative)
        result.realFee = .init(precision: realPrecision, terms: realTerms, networkTerms: networkTerms)
        result.realNetworkFee = .init(precision: realPrecision, terms: networkTerms, nativeSum: realNetworkFee)
    }
    if let networkFee, let realNetworkFee {
        result.excessFee = max(.zero, networkFee - realNetworkFee)
    }
    return result
}

private func explainGaslessSwapFee(
    tokenIn: ApiToken,
    networkFee: BigInt?,
    realNetworkFee: BigInt?,
    ourFee: BigInt,
    dieselFee: BigInt?,
    nativeTokenInBalance: BigInt?,
    isExact: Bool,
    shouldShowOurFee: Bool,
    isStarsDiesel: Bool
) -> ExplainedSwapFee {
    var result = ExplainedSwapFee(isGasless: true, shouldShowOurFee: shouldShowOurFee)
    guard let networkFee, let dieselFee, let nativeTokenInBalance else {
        return result
    }
    let dieselKeyTerms = MFee.FeeTerms(
        token: isStarsDiesel ? nil : dieselFee,
        native: nativeTokenInBalance,
        stars: isStarsDiesel ? dieselFee : nil
    )
    let fullPrecision: MFee.FeePrecision = isExact ? .exact : .lessThan
    let fullTerms = addOurFeeToTerms(dieselKeyTerms, ourFee: ourFee, isOurFeeNative: false)
    result.fullFee = .init(precision: fullPrecision, terms: fullTerms, networkTerms: dieselKeyTerms)
    result.realFee = result.fullFee
    result.fullNetworkFee = .init(precision: fullPrecision, terms: dieselKeyTerms, nativeSum: networkFee)
    
    if let realNetworkFee {
        let networkFeeCoveredByDiesel = max(.zero, networkFee - nativeTokenInBalance)
        let realFeeInDiesel = convertFee(
            amount: realNetworkFee,
            exampleFromAmount: networkFeeCoveredByDiesel,
            exampleToAmount: dieselFee
        )
        let dieselRealFee = min(dieselFee, realFeeInDiesel)
        let nativeRealFee = max(.zero, realNetworkFee - networkFeeCoveredByDiesel)
        let realNetworkTerms = MFee.FeeTerms(
            token: isStarsDiesel ? nil : dieselRealFee,
            native: nativeRealFee,
            stars: isStarsDiesel ? dieselRealFee : nil
        )
        let realPrecision: MFee.FeePrecision = isExact ? .exact : .approximate
        let realTerms = addOurFeeToTerms(realNetworkTerms, ourFee: ourFee, isOurFeeNative: false)
        result.realFee = .init(precision: realPrecision, terms: realTerms, networkTerms: realNetworkTerms)
        result.realNetworkFee = .init(precision: realPrecision, terms: realNetworkTerms, nativeSum: realNetworkFee)
    }
    if let realNetworkFee {
        result.excessFee = max(.zero, networkFee - realNetworkFee)
    }
    return result
}

private func shouldSwapBeGasless(
    swapType: SwapType,
    tokenIn: ApiToken,
    networkFee: BigInt?,
    dieselStatus: DieselStatus?,
    nativeTokenInBalance: BigInt?
) -> Bool {
    guard swapType == .onChain else { return false }
    guard !tokenIn.isNative else { return false }
    guard let dieselStatus, dieselStatus != .notAvailable else { return false }
    guard let networkFee, let nativeTokenInBalance else { return false }
    return nativeTokenInBalance < networkFee
}

private func addOurFeeToTerms(_ terms: MFee.FeeTerms, ourFee: BigInt, isOurFeeNative: Bool) -> MFee.FeeTerms {
    guard ourFee > 0 else { return terms }
    if isOurFeeNative {
        return .init(token: terms.token, native: (terms.native ?? .zero) + ourFee, stars: terms.stars)
    } else {
        return .init(token: (terms.token ?? .zero) + ourFee, native: terms.native, stars: terms.stars)
    }
}
