import React, { memo } from '../../lib/teact/teact';

import type { MarketSection } from './helpers/buildMarketSections';

import buildClassName from '../../util/buildClassName';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useScrolledState from '../../hooks/useScrolledState';

import Button from '../ui/Button';
import TokenRow from './TokenRow';

import styles from './Market.module.scss';

interface OwnProps {
  section: MarketSection;
  onTokenClick: (slug: string) => void;
  onBackClick: NoneToVoidFunction;
}

function SectionList({ section, onTokenClick, onBackClick }: OwnProps) {
  const lang = useLang();
  const { isPortrait } = useDeviceScreen();
  const { isScrolled, handleScroll } = useScrolledState();

  return (
    <div
      className={buildClassName(styles.slide, styles.listSlide, styles.panel, 'custom-scroll')}
      onScroll={handleScroll}
    >
      <div className={buildClassName(
        styles.listHeader,
        isPortrait && 'with-notch-on-scroll',
        isScrolled && 'is-scrolled',
      )}
      >
        <Button className={styles.backButton} isSimple isText onClick={onBackClick}>
          <i className={buildClassName(styles.backIcon, 'icon-chevron-left')} aria-hidden />
          <span>{lang('Back')}</span>
        </Button>

        <h3 className={styles.listTitle}>{section.title}</h3>
      </div>

      <div className={buildClassName(styles.card, styles.rows, styles.listCard)}>
        {section.tokens.map((token) => (
          <TokenRow key={token.slug} token={token} onClick={onTokenClick} />
        ))}
      </div>
    </div>
  );
}

export default memo(SectionList);
