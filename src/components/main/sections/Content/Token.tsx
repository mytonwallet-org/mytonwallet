import React, { type ElementRef, memo, useMemo, useRef } from '../../../../lib/teact/teact';

import type { ApiBaseCurrency, ApiStakingState, ApiYieldType } from '../../../../api/types';
import type { AppTheme, UserToken } from '../../../../global/types';
import type { Layout } from '../../../../hooks/useMenuPosition';
import type { StakingStateStatus } from '../../../../util/staking';

import { ANIMATED_STICKER_TINY_ICON_PX, IS_CORE_WALLET } from '../../../../config';
import { Big } from '../../../../lib/big.js';
import buildClassName from '../../../../util/buildClassName';
import { calcChangeValue } from '../../../../util/calcChangeValue';
import { DAY, formatFullDay } from '../../../../util/dateFormat';
import { toDecimal } from '../../../../util/decimals';
import { formatCurrency, getShortCurrencySymbol } from '../../../../util/formatNumber';
import getPseudoRandomNumber from '../../../../util/getPseudoRandomNumber';
import { round } from '../../../../util/round';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';
import getTokenName from '../../helpers/getTokenName';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useShowTransition from '../../../../hooks/useShowTransition';
import useTokenContextMenu from './hooks/useTokenContextMenu';

import TokenIcon from '../../../common/TokenIcon';
import AnimatedCounter from '../../../ui/AnimatedCounter';
import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import Button from '../../../ui/Button';
import DropdownMenu from '../../../ui/DropdownMenu';
import MenuBackdrop from '../../../ui/MenuBackdrop';
import SensitiveData from '../../../ui/SensitiveData';

import styles from './Token.module.scss';

interface OwnProps {
  ref?: ElementRef<HTMLButtonElement>;
  token: UserToken;
  // Undefined means that it's not a staked token
  stakingStatus?: StakingStateStatus;
  stakingState?: ApiStakingState;
  vestingStatus?: 'frozen' | 'readyToUnfreeze';
  unfreezeEndDate?: number;
  amount?: string;
  isInvestorView?: boolean;
  classNames?: string;
  style?: string;
  annualYield?: number;
  yieldType?: ApiYieldType;
  isActive?: boolean;
  baseCurrency: ApiBaseCurrency;
  appTheme: AppTheme;
  withChainIcon?: boolean;
  withContextMenu?: boolean;
  isSensitiveDataHidden?: true;
  isSwapDisabled?: boolean;
  isStakingAvailable?: boolean;
  isViewMode?: boolean;
  isPinned?: boolean;
  withPinTransition?: boolean;
  onClick: (slug: string) => void;
}

const UNFREEZE_DANGER_DURATION = 7 * DAY;
const CONTEXT_MENU_VERTICAL_SHIFT_PX = 4;
export const OPEN_CONTEXT_MENU_CLASS_NAME = 'open-context-menu';

function Token({
  ref,
  token,
  amount,
  stakingStatus,
  stakingState,
  vestingStatus,
  unfreezeEndDate,
  annualYield,
  isInvestorView,
  classNames,
  style,
  appTheme,
  isActive,
  baseCurrency,
  withChainIcon,
  withContextMenu,
  isSensitiveDataHidden,
  isStakingAvailable,
  isSwapDisabled,
  isViewMode,
  isPinned,
  withPinTransition,
  yieldType,
  onClick,
}: OwnProps) {
  const {
    symbol,
    slug,
    amount: tokenAmount,
    price,
    change24h: change,
    decimals,
    label,
  } = token;

  const lang = useLang();
  const { isPortrait } = useDeviceScreen();

  let buttonRef = useRef<HTMLButtonElement>();
  const menuRef = useRef<HTMLDivElement>();
  const isVesting = Boolean(vestingStatus?.length);
  const renderedAmount = amount ?? toDecimal(tokenAmount, decimals, true);
  const value = Big(renderedAmount).mul(price).toString();
  const changeClassName = change > 0 ? styles.change_up : change < 0 ? styles.change_down : undefined;
  const changeValue = Math.abs(round(calcChangeValue(Number(value), change), 4));
  const changePercent = Math.abs(round(change * 100, 2));
  const withYield = !IS_CORE_WALLET && annualYield !== undefined;
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);
  const withLabel = Boolean(!isVesting && label);
  const stakingId = stakingState?.id;
  const name = getTokenName(lang, token);
  const withChainIconRendered = withChainIcon && !stakingId;
  const amountCols = useMemo(() => getPseudoRandomNumber(4, 12, name), [name]);
  const fiatAmountCols = 5 + (amountCols % 6);
  if (ref) {
    buttonRef = ref;
  }

  const {
    shouldRender: shouldRenderYield,
    ref: yieldRef,
  } = useShowTransition<HTMLSpanElement>({
    isOpen: withYield,
    withShouldRender: true,
  });

  const {
    shouldRender: shouldRenderPin,
    ref: pinRef,
  } = useShowTransition<HTMLElement>({
    isOpen: isPinned,
    withShouldRender: true,
  });

  const handleClick = useLastCallback(() => {
    onClick(slug);
  });

  const getTriggerElement = useLastCallback(() => buttonRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback((): Layout => ({
    withPortal: true,
    doNotCoverTrigger: isPortrait,
    // The shift is needed to prevent the mouse cursor from highlighting the first menu item
    topShiftY: !isPortrait ? CONTEXT_MENU_VERTICAL_SHIFT_PX : undefined,
    preferredPositionX: 'left',
  }));

  const {
    isContextMenuOpen,
    isContextMenuShown,
    contextMenuAnchor,
    items,
    isBackdropRendered,
    handleBeforeContextMenu,
    handleContextMenu,
    handleContextMenuClose,
    handleContextMenuHide,
    handleMenuItemSelect,
  } = useTokenContextMenu(buttonRef, {
    token,
    isPortrait,
    withContextMenu,
    isStakingAvailable,
    isSwapDisabled,
    isViewMode,
    stakingState,
    isPinned,
  });

  function renderYield() {
    const labelClassName = buildClassName(
      styles.label,
      styles.apyLabel,
      stakingStatus && styles.apyLabel_staked,
    );

    return (
      <span ref={yieldRef} className={labelClassName}>
        {stakingStatus ? '' : `${yieldType} `}{round(annualYield ?? 0, 2)}%
      </span>
    );
  }

  function renderChangeIcon() {
    if (change === 0) {
      return undefined;
    }

    return (
      <i
        className={buildClassName(styles.iconArrow, change > 0 ? 'icon-arrow-up' : 'icon-arrow-down')}
        aria-hidden
      />
    );
  }

  function renderStakingIcon() {
    if (stakingStatus === 'active') {
      return (
        <i
          className={buildClassName('icon-percent', styles.percent)}
          aria-hidden
        />
      );
    }

    if (stakingStatus === 'readyToClaim') {
      return (
        <i
          className={buildClassName('icon-check-alt', styles.readyToClaim)}
          aria-hidden
        />
      );
    }

    return (
      <AnimatedIconWithPreview
        play
        size={ANIMATED_STICKER_TINY_ICON_PX}
        className={styles.percent}
        nonInteractive
        noLoop={false}
        tgsUrl={ANIMATED_STICKERS_PATHS[appTheme].iconClockPurple}
        previewUrl={ANIMATED_STICKERS_PATHS[appTheme].preview.iconClockPurple}
      />
    );
  }

  const fullClassName = buildClassName(
    styles.button,
    isActive && styles.active,
    isContextMenuOpen && OPEN_CONTEXT_MENU_CLASS_NAME,
  );

  function renderInvestorView() {
    return (
      <Button
        ref={buttonRef}
        isSimple
        className={fullClassName}
        onMouseDown={handleBeforeContextMenu}
        onContextMenu={handleContextMenu}
        onClick={handleClick}
      >
        <TokenIcon
          size="large"
          token={token}
          withChainIcon={withChainIconRendered}
          className={styles.tokenIcon}
        >
          <>
            {stakingStatus && renderStakingIcon()}
            {vestingStatus && (
              <i
                className={buildClassName(vestingStatus === 'frozen' ? 'icon-snow' : 'icon-fire', styles.vestingIcon)}
                aria-hidden
              />
            )}
          </>
        </TokenIcon>
        <div className={styles.primaryCell}>
          <div className={styles.name}>
            <span className={styles.nameText}>{name}</span>
            {shouldRenderYield && renderYield()}
            {withLabel && (
              <span className={buildClassName(styles.label, styles.chainLabel)}>{label}</span>
            )}
          </div>
          <div className={styles.subtitle}>
            <SensitiveData
              isActive={isSensitiveDataHidden}
              cols={fiatAmountCols}
              rows={2}
              cellSize={8}
            >
              <AnimatedCounter text={formatCurrency(renderedAmount, symbol)} />
            </SensitiveData>
            <i className={styles.dot} aria-hidden />
            <AnimatedCounter text={formatCurrency(price, shortBaseSymbol, undefined, true)} />
          </div>
        </div>
        <div className={styles.secondaryCell}>
          <SensitiveData
            isActive={isSensitiveDataHidden}
            cols={amountCols}
            rows={2}
            cellSize={8}
            align="right"
            className={buildClassName(
              styles.secondaryValue,
              stakingStatus && styles.secondaryValue_staked,
              isVesting && styles.secondaryValue_vesting,
              isVesting && vestingStatus === 'readyToUnfreeze' && styles.secondaryValue_vestingUnfreeze,
            )}
          >
            <AnimatedCounter text={formatCurrency(value, shortBaseSymbol)} />
          </SensitiveData>
          {unfreezeEndDate ? (
            <div
              className={buildClassName(
                styles.change,
                (unfreezeEndDate - Date.now() < UNFREEZE_DANGER_DURATION) && styles.change_down,
              )}
            >
              {lang('Unfreeze')}
              {' '}
              {lang('until %date%', { date: `${formatFullDay(lang.code!, unfreezeEndDate)}` })}
            </div>
          ) : (
            <SensitiveData
              isActive={isSensitiveDataHidden}
              cols={fiatAmountCols}
              rows={2}
              cellSize={8}
              align="right"
              className={buildClassName(styles.change, changeClassName)}
            >
              {renderChangeIcon()}<AnimatedCounter text={String(changePercent)} />%
              <i className={styles.dot} aria-hidden />
              <AnimatedCounter text={formatCurrency(changeValue, shortBaseSymbol, undefined, true)} />
            </SensitiveData>
          )}
        </div>
      </Button>
    );
  }

  function renderDefaultView() {
    const totalAmount = Big(renderedAmount).mul(price);
    const canRenderYield = annualYield !== undefined;

    return (
      <Button
        ref={buttonRef}
        isSimple
        className={fullClassName}
        onMouseDown={handleBeforeContextMenu}
        onContextMenu={handleContextMenu}
        onClick={handleClick}
      >
        <TokenIcon
          token={token}
          size="large"
          withChainIcon={withChainIconRendered}
          className={styles.tokenIcon}
        >
          <>
            {stakingStatus && renderStakingIcon()}
            {vestingStatus && (
              <i
                className={buildClassName(vestingStatus === 'frozen' ? 'icon-snow' : 'icon-fire', styles.vestingIcon)}
                aria-hidden
              />
            )}
          </>
        </TokenIcon>
        <div className={styles.primaryCell}>
          <div className={styles.name}>
            {shouldRenderPin && (
              <i
                ref={pinRef}
                className={buildClassName(
                  styles.pinIcon,
                  'icon-pin',
                  withPinTransition && styles.pinIcon_withTransition,
                )}
                aria-hidden
              />
            )}
            <span className={styles.nameText}>{name}</span>
            {canRenderYield && renderYield()}
            {withLabel && (
              <span className={buildClassName(styles.label, styles.chainLabel)}>{label}</span>
            )}
          </div>
          <div className={styles.subtitle}>
            <AnimatedCounter text={formatCurrency(price, shortBaseSymbol, undefined, true)} />
            {!stakingStatus && (
              <>
                <i className={styles.dot} aria-hidden />
                {unfreezeEndDate ? (
                  <span className={(unfreezeEndDate - Date.now() < UNFREEZE_DANGER_DURATION) && styles.change_down}>
                    {lang('Unfreeze')}
                    {' '}
                    {lang('until %date%', { date: `${formatFullDay(lang.code!, unfreezeEndDate)}` })}
                  </span>
                ) : (
                  <span className={changeClassName}>
                    {renderChangeIcon()}<AnimatedCounter text={String(changePercent)} />%
                  </span>
                )}
              </>
            )}
          </div>
        </div>
        <div className={styles.secondaryCell}>
          <SensitiveData
            isActive={isSensitiveDataHidden}
            cols={amountCols}
            rows={2}
            cellSize={8}
            align="right"
            className={buildClassName(
              styles.secondaryValue,
              stakingStatus && styles.secondaryValue_staked,
              isVesting && styles.secondaryValue_vesting,
              isVesting && vestingStatus === 'readyToUnfreeze' && styles.secondaryValue_vestingUnfreeze,
            )}
          >
            <AnimatedCounter text={formatCurrency(renderedAmount, symbol)} />
          </SensitiveData>
          <SensitiveData
            isActive={isSensitiveDataHidden}
            cols={fiatAmountCols}
            rows={2}
            cellSize={8}
            align="right"
            className={styles.subtitle}
          >
            {totalAmount.gt(0) ? '≈' : ''}&thinsp;
            <AnimatedCounter text={formatCurrency(totalAmount, shortBaseSymbol, undefined, true)} />
          </SensitiveData>
        </div>
      </Button>
    );
  }

  return (
    <div className={buildClassName(styles.container, classNames)} style={style}>
      <MenuBackdrop
        isMenuOpen={isBackdropRendered}
        contentRef={buttonRef}
        contentClassName={styles.wrapperVisible}
      />
      {isInvestorView ? renderInvestorView() : renderDefaultView()}
      {withContextMenu && isContextMenuShown && (
        <DropdownMenu
          ref={menuRef}
          withPortal
          shouldTranslateOptions
          isOpen={isContextMenuOpen}
          items={items}
          menuAnchor={contextMenuAnchor}
          bubbleClassName={styles.menu}
          fontIconClassName={styles.menuIcon}
          getTriggerElement={getTriggerElement}
          getRootElement={getRootElement}
          getMenuElement={getMenuElement}
          getLayout={getLayout}
          onSelect={handleMenuItemSelect}
          onClose={handleContextMenuClose}
          onCloseAnimationEnd={handleContextMenuHide}
        />
      )}
    </div>
  );
}

export default memo(Token);
