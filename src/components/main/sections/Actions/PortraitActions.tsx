import React, { type ElementRef, memo } from '../../../../lib/teact/teact';
import { getActions } from '../../../../global';

import type { StakingStateStatus } from '../../../../util/staking';

import { IS_CORE_WALLET } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
import { vibrate } from '../../../../util/haptics';
import { handleSendMenuItemClick, SEND_CONTEXT_MENU_ITEMS } from './helpers/sendMenu';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import Button from '../../../ui/Button';
import WithContextMenu from '../../../ui/WithContextMenu';
import { STAKING_TAB_TEXT_VARIANTS } from './LandscapeActions';

import styles from './PortraitActions.module.scss';

interface OwnProps {
  isTestnet?: boolean;
  isLedger?: boolean;
  stakingStatus: StakingStateStatus;
  isSwapDisabled?: boolean;
  isStakingDisabled?: boolean;
  isOnRampDisabled?: boolean;
  isOffRampDisabled?: boolean;
  containerRef: ElementRef<HTMLDivElement>;
  onEarnClick: NoneToVoidFunction;
}

function PortraitActions({
  isTestnet,
  stakingStatus,
  isStakingDisabled,
  isSwapDisabled,
  isOnRampDisabled,
  isOffRampDisabled,
  containerRef,
  onEarnClick,
}: OwnProps) {
  const {
    startTransfer, startSwap, openReceiveModal,
  } = getActions();

  const lang = useLang();

  const isOnRampAllowed = !isTestnet && !isOnRampDisabled;
  const addBuyButtonName = IS_CORE_WALLET
    ? lang('Receive')
    : (!isSwapDisabled || isOnRampAllowed
      ? (lang.code === 'en'
        ? (<span className={styles.name}>{lang('Add')}<span className={styles.divider}>/</span>{lang('Buy')}</span>)
        : lang('Add / Buy')
      )
      : lang('Add')
    );
  const sendButtonName = IS_CORE_WALLET || isOffRampDisabled || lang.code !== 'en'
    ? lang('Send')
    : <span className={styles.name}>{lang('Send')}<span className={styles.divider}>/</span>{lang('Sell')}</span>;

  const handleStartSwap = useLastCallback(() => {
    void vibrate();

    startSwap();
  });

  const handleStartTransfer = useLastCallback(() => {
    void vibrate();

    startTransfer({ isPortrait: true });
  });

  const handleAddBuyClick = useLastCallback(() => {
    void vibrate();

    openReceiveModal();
  });

  const handleEarnClick = useLastCallback(() => {
    void vibrate();

    onEarnClick();
  });

  return (
    <div className={styles.container}>
      <div className={styles.buttons}>
        <Button
          isSimple
          className={styles.button}
          onClick={handleAddBuyClick}
        >
          <i className={buildClassName(styles.buttonIcon, 'icon-action-add')} aria-hidden />
          {addBuyButtonName}
        </Button>
        <WithContextMenu
          rootRef={containerRef}
          items={SEND_CONTEXT_MENU_ITEMS}
          menuClassName={styles.menu}
          onItemClick={handleSendMenuItemClick}
        >
          {(buttonProps, isMenuOpen) => (
            <Button
              {...buttonProps}
              isSimple
              className={buildClassName(styles.button, isMenuOpen && styles.buttonActive)}
              onClick={handleStartTransfer}
              ref={buttonProps.ref as ElementRef<HTMLButtonElement>}
            >
              <i className={buildClassName(styles.buttonIcon, 'icon-action-send')} aria-hidden />
              {sendButtonName}
            </Button>
          )}
        </WithContextMenu>
        {!isSwapDisabled && (
          <Button
            isSimple
            className={styles.button}
            onClick={handleStartSwap}
          >
            <i className={buildClassName(styles.buttonIcon, 'icon-action-swap')} aria-hidden />
            {lang('Swap')}
          </Button>
        )}
        {!isStakingDisabled && (
          <Button
            isSimple
            className={buildClassName(styles.button, stakingStatus !== 'inactive' && styles.button_purple)}
            onClick={handleEarnClick}
          >
            <i className={buildClassName(styles.buttonIcon, 'icon-action-earn')} aria-hidden />
            {lang(STAKING_TAB_TEXT_VARIANTS[stakingStatus])}
          </Button>
        )}
      </div>
    </div>
  );
}

export default memo(PortraitActions);
