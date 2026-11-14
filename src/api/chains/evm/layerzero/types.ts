export type VtTransaction = { from: string; to: string; chainId: number; data: string; value?: string };
export type VtQuote = {
  id: string;
  srcAmount: string;
  dstAmount: string;
  dstAmountMin: string;
  expiresAt?: string;
  routeSteps: { type: string; srcChainKey: string }[];
  fees: { type: string; address: string; amount: string; chainKey: string }[];
  userSteps: {
    type: string;
    chainKey: string;
    chainType?: string;
    signerAddress: string;
    transaction?: { encoded: VtTransaction };
  }[];
};
export type VtPlan = {
  provider: 'layerzero';
  quote: VtQuote;
  expiresAt: number;
};
export type VtIntent = {
  sourceChain: string;
  destinationChain: string;
  owner: string;
  recipient: string;
  sourceToken: string;
  destinationToken: string;
  sourceDecimals: number;
  destinationDecimals: number;
  amount: string;
  minimum: string;
  feeAmount: string;
  nativeFeeBudget: string;
};
