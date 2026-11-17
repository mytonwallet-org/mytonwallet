import React, { memo } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { ApiPerpsFundingRequirements } from '../../../api/types';
import type { LangFn } from '../../../util/langProvider';

import { ARBITRUM, ARBITRUM_USDC_MAINNET } from '../../../config';
import { Big } from '../../../lib/big.js';
import { formatPerpsMoney, formatPerpsRequiredAmount } from '../helpers/formatPerps';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import TradeNotice from '../../swap/TradeNotice';

import styles from './TradeForm.module.scss';

interface OwnProps {
  block: PerpsFundingBlock;
}

type PerpsFundingBlock = {
  title: string;
  description: string;
  /** The text of the main button of the form */
  buttonText: string;
  tokenSlug: string;
  tokenSymbol: string;
};

function FundingNotice({ block }: OwnProps) {
  const { startTokenTrade } = getActions();
  const lang = useLang();

  // The trade modal hides while the purchase is open and comes back with the same form after it
  const handleBuyClick = useLastCallback(() => {
    startTokenTrade({ tokenSlug: block.tokenSlug, direction: 'buy' });
  });

  return (
    <TradeNotice
      title={block.title}
      message={block.description}
      actionTitle={lang('Buy %token%', { token: block.tokenSymbol })}
      className={styles.notice}
      onActionClick={handleBuyClick}
    />
  );
}

export default memo(FundingNotice);

/**
 * What the account lacks on Arbitrum to pay for the trade: USDC for the deposit, ETH for the network fee, or both.
 * The notice shows before any amount is typed, so the user can top up first.
 */
export function getPerpsFundingBlock(
  lang: LangFn,
  funding: ApiPerpsFundingRequirements,
  isEdit: boolean,
): PerpsFundingBlock | undefined {
  if (!funding.needsUsdc && !funding.needsEth) return undefined;

  // A wallet without ETH pays the network fee in USDC, so buying only the deposit would leave the fee unpaid
  const minUsdc = formatPerpsRequiredAmount(Big(funding.requiredUsdc).plus(funding.requiredGasUsdc).toFixed());
  const feeEth = formatPerpsRequiredAmount(funding.requiredEth);

  if (funding.needsUsdc && funding.needsEth) {
    return {
      title: lang('PerpsFundingMissingTitle'),
      description: lang('$perps_funding_missing', { minUSDC: minUsdc, feeETH: feeEth }) as string,
      buttonText: lang('Not Enough Funds'),
      tokenSlug: ARBITRUM_USDC_MAINNET.slug,
      tokenSymbol: ARBITRUM_USDC_MAINNET.symbol,
    };
  }

  if (funding.needsUsdc) {
    return {
      title: lang('$not_enough_symbol_lowercase', { symbol: ARBITRUM_USDC_MAINNET.symbol }) as string,
      description: lang(isEdit ? '$perps_funding_usdc_increase' : '$perps_funding_usdc', {
        minUSDC: minUsdc,
      }) as string,
      buttonText: lang('Not Enough %symbol%', { symbol: ARBITRUM_USDC_MAINNET.symbol }) as string,
      tokenSlug: ARBITRUM_USDC_MAINNET.slug,
      tokenSymbol: ARBITRUM_USDC_MAINNET.symbol,
    };
  }

  return {
    title: lang('PerpsFundingGasTitle'),
    description: lang('$perps_funding_gas', {
      feeETH: feeEth,
      feeFiat: formatPerpsMoney(funding.requiredEthUsd),
    }) as string,
    buttonText: lang('Not Enough %symbol%', { symbol: ARBITRUM.symbol }) as string,
    tokenSlug: ARBITRUM.slug,
    tokenSymbol: ARBITRUM.symbol,
  };
}
