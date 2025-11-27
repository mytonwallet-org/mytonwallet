import React, { memo } from '../../../../lib/teact/teact';

import type { ApiChain } from '../../../../api/types';

import { ANIMATED_STICKER_BIG_SIZE_PX, ANIMATED_STICKER_SMALL_SIZE_PX } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
import { getChainTitle, getOrderedAccountChains } from '../../../../util/chain';
import { formatEnumeration } from '../../../../util/langProvider';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';

import useLang from '../../../../hooks/useLang';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';

import styles from './NewWalletGreeting.module.scss';

interface Props {
  isActive?: boolean;
  accountChains: Partial<Record<ApiChain, unknown>>;
  mode: 'panel' | 'emptyList';
}

function NewWalletGreeting({ isActive, accountChains, mode }: Props) {
  const lang = useLang();
  const chainTitles = getOrderedAccountChains(accountChains).map(getChainTitle);

  return (
    <div className={buildClassName(styles.container, styles[mode])}>
      <AnimatedIconWithPreview
        play={isActive}
        tgsUrl={ANIMATED_STICKERS_PATHS.hello}
        previewUrl={ANIMATED_STICKERS_PATHS.helloPreview}
        nonInteractive
        noLoop={false}
        size={mode === 'emptyList' ? ANIMATED_STICKER_BIG_SIZE_PX : ANIMATED_STICKER_SMALL_SIZE_PX}
      />

      <div className={styles.text}>
        <p className={styles.header}>
          {lang(chainTitles.length > 1
            ? 'You have just created a new multichain wallet'
            : 'You have just created a new wallet')}
        </p>
        <p className={styles.description}>
          {chainTitles.length > 1
            ? lang(
              'Now you can transfer tokens from your %chains% wallets.',
              { chains: formatEnumeration(lang, chainTitles, 'and') },
            )
            : lang('You can now transfer your tokens from another wallet or exchange.')}
        </p>
      </div>
    </div>
  );
}

export default memo(NewWalletGreeting);
