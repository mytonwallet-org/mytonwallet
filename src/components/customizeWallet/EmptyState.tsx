import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useLang from '../../hooks/useLang';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';

import styles from './CustomizeWalletModal.module.scss';

interface OwnProps {
  onGetFirstCard: NoneToVoidFunction;
}

function EmptyState({ onGetFirstCard }: OwnProps) {
  const lang = useLang();

  return (
    <div className={styles.section}>
      <div className={styles.sectionSelectCard}>
        <div className={styles.icon}>
          <i className={buildClassName('icon-cards-empty', styles.iconImage)} aria-hidden />
        </div>
        <AnimatedIconWithPreview
          play
          tgsUrl={ANIMATED_STICKERS_PATHS.noData}
          previewUrl={ANIMATED_STICKERS_PATHS.noDataPreview}
          noLoop={false}
          nonInteractive
        />
        <h3 className={styles.emptyTitle}>
          {lang('You don\'t have any cards to customize yet')}
        </h3>
        <p className={styles.helperTextInside}>
          {lang(
            'MyTonWallet Cards can be installed for wallets and displayed on the home screen and in the wallet list.',
          )}
        </p>
      </div>

      <div className={styles.buttonContainer}>
        <div className={styles.getMoreButton} onClick={onGetFirstCard} role="button" tabIndex={0}>
          <span className={styles.getMoreText}>{lang('Get First Card')}</span>
        </div>
        <p className={styles.helperTextOutside}>
          {lang('Browse MyTonWallet Cards available for purchase.')}
        </p>
      </div>
    </div>
  );
}

export default memo(EmptyState);
