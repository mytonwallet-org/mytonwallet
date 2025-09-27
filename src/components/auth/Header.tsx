import type { ElementRef } from '../../lib/teact/teact';
import React, { memo, useState } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import { REM } from '../../util/windowEnvironment';
import { calcSafeAreaTop } from '../main/helpers/calcSafeAreaTop';

import useElementVisibility from '../../hooks/useElementVisibility';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import { HEADER_HEIGHT_REM } from '../main/sections/Header/Header';
import Button from '../ui/Button';

import styles from './Header.module.scss';

interface OwnProps {
  isActive: boolean | undefined;
  title?: string;
  topTargetRef?: ElementRef<HTMLDivElement | undefined>;
  withBorder?: boolean;
  backButtonText?: string;
  className?: string;
  onBackClick: NoneToVoidFunction;
}

function Header({
  isActive,
  title,
  topTargetRef,
  withBorder,
  className,
  backButtonText,
  onBackClick,
}: OwnProps) {
  const lang = useLang();

  const isTitleAlwaysVisible = !topTargetRef;
  const [isTitleVisible, setIsTitleVisible] = useState(isTitleAlwaysVisible);
  const safeAreaTop = calcSafeAreaTop();
  const intersectionRootMarginTop = HEADER_HEIGHT_REM * REM + safeAreaTop;
  // If `withBorder` is `undefined`, it means that the border visibility is controlled by `transform`
  const isBorderVisible = withBorder || withBorder === undefined;

  const handleIntersection = useLastCallback((entry: IntersectionObserverEntry) => {
    setIsTitleVisible(!entry.isIntersecting && entry.boundingClientRect.top - intersectionRootMarginTop < 0);
  });

  useElementVisibility({
    isDisabled: !isActive || !topTargetRef,
    targetRef: topTargetRef,
    rootMargin: `-${intersectionRootMarginTop}px 0px 0px 0px`,
    cb: handleIntersection,
    threshold: [1],
  });

  return (
    <div className={buildClassName(styles.root, className)}>
      {!!title && (
        <div className={buildClassName(
          styles.background,
          isTitleVisible && styles.backgroundVisible,
          isBorderVisible && styles.backgroundWithBorder,
        )}
        />
      )}
      <Button
        isSimple
        isText
        className={styles.backButton}
        onClick={onBackClick}
      >
        <i className={buildClassName(styles.backIcon, 'icon-chevron-left')} aria-hidden />

        <span>{backButtonText || lang('Back')}</span>
      </Button>

      {!!title && (
        <div
          aria-hidden={!isTitleAlwaysVisible}
          className={buildClassName(styles.title, (isTitleAlwaysVisible || isTitleVisible) && styles.titleVisible)}
        >
          {title}
        </div>
      )}
    </div>
  );
}

export default memo(Header);
