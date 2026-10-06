export type EvmMetaTransaction = {
  to: string;
  value?: bigint;
  data?: string;
};

export type EvmBatchSubmitResult = {
  userOpHash: string;
  txHash: string;
  success: boolean;
};
