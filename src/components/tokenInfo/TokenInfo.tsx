import React, { memo, useEffect, useRef } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { UserToken } from '../../global/types';

import { selectCurrentAccountState, selectUserTokenMemoized } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { animateContentShift } from '../../util/layoutChangeAnimation';
import { captureControlledSwipe } from '../../util/swipeController';
import useTelegramMiniAppSwipeToClose from '../../util/telegram/hooks/useTelegramMiniAppSwipeToClose';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';

import Activities from '../main/sections/Content/Activities';
import Header from './Header';
import Summary from './Summary';

import styles from './TokenInfo.module.scss';

interface OwnProps {
  isActive?: boolean;
}

interface StateProps {
  token?: UserToken;
}

const SCROLL_CONTAINER_CLASS = 'token-content-scroll';
const SCROLL_CONTAINER_SELECTOR = `.${SCROLL_CONTAINER_CLASS}`;

function TokenInfo({ isActive, token }: OwnProps & StateProps) {
  const { closeTokenActivity, selectToken } = getActions();

  const rootRef = useRef<HTMLDivElement>();
  const activityRef = useRef<HTMLDivElement>();
  const { handleScroll, isScrolled } = useScrolledState();

  const { disableSwipeToClose, enableSwipeToClose } = useTelegramMiniAppSwipeToClose(isActive);

  const renderedToken = useCurrentOrPrev(token, true);
  const slug = token?.slug;

  useEffect(() => {
    if (!IS_TOUCH_ENV || !slug) return undefined;

    return captureControlledSwipe(rootRef.current!, {
      onSwipeRightStart: () => {
        closeTokenActivity();
        disableSwipeToClose();
      },
      onCancel: () => {
        selectToken({ slug });
        enableSwipeToClose();
      },
    });
  }, [slug, disableSwipeToClose, enableSwipeToClose]);

  const handleSummaryHeightChange = useLastCallback((prevHeight: number, nextHeight: number) => {
    animateContentShift(activityRef.current!, SCROLL_CONTAINER_SELECTOR, prevHeight - nextHeight);
  });

  if (!renderedToken) return undefined;

  return (
    <div ref={rootRef} className={styles.root}>
      <Header
        token={renderedToken}
        isScrolled={isScrolled}
        // The portrait slide stays mounted between openings, so only the visible screen handles history and Esc
        isHidden={!isActive}
        className={styles.header}
        onBackClick={closeTokenActivity}
      />

      <div className={buildClassName(styles.body, 'custom-scroll', SCROLL_CONTAINER_CLASS)} onScroll={handleScroll}>
        <Summary
          key={renderedToken.slug}
          token={renderedToken}
          isActive={isActive}
          className={styles.summary}
          onHeightChange={handleSummaryHeightChange}
        />

        <div ref={activityRef} className={styles.activity}>
          <Activities isActive={isActive} scrollContainerSelector={SCROLL_CONTAINER_SELECTOR} />
        </div>
      </div>
    </div>
  );
}

export default memo(
  withGlobal<OwnProps>((global): StateProps => {
    const { currentTokenSlug } = selectCurrentAccountState(global) ?? {};

    return {
      token: currentTokenSlug ? selectUserTokenMemoized(global, currentTokenSlug) : undefined,
    };
  })(TokenInfo),
);
