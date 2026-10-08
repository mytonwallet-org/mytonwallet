import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useRef, useState } from '../../lib/teact/teact';

import type { IAnchorPosition } from '../../global/types';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import IconWithTooltip from '../ui/IconWithTooltip';
import Menu from '../ui/Menu';

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

  const buttonRef = useRef<HTMLButtonElement>();
  const menuRef = useRef<HTMLDivElement>();
  const [anchor, setAnchor] = useState<IAnchorPosition | undefined>();
  const isOpen = Boolean(anchor);

  const getTriggerElement = useLastCallback(() => buttonRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback(() => ({ withPortal: true }));
  const closeMenu = useLastCallback(() => setAnchor(undefined));

  const handleButtonClick = useLastCallback(() => {
    if (isOpen) {
      closeMenu();
      return;
    }

    const { left, right, y, height } = buttonRef.current!.getBoundingClientRect();
    // RTL: mirror the anchor edge
    setAnchor({ x: lang.isRtl ? left : right, y: y + height });
  });

  const handleSlippageClick = useLastCallback(() => {
    closeMenu();
    onSlippageClick();
  });

  const handleProviderInfoClick = useLastCallback(() => {
    closeMenu();
    onProviderInfoClick();
  });

  function renderTooltip(messages: string[]) {
    return (
      <IconWithTooltip
        message={messages.map((message) => <span>{message}</span>)}
        size="small"
        iconClassName={styles.menuTooltipIcon}
        tooltipClassName={styles.menuTooltip}
      />
    );
  }

  function renderRow(title: string, value: TeactNode | undefined, help?: TeactNode, isError?: boolean) {
    return (
      <div className={styles.menuRow}>
        <span className={buildClassName(styles.menuRowTitle, isError && styles.menuRowError)}>
          {title}
          {help}
        </span>
        <span className={buildClassName(styles.menuRowValue, isError && styles.menuRowError)}>
          {value ?? lang('No Data')}
        </span>
      </div>
    );
  }

  function renderProviderHelp() {
    return (
      <button
        type="button"
        className={styles.menuProviderHelp}
        aria-label={lang('Cross-chain Provider')}
        disabled={!providerName}
        onClick={handleProviderInfoClick}
      >
        <i className={buildClassName(styles.menuTooltipIcon, 'icon-question')} aria-hidden />
      </button>
    );
  }

  return (
    <>
      <Button
        ref={buttonRef}
        isRound
        className={styles.headerButton}
        ariaLabel={lang('Swap Details')}
        onClick={handleButtonClick}
      >
        <i
          className={buildClassName(styles.headerIcon, mode === 'card' ? 'icon-info' : 'icon-menu-params')}
          aria-hidden
        />
      </Button>
      <Menu
        menuRef={menuRef}
        isOpen={isOpen}
        type="dropdown"
        withPortal
        bubbleClassName={styles.menuBubble}
        anchor={anchor}
        getTriggerElement={getTriggerElement}
        getRootElement={getRootElement}
        getMenuElement={getMenuElement}
        getLayout={getLayout}
        onClose={closeMenu}
      >
        {renderRow(lang('Exchange Rate'), exchangeRate)}
        {mode === 'cex' && renderRow(lang('Cross-chain Provider'), providerName, renderProviderHelp())}
        {mode === 'dex' && (
          <>
            {renderRow(
              lang('Price Impact'),
              priceImpact !== undefined ? `${priceImpact}%` : undefined,
              renderTooltip([lang('$swap_price_impact_tooltip1'), lang('$swap_price_impact_tooltip2')]),
              isPriceImpactError,
            )}
            {renderRow(
              lang('Minimum Received'),
              minimumReceived,
              renderTooltip([lang('$swap_minimum_received_tooltip1'), lang('$swap_minimum_received_tooltip2')]),
            )}
            <button
              type="button"
              className={buildClassName(styles.menuRow, styles.menuRowButton)}
              onClick={handleSlippageClick}
            >
              <span className={styles.menuRowTitle}>
                {lang('Slippage')}
                {renderTooltip([lang('$swap_slippage_tooltip1'), lang('$swap_slippage_tooltip2')])}
              </span>
              <span className={styles.menuRowValue}>{slippage}%</span>
              <i className={buildClassName(styles.menuRowChevron, 'icon-chevron-right')} aria-hidden />
            </button>
          </>
        )}
      </Menu>
    </>
  );
}

export default memo(TokenTradeMenu);
