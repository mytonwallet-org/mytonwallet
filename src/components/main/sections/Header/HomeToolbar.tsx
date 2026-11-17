import type { TeactNode } from '../../../../lib/teact/teact';
import React, { memo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { Account } from '../../../../global/types';

import { IS_EXTENSION, IS_TELEGRAM_APP } from '../../../../config';
import {
  selectCurrentAccount,
  selectCurrentAccountId,
  selectHasPassword,
  selectIsCurrentAccountViewMode,
} from '../../../../global/selectors';
import { getAccountTitle } from '../../../../util/account';
import buildClassName from '../../../../util/buildClassName';
import { getTelegramAvatarUrlFromDomain } from '../../../../util/dns';
import getTestId from '../../../../util/getTestId';
import { animateCapsuleWidth, animateShift } from '../../../../util/layoutChangeAnimation';
import { IS_ELECTRON, REM } from '../../../../util/windowEnvironment';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useLayoutEffectWithPrevDeps from '../../../../hooks/useLayoutEffectWithPrevDeps';
import useQrScannerSupport from '../../../../hooks/useQrScannerSupport';
import useShowTransition from '../../../../hooks/useShowTransition';

import WalletAvatar from '../../../ui/WalletAvatar';
import AppLockButton from './actionButtons/AppLockButton';
import BackButton from './actionButtons/BackButton';
import QrScannerButton from './actionButtons/QrScannerButton';
import ToggleFullscreenButton from './actionButtons/ToggleFullscreenButton';
import ToggleLayoutButton from './actionButtons/ToggleLayoutButton';
import ToggleSensitiveDataButton from './actionButtons/ToggleSensitiveDataButton';
import HomeSearchField from './HomeSearchField';

import styles from './HomeToolbar.module.scss';

interface OwnProps {
  isHidden?: boolean;
  isOnFirstBackground?: boolean;
  isOverScreenHeader?: boolean;
}

interface StateProps {
  currentAccountId?: string;
  currentAccount?: Account;
  isViewMode?: boolean;
  isAppLockEnabled: boolean;
  isSensitiveDataHidden: boolean;
  isFullscreen: boolean;
  isTemporaryAccount: boolean;
}

const CAN_TOGGLE_APP_LAYOUT = IS_EXTENSION || IS_ELECTRON;
const LOCK_TRANSITION_DURATION_MS = 200;
// Must match the width of the `.lock` icon plus the `.pill` gap in front of it
const LOCK_SLOT_WIDTH_PX = 2.5 * REM;

function HomeToolbar({
  isHidden,
  isOnFirstBackground,
  isOverScreenHeader,
  currentAccountId,
  currentAccount,
  isViewMode,
  isAppLockEnabled,
  isSensitiveDataHidden,
  isFullscreen,
  isTemporaryAccount,
}: OwnProps & StateProps) {
  const { switchToSettings } = getActions();

  const lang = useLang();
  const { isPortrait } = useDeviceScreen();
  const isQrScannerSupported = useQrScannerSupport() && !isViewMode;

  const searchRef = useRef<HTMLDivElement>();
  const microphoneRef = useRef<HTMLElement>();
  const pillRef = useRef<HTMLDivElement>();
  const pillStartRef = useRef<HTMLDivElement>();

  const { shouldRender: shouldRenderLock, ref: lockRef } = useShowTransition<HTMLDivElement>({
    isOpen: isAppLockEnabled,
    withShouldRender: true,
    noMountTransition: true,
    closeDuration: LOCK_TRANSITION_DURATION_MS,
    className: false,
  });

  // In landscape the lock shares a capsule with its neighbours, so the capsule plays out the change.
  // The row takes its final layout at once, and the neighbours of the icon slide from their old positions.
  useLayoutEffectWithPrevDeps(([wasAppLockEnabled]) => {
    if (isPortrait || wasAppLockEnabled === undefined || wasAppLockEnabled === isAppLockEnabled) return;

    const pillWidthChange = isAppLockEnabled ? LOCK_SLOT_WIDTH_PX : -LOCK_SLOT_WIDTH_PX;
    const shift = lang.isRtl ? -pillWidthChange : pillWidthChange;

    animateCapsuleWidth(pillRef.current!, 'start', pillWidthChange, LOCK_TRANSITION_DURATION_MS, lang.isRtl);
    animateCapsuleWidth(searchRef.current!, 'end', -pillWidthChange, LOCK_TRANSITION_DURATION_MS, lang.isRtl);
    animateShift(pillStartRef.current!, shift, 0, LOCK_TRANSITION_DURATION_MS);
    animateShift(microphoneRef.current!, shift, 0, LOCK_TRANSITION_DURATION_MS);
  }, [isAppLockEnabled, isPortrait, lang.isRtl]);

  const handleAvatarClick = useLastCallback(() => {
    switchToSettings();
  });

  function renderStartPill() {
    const isFullscreenToggleShown = isPortrait && IS_TELEGRAM_APP;
    if (!CAN_TOGGLE_APP_LAYOUT && !isFullscreenToggleShown && !isQrScannerSupported) return undefined;

    return (
      <div className={styles.pill}>
        {CAN_TOGGLE_APP_LAYOUT && <ToggleLayoutButton />}
        {isFullscreenToggleShown && <ToggleFullscreenButton isFullscreen={isFullscreen} />}
        <QrScannerButton isViewMode={isViewMode} />
      </div>
    );
  }

  function renderPortraitEnd() {
    return (
      <>
        {isAppLockEnabled && renderPill(<AppLockButton />)}
        {currentAccount && (
          <button
            type="button"
            className={styles.avatarButton}
            aria-label={lang('Settings')}
            data-testid={getTestId('tab_settings_button')}
            onClick={handleAvatarClick}
          >
            <WalletAvatar
              className={styles.avatar}
              title={getAccountTitle(currentAccount)}
              accountId={currentAccountId}
              imageUrl={getTelegramAvatarUrlFromDomain(currentAccount.byChain.ton?.domain)}
            />
          </button>
        )}
      </>
    );
  }

  function renderLandscapeEnd() {
    return (
      <div ref={pillRef} className={styles.pill}>
        <div ref={pillStartRef} className={styles.pillStart}>
          <ToggleSensitiveDataButton isSensitiveDataHidden={isSensitiveDataHidden} />
          {IS_TELEGRAM_APP && <ToggleFullscreenButton isFullscreen={isFullscreen} />}
        </div>
        {shouldRenderLock && (
          <div ref={lockRef} className={styles.lock}>
            <AppLockButton />
          </div>
        )}
      </div>
    );
  }

  return (
    <div
      className={buildClassName(
        styles.root,
        isPortrait ? styles.portrait : styles.landscape,
        isHidden && styles.hidden,
        isOnFirstBackground && styles.onFirstBackground,
        isOverScreenHeader && styles.overScreenHeader,
      )}
    >
      <div className={buildClassName(styles.row, isPortrait && styles.rowPortrait)}>
        {isTemporaryAccount && renderPill(<BackButton isIconOnly />)}
        {renderStartPill()}
        <HomeSearchField ref={searchRef} microphoneRef={microphoneRef} />
        {isPortrait ? renderPortraitEnd() : renderLandscapeEnd()}
      </div>
    </div>
  );
}

export default memo(withGlobal<OwnProps>(
  (global): StateProps => {
    const {
      isFullscreen,
      currentTemporaryViewAccountId,
      settings: {
        isAppLockEnabled,
        isSensitiveDataHidden,
      },
    } = global;

    return {
      currentAccountId: selectCurrentAccountId(global),
      currentAccount: selectCurrentAccount(global),
      isViewMode: selectIsCurrentAccountViewMode(global),
      isAppLockEnabled: Boolean(isAppLockEnabled && selectHasPassword(global)),
      isFullscreen: Boolean(isFullscreen),
      isSensitiveDataHidden: Boolean(isSensitiveDataHidden),
      isTemporaryAccount: Boolean(currentTemporaryViewAccountId),
    };
  },
)(HomeToolbar));

function renderPill(content: TeactNode) {
  return <div className={styles.pill}>{content}</div>;
}
