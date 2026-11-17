import type { ApiPerpsFundingRequirements } from '../../../api/types';
import type { LangFn } from '../../../util/langProvider';

import { getPerpsFundingBlock } from './FundingNotice';

const lang = ((key: string, vars?: Record<string, string>) => (vars ? `${key} ${vars.minUSDC}` : key)) as LangFn;

const FUNDING: ApiPerpsFundingRequirements = {
  requiredUsdc: '10.2',
  requiredBridgeFeeUsdc: '0',
  requiredGasUsdc: '0',
  requiredEth: '0',
  requiredEthUsd: '0',
  usdcBalance: '0',
  ethBalance: '0',
  needsUsdc: true,
  needsEth: false,
};

describe('getPerpsFundingBlock', () => {
  it('asks for the deposit together with the network fee paid in USDC', () => {
    expect(getPerpsFundingBlock(lang, FUNDING, false)?.description).toBe('$perps_funding_usdc 10.2');
    expect(getPerpsFundingBlock(lang, { ...FUNDING, requiredGasUsdc: '0.5' }, false)?.description)
      .toBe('$perps_funding_usdc 10.7');
  });
});
