import React, {
  memo, useState,
} from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiBaseCurrency } from '../../api/types';
import { SettingsState, type UserToken } from '../../global/types';

import { bigintMultiplyToNumber } from '../../util/bigint';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { stopEvent } from '../../util/domEvents';
import { formatCurrency, getShortCurrencySymbol } from '../../util/formatNumber';
import getDeterministicRandom from '../../util/getDeterministicRandom';
import getTokenName from '../main/helpers/getTokenName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TokenIcon from '../common/TokenIcon';
import TokenTitle from '../common/TokenTitle';
import DeleteTokenModal from '../main/modals/DeleteTokenModal';
import AnimatedCounter from '../ui/AnimatedCounter';
import SensitiveData from '../ui/SensitiveData';
import Switcher from '../ui/Switcher';

import styles from './Settings.module.scss';

interface OwnProps {
  tokens?: UserToken[];
  pinnedSlugs?: string[];
  baseCurrency: ApiBaseCurrency;
  withChainIcon?: boolean;
  isSensitiveDataHidden?: true;
}

function SettingsTokens({
  tokens,
  baseCurrency,
  withChainIcon,
  isSensitiveDataHidden,
  pinnedSlugs = [],
}: OwnProps) {
  const {
    openSettingsWithState,
    toggleTokenVisibility,
  } = getActions();
  const lang = useLang();
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);

  const [tokenToDelete, setTokenToDelete] = useState<UserToken | undefined>();

  const handleOpenAddTokenPage = useLastCallback(() => {
    openSettingsWithState({ state: SettingsState.SelectTokenList });
  });

  const handleOpenAddTokenPageKeyDown = useLastCallback((e: React.KeyboardEvent) => {
    if (e.code === 'Enter' || e.code === 'Space') {
      stopEvent(e);
      handleOpenAddTokenPage();
    }
  });

  const handleTokenVisibility = useLastCallback((
    token: UserToken,
    e: React.MouseEvent | React.TouchEvent | React.KeyboardEvent,
  ) => {
    stopEvent(e);
    toggleTokenVisibility({ slug: token.slug, shouldShow: Boolean(token.isDisabled) });
  });

  const handleTokenKeyDown = useLastCallback((token: UserToken, e: React.KeyboardEvent) => {
    if (e.code === 'Enter' || e.code === 'Space') {
      handleTokenVisibility(token, e);
    }
  });

  const handleDeleteToken = useLastCallback((token: UserToken, e: React.MouseEvent<HTMLSpanElement>) => {
    e.stopPropagation();
    setTokenToDelete(token);
  });

  function renderToken(token: UserToken, index: number) {
    const {
      symbol, amount, price, slug, isDisabled,
    } = token;

    const totalAmount = bigintMultiplyToNumber(amount, price);
    const isPinned = pinnedSlugs.includes(slug);
    const tokenName = getTokenName(lang, token);

    const isDeleteButtonVisible = amount === 0n;

    const ariaLabel = isDisabled
      ? `${lang('Show')} ${tokenName}`
      : `${lang('Hide')} ${tokenName}`;

    return (
      <div
        key={slug}
        tabIndex={0}
        role="button"
        aria-label={ariaLabel}
        aria-pressed={!isDisabled}
        className={buildClassName(styles.item, styles.item_token)}
        onKeyDown={(e) => handleTokenKeyDown(token, e)}
        onClick={(e) => handleTokenVisibility(token, e)}
      >
        <TokenIcon token={token} withChainIcon={withChainIcon} />
        <div className={styles.tokenInfo}>
          <TokenTitle
            tokenName={tokenName}
            tokenLabel={token.label}
            isPinned={isPinned}
          />
          <div className={styles.tokenDescription}>
            <SensitiveData
              isActive={isSensitiveDataHidden}
              cols={getDeterministicRandom(4, 9, index)}
              rows={2}
              cellSize={8}
              contentClassName={styles.tokenAmount}
            >
              <AnimatedCounter text={formatCurrency(toDecimal(totalAmount, token.decimals, true), shortBaseSymbol)} />
              <i className={styles.dot} aria-hidden />
              <AnimatedCounter text={formatCurrency(toDecimal(amount, token.decimals), symbol)} />
            </SensitiveData>
            {isDeleteButtonVisible && (
              <>
                <i className={styles.dot} aria-hidden />
                <span className={styles.deleteText} onClick={(e) => handleDeleteToken(token, e)}>
                  {lang('Delete')}
                </span>
              </>
            )}
          </div>
        </div>
        <Switcher
          className={styles.menuSwitcher}
          checked={!isDisabled}
        />
      </div>
    );
  }

  return (
    <>
      <p className={styles.blockTitle}>{lang('My Assets')}</p>
      <div className={styles.settingsBlock}>
        <div
          role="button"
          tabIndex={0}
          className={buildClassName(styles.item, styles.item_small)}
          onClick={handleOpenAddTokenPage}
          onKeyDown={handleOpenAddTokenPageKeyDown}
        >
          {lang('Add Token')}
          <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
        </div>

        {tokens?.map(renderToken)}
      </div>

      <DeleteTokenModal token={tokenToDelete} />
    </>
  );
}

export default memo(SettingsTokens);
