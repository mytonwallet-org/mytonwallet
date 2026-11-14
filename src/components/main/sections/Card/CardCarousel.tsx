import React, {
  type ElementRef,
  memo,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from '../../../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../../../global';

import type { Account } from '../../../../global/types';
import type { CarouselScroll } from '../../../../util/card/carouselScroll';

import { ANIMATION_LEVEL_MED } from '../../../../config';
import { requestForcedReflow, suppressStrict } from '../../../../lib/fasterdom/fasterdom';
import {
  selectCurrentAccount,
  selectCurrentAccountId,
  selectIs3dCardDisabled,
  selectOrderedAccounts,
  selectShownCardAccountId,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { CAROUSEL_WINDOW_RADIUS, startCarouselScroll } from '../../../../util/card/carouselScroll';
import { orderBy } from '../../../../util/iteratees';

import { preloadCardArtworks } from '../../../../hooks/useCardArtwork';
import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useDragScroll from '../../../../hooks/useDragScroll';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import { useMediaQuery } from '../../../../hooks/useMediaQuery';

import Card from './Card';

import styles from './CardCarousel.module.scss';

interface OwnProps {
  ref?: ElementRef<HTMLDivElement>;
  onYieldClick: (stakingId?: string) => void;
}

interface StateProps {
  accountId: string;
  selectedId: string;
  accounts: Array<[string, Account]>;
  temporaryAccount?: Account;
  isMotionDisabled: boolean;
}

const MOUSE_DRAG_THRESHOLD_PX = 12;

function CardCarousel({
  ref,
  accountId,
  selectedId,
  accounts,
  temporaryAccount,
  isMotionDisabled,
  onYieldClick,
}: OwnProps & StateProps) {
  const { isPortrait } = useDeviceScreen();
  const lang = useLang();
  const rootRef = useRef<HTMLDivElement>();
  const viewportRef = useRef<HTMLDivElement>();
  const carouselRef = useRef<CarouselScroll>();
  const [settledId, setSettledId] = useState(selectedId);
  const [windowCenterId, setWindowCenterId] = useState(selectedId);
  const [isMoving, setIsMoving] = useState(false);
  const hasReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');
  const isCarouselMotionDisabled = Boolean(hasReducedMotion || isMotionDisabled);

  const shownAccounts: Array<[string, Account]> = temporaryAccount ? [[accountId, temporaryAccount]] : accounts;
  const accountIds = useMemo(() => (
    temporaryAccount ? [accountId] : accounts.map(([id]) => id)
  ), [accountId, accounts, temporaryAccount]);
  const accountIdsKey = accountIds.join('|');
  const windowCenterIndex = Math.max(0, accountIds.indexOf(windowCenterId));

  const getAccountIds = useLastCallback(() => accountIds);
  const getIsMotionDisabled = useLastCallback(() => isCarouselMotionDisabled);

  const alignWithShownAccount = useLastCallback(() => {
    // A moving card is reconciled with the account when the movement ends
    if (isMoving || selectedId === settledId) return;

    setWindowCenterId(selectedId);

    // The card of a far account has to mount first, and this runs again when the window has moved to it
    if (Math.abs(accountIds.indexOf(selectedId) - windowCenterIndex) > CAROUSEL_WINDOW_RADIUS) return;

    carouselRef.current?.alignToAccount(selectedId);
  });

  const handleSelectedChange = useLastCallback((id: string) => {
    getActions().showCardAccount({ accountId: id });
  });

  const handleSettle = useLastCallback((id: string) => {
    setSettledId(id);
    setWindowCenterId(id);

    // Without a shown card, the carousel has only aligned itself with the current account
    if (getGlobal().shownCardAccountId !== undefined) getActions().switchToCardAccount({ accountId: id });
  });

  // `Card` fits its balance to this width in its own layout effect, which runs after this one
  useLayoutEffect(() => {
    suppressStrict(() => {
      viewportRef.current!.style.setProperty('--carousel-card-width', `${rootRef.current!.clientWidth}px`);
    });
  }, [isPortrait]);

  useLayoutEffect(() => {
    let carousel: CarouselScroll | undefined;
    let isCancelled = false;

    // The width of the cards comes from a measurement, and it must be set before the first paint
    requestForcedReflow(() => {
      if (isCancelled) return;

      carousel = startCarouselScroll({
        root: rootRef.current!,
        viewport: viewportRef.current!,
        snapDisabledClassName: styles.snapDisabled,
        getAccountIds,
        getStartAccountId: getShownAccountId,
        getIsMotionDisabled,
        onSelectedChange: handleSelectedChange,
        onMovingChange: setIsMoving,
        onSettle: handleSettle,
      });
      carouselRef.current = carousel;

      // A gesture that the previous carousel did not finish settles here
      const shownAccountId = getShownAccountId();
      if (shownAccountId !== selectCurrentAccountId(getGlobal())) handleSettle(shownAccountId);
    });

    return () => {
      isCancelled = true;
      carousel?.stop();
      carouselRef.current = undefined;
    };
  }, [accountIdsKey, getAccountIds, getIsMotionDisabled, handleSelectedChange, handleSettle, isPortrait]);

  // The carousel is absent for a frame while it restarts for another account list or layout
  const getDragBounds = useLastCallback(() => carouselRef.current?.getGestureBounds());
  const handleDragStart = useLastCallback(() => carouselRef.current?.startMouseDrag());
  const handleDragEnd = useLastCallback((velocity: number) => carouselRef.current?.finishMouseDrag(velocity));

  useDragScroll({
    containerRef: viewportRef,
    dragThreshold: MOUSE_DRAG_THRESHOLD_PX,
    getScrollBounds: getDragBounds,
    onDragStart: handleDragStart,
    onDragEnd: handleDragEnd,
  });

  useEffect(alignWithShownAccount, [
    selectedId, settledId, isMoving, accountIdsKey, alignWithShownAccount, isPortrait, windowCenterIndex,
  ]);

  useEffect(() => {
    preloadCardArtworks(getCardNftsByDistance(getAccountIds(), accountId));
  }, [accountId, accountIdsKey, getAccountIds]);

  function renderItem([id, account]: [string, Account], index: number) {
    // The settled card stays visible until a far jump finishes
    const isMounted = Math.abs(index - windowCenterIndex) <= CAROUSEL_WINDOW_RADIUS
      || id === selectedId || id === settledId;
    const isCurrent = id === accountId;

    return (
      <div
        key={id}
        data-card-carousel-item
        className={styles.item}
        aria-hidden={id !== selectedId}
        aria-label={account.title}
      >
        <div
          data-card-carousel-pose
          className={buildClassName(
            styles.pose,
            isCarouselMotionDisabled && styles.poseStill,
            !isMounted && styles.posePlaceholder,
          )}
        >
          {isMounted && (
            <Card
              accountId={id}
              isActive={isCurrent}
              isPaused={isCurrent && (isMoving || id !== selectedId)}
              onYieldClick={onYieldClick}
            />
          )}
        </div>
      </div>
    );
  }

  return (
    <div ref={rootRef} className={styles.root} role="region" aria-label={lang('Wallets')}>
      <div ref={ref} className={styles.visibilityTarget} aria-hidden="true" />
      <div ref={viewportRef} className={buildClassName(styles.viewport, 'no-scrollbar')} dir="ltr">
        <div className={styles.track} teactFastList>
          {shownAccounts.map(renderItem)}
        </div>
      </div>
      {shownAccounts.length > 1 && (
        <div className={styles.edges} aria-hidden="true">
          <span className={buildClassName(styles.edge, styles.edgeLeft)} />
          <span className={buildClassName(styles.edge, styles.edgeRight)} />
        </div>
      )}
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const account = selectCurrentAccount(global);

  return {
    accountId: selectCurrentAccountId(global)!,
    selectedId: selectShownCardAccountId(global)!,
    accounts: selectOrderedAccounts(global),
    temporaryAccount: account?.isTemporary ? account : undefined,
    isMotionDisabled: selectIs3dCardDisabled(global) || global.settings.animationLevel === ANIMATION_LEVEL_MED,
  };
})(CardCarousel));

function getShownAccountId() {
  return selectShownCardAccountId(getGlobal())!;
}

function getCardNftsByDistance(accountIds: string[], centerAccountId: string) {
  const { byAccountId } = getGlobal().settings;
  const centerIndex = accountIds.indexOf(centerAccountId);
  const accountsByDistance = orderBy(
    accountIds.map((id, index) => ({ id, distance: Math.abs(index - centerIndex) })),
    'distance',
  );

  return accountsByDistance.map(({ id }) => byAccountId[id]?.cardBackgroundNft).filter(Boolean);
}
