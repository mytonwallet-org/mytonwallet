import type { ZerionTransaction } from './types';

import { ARBITRUM_USDC_MAINNET, IS_PERPS_ENABLED } from '../../../config';
import {
  PERPS_CCTP_EXTENSION_ADDRESS,
  PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS,
  PERPS_HYPERCORE_BRIDGE_RELAYER,
} from '../../common/perps';
import { transformEvmTxToUnified } from './activities';

const OWNER = '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045';
const BRIDGE = PERPS_CCTP_EXTENSION_ADDRESS.toLowerCase();
const GROSS_AMOUNT = 10_000_000n + PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS;

function buildUsdcTx(
  operationType: string,
  from: string,
  to: string,
  direction: 'in' | 'out',
): ZerionTransaction {
  return {
    type: 'transactions',
    id: '0xusdc',
    attributes: {
      address: OWNER,
      operation_type: operationType,
      hash: '0xusdc',
      mined_at_block: 1,
      mined_at: '2026-10-30T00:00:00Z',
      sent_from: from,
      sent_to: to,
      status: 'confirmed',
      nonce: 1,
      fee: { quantity: { int: '21000', decimals: 18, float: 0, numeric: '0' }, price: 0, value: 0 },
      transfers: [{
        act_id: '0',
        direction,
        sender: from,
        recipient: to,
        quantity: { int: GROSS_AMOUNT.toString(), decimals: 6, float: 10, numeric: '10' },
        // eslint-disable-next-line no-null/no-null
        price: null,
        // eslint-disable-next-line no-null/no-null
        value: null,
        fungible_info: {
          id: 'arbitrum-usdc',
          name: 'USD Coin',
          symbol: 'USDC',
          // eslint-disable-next-line no-null/no-null
          icon: null,
          flags: { verified: true },
          implementations: [{
            chain_id: 'arbitrum',
            address: ARBITRUM_USDC_MAINNET.tokenAddress.toLowerCase(),
            decimals: 6,
          }],
        },
      }],
      approvals: [],
      flags: { is_trash: false },
      acts: [],
    },
    relationships: { chain: { links: { related: '' }, data: { type: 'chains', id: 'arbitrum' } } },
  } as unknown as ZerionTransaction;
}

describe('Perps stays out of the activity history on this release train', () => {
  it('keeps the feature closed', () => {
    expect(IS_PERPS_ENABLED).toBe(false);
  });

  it('labels an Arbitrum USDC mint from the HyperCore relayer as a plain mint', () => {
    const tx = buildUsdcTx('mint', PERPS_HYPERCORE_BRIDGE_RELAYER.toLowerCase(), OWNER.toLowerCase(), 'in');

    const activity = transformEvmTxToUnified('arbitrum', tx, OWNER);

    expect(activity).toMatchObject({ kind: 'transaction', type: 'mint' });
  });

  it('leaves a USDC transfer to the CCTP extension as an ordinary transfer', () => {
    const tx = buildUsdcTx('execute', OWNER.toLowerCase(), BRIDGE, 'out');

    const activity = transformEvmTxToUnified('arbitrum', tx, OWNER);

    expect(activity).not.toHaveProperty('type', 'perps_deposit');
    expect(activity).toMatchObject({ kind: 'transaction', amount: -GROSS_AMOUNT });
  });
});
