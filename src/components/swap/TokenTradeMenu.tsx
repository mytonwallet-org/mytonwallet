import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import getTestId from '../../util/getTestId';

import useLang from '../../hooks/useLang';

import TradeHeaderMenu from './TradeHeaderMenu';
import TradeMenuRow from './TradeMenuRow';

import styles from './TokenTrade.module.scss';

type TokenTradeDetailsMode = 'card' | 'dex' | 'cex';

interface OwnProps {
  mode: TokenTradeDetailsMode;
  exchangeRate?: string;
  priceImpact?: number;
  isPriceImpactError?: boolean;
  minimumReceived?: string;
  slippage: number;
  providerName?: string;
  onProviderInfoClick: NoneToVoidFunction;
  onSlippageClick: NoneToVoidFunction;
}

/** The details button of the Buy / Sell screen together with the menu it opens */
function TokenTradeMenu({
  mode,
  exchangeRate,
  priceImpact,
  isPriceImpactError,
  minimumReceived,
  slippage,
  providerName,
  onProviderInfoClick,
  onSlippageClick,
}: OwnProps) {
  const lang = useLang();

  function renderContent(closeMenu: NoneToVoidFunction) {
    function handleSlippageClick() {
      closeMenu();
      onSlippageClick();
    }

    function handleProviderInfoClick() {
      closeMenu();
      onProviderInfoClick();
    }

    const noDataText = lang('No Data');

    return (
      <>
        <TradeMenuRow title={lang('Exchange Rate')} value={exchangeRate} emptyValue={noDataText} />
        {mode === 'cex' && (
          <TradeMenuRow
            title={lang('Cross-chain Provider')}
            value={providerName}
            emptyValue={noDataText}
            titleAddon={renderProviderHelp(handleProviderInfoClick)}
          />
        )}
        {mode === 'dex' && (
          <>
            <TradeMenuRow
              title={lang('Price Impact')}
              value={priceImpact !== undefined ? `${priceImpact}%` : undefined}
              emptyValue={noDataText}
              hint={renderHint([lang('$swap_price_impact_tooltip1'), lang('$swap_price_impact_tooltip2')])}
              isError={isPriceImpactError}
            />
            <TradeMenuRow
              title={lang('Minimum Received')}
              value={minimumReceived}
              emptyValue={noDataText}
              hint={renderHint([lang('$swap_minimum_received_tooltip1'), lang('$swap_minimum_received_tooltip2')])}
            />
            <TradeMenuRow
              title={lang('Slippage')}
              value={`${slippage}%`}
              emptyValue={noDataText}
              hint={renderHint([lang('$swap_slippage_tooltip1'), lang('$swap_slippage_tooltip2')])}
              onClick={handleSlippageClick}
            />
          </>
        )}
      </>
    );
  }

  function renderHint(messages: string[]) {
    return messages.map((message) => <span>{message}</span>);
  }

  function renderProviderHelp(onClick: NoneToVoidFunction) {
    return (
      <button
        type="button"
        className={styles.menuProviderHelp}
        aria-label={lang('Cross-chain Provider')}
        disabled={!providerName}
        onClick={onClick}
      >
        <i className={buildClassName(styles.menuTooltipIcon, 'icon-question')} aria-hidden />
      </button>
    );
  }

  return (
    <TradeHeaderMenu
      ariaLabel={lang('Swap Details')}
      icon={mode === 'card' ? 'icon-info' : 'icon-menu-params'}
      testId={getTestId('token_trade_settings')}
    >
      {renderContent}
    </TradeHeaderMenu>
  );
}

export default memo(TokenTradeMenu);
