import React, { type ElementRef, memo } from '../../../../lib/teact/teact';

import { ANIMATED_STICKER_SMALL_SIZE_PX } from '../../../../config';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';
import { AccountTab } from './constants';

import useLang from '../../../../hooks/useLang';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';

import styles from './AccountSelectorModal.module.scss';

interface OwnProps {
  isActive: boolean;
  ref: ElementRef<HTMLDivElement>;
  tab: AccountTab;
}

function AccountsEmptyState({ isActive, ref, tab }: OwnProps) {
  const lang = useLang();

  const title = tab === AccountTab.Ledger
    ? 'No Ledger wallets yet'
    : (tab === AccountTab.View
      ? 'No view wallets yet'
      : 'You don’t have any wallets yet');
  const description = tab === AccountTab.View
    ? 'Add the first one to track balances and activity for any address.'
    : 'Add your first one to begin.';

  return (
    <div ref={ref} className={styles.emptyState}>
      <AnimatedIconWithPreview
        play={isActive}
        tgsUrl={ANIMATED_STICKERS_PATHS.noData}
        previewUrl={ANIMATED_STICKERS_PATHS.noDataPreview}
        size={ANIMATED_STICKER_SMALL_SIZE_PX}
        className={styles.sticker}
        noLoop={false}
        nonInteractive
      />
      <div className={styles.emptyStateTitle}>{lang(title)}</div>
      <div className={styles.emptyStateDescription}>{lang(description)}</div>
    </div>
  );
}

export default memo(AccountsEmptyState);
