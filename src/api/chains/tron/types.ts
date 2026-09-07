export enum TronContractMethodSignature {
  Transfer = 'a9059cbb',
  TransferFrom = '23b872dd',
}

export type TronTrc20Transaction = {
  transaction_id: string;
  block_timestamp: number;
  from: string;
  to: string;
  type: string;
  value: string;
  token_info: {
    address: string;
  };
};
