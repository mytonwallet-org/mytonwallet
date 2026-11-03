import type { ApiPerpsWithdrawPermit } from '../../src/api/types';

const SEND_TO_EVM_FIELDS = [
  { name: 'hyperliquidChain', type: 'string' },
  { name: 'token', type: 'string' },
  { name: 'amount', type: 'string' },
  { name: 'sourceDex', type: 'string' },
  { name: 'destinationRecipient', type: 'string' },
  { name: 'addressEncoding', type: 'string' },
  { name: 'destinationChainId', type: 'uint32' },
  { name: 'gasLimit', type: 'uint64' },
  { name: 'data', type: 'bytes' },
  { name: 'nonce', type: 'uint64' },
];

export function perpsWithdrawalFixture(
  destination: string, amountUsdc = '99.97', sourceDex = 'spot',
): ApiPerpsWithdrawPermit {
  const nonce = Date.now();
  const values = {
    hyperliquidChain: 'Mainnet', token: 'USDC', amount: amountUsdc, sourceDex, destinationRecipient: destination,
    addressEncoding: 'hex', destinationChainId: 3, gasLimit: 200_000, data: '0x', nonce,
  };
  const action = { type: 'sendToEvmWithData', signatureChainId: '0xa4b1', ...values };
  const permitData = {
    domain: {
      name: 'HyperliquidSignTransaction', version: '1', chainId: 42161,
      verifyingContract: '0x0000000000000000000000000000000000000000',
    },
    types: { 'HyperliquidTransaction:SendToEvmWithData': SEND_TO_EVM_FIELDS },
    values,
  };
  return { requiresPermitSignature: true, amountUsdc, forwardFeeUsdc: '0.2', destination,
    action, nonce, permitData };
}
