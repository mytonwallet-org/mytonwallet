import React, { memo, useEffect } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import { ANIMATION_LEVEL_MIN } from '../../config';
import { selectCurrentAccountState, selectMycoin } from '../../global/selectors';

import useLang from '../../hooks/useLang';
import useShowTransition from '../../hooks/useShowTransition';

import ClockIcon from '../ui/ClockIcon';

import styles from './MintCardButton.module.scss';

interface StateProps {
  isCardMinting?: boolean;
  hasCardsInfo?: boolean;
  isMycoinLoaded: boolean;
  noAnimation?: boolean;
}

function MintCardButton({
  isCardMinting,
  hasCardsInfo,
  isMycoinLoaded,
  noAnimation,
}: StateProps) {
  const { loadMycoin, openMintCardModal } = getActions();

  const lang = useLang();
  const canRender = Boolean(hasCardsInfo || isCardMinting);
  const {
    shouldRender: shouldRenderMintCardsButton,
    ref: mintCardsButtonRef,
  } = useShowTransition<HTMLButtonElement>({
    isOpen: canRender,
    withShouldRender: true,
  });

  useEffect(() => {
    if (isMycoinLoaded || !canRender) return;

    loadMycoin();
  }, [canRender, isMycoinLoaded]);

  if (!shouldRenderMintCardsButton) return undefined;

  return (
    <button
      ref={mintCardsButtonRef}
      type="button"
      className={styles.button}
      aria-label={lang('Mint Cards')}
      title={lang('Mint Cards')}
      onClick={() => openMintCardModal()}
    >
      <i className={isCardMinting ? 'icon-magic-wand-loading' : 'icon-magic-wand'} aria-hidden />
      {isCardMinting && <ClockIcon className={styles.icon} noAnimation={noAnimation} />}
    </button>
  );
}

export default memo(withGlobal((global): StateProps => {
  const accountState = selectCurrentAccountState(global);
  const { config } = selectCurrentAccountState(global) || {};
  const animationLevel = global.settings.animationLevel;
  const mycoin = selectMycoin(global);

  return {
    hasCardsInfo: Boolean(config?.cardsInfo),
    isCardMinting: accountState?.isCardMinting,
    isMycoinLoaded: Boolean(mycoin),
    noAnimation: animationLevel === ANIMATION_LEVEL_MIN,
  };
})(MintCardButton));
