import React, { memo, useEffect, useRef } from '../../lib/teact/teact';

import type { DropdownItem } from './Dropdown';

import { requestMutation } from '../../lib/fasterdom/fasterdom';
import animateHorizontalScroll from '../../util/animateHorizontalScroll';
import buildClassName from '../../util/buildClassName';
import { IS_ANDROID, IS_IOS } from '../../util/windowEnvironment';

import useHorizontalScroll from '../../hooks/useHorizontalScroll';
import useLang from '../../hooks/useLang';
import useWindowSize from '../../hooks/useWindowSize';

import Tab from './Tab';

import styles from './TabList.module.scss';

export type TabWithProperties<T extends number = number> = {
  id: T;
  icon?: string;
  title: string;
  className?: string;
  menuItems?: DropdownItem[];
  menuClassName?: string;
  menuPositionX?: 'left' | 'right';
  onMenuItemClick?: (value: string) => void;
};

type OwnProps = {
  isActive?: boolean;
  tabs: readonly TabWithProperties[];
  activeTab: number;
  className?: string;
  overlayClassName?: string;
  onSwitchTab: (index: number) => void;
  onActiveTabClick?: NoneToVoidFunction;
};

const TAB_SCROLL_THRESHOLD_PX = 16;
// Should match duration from `--slide-transition` CSS variable
const SCROLL_DURATION = IS_IOS ? 450 : IS_ANDROID ? 400 : 300;
const CLIP_PATH_CONTAINER_CLASS_NAME = 'clip-path-container';

function TabList({
  isActive, tabs, activeTab, className, overlayClassName, onSwitchTab, onActiveTabClick,
}: OwnProps) {
  const lang = useLang();
  const containerRef = useRef<HTMLDivElement>();
  const { width: appWidth } = useWindowSize();

  const fullClassName = buildClassName(
    styles.container,
    'no-scrollbar',
    className,
  );

  useHorizontalScroll({
    containerRef,
    shouldPreventDefault: true,
  });

  useActiveTabCentering(activeTab, containerRef.current);

  useEffect(() => {
    const container = containerRef.current?.querySelector(`.${CLIP_PATH_CONTAINER_CLASS_NAME}`) as HTMLElement | null;
    const activeTabElement = container?.childNodes[activeTab] as HTMLElement | null;

    if (container && activeTabElement) {
      const clipPath = calculateClipPath(activeTabElement, container);
      requestMutation(() => {
        container.style.clipPath = clipPath;
      });
    }
    // When the following dependencies change, `clipPath` must be updated
  }, [isActive, activeTab, tabs, lang, containerRef, appWidth]);

  return (
    <div ref={containerRef} className={fullClassName}>
      {tabs.map((tab, i) => (
        <Tab
          key={tab.title}
          title={tab.title}
          isActive={i === activeTab}
          className={tab?.className}
          menuItems={tab?.menuItems}
          menuClassName={tab?.menuClassName}
          menuPositionX={tab?.menuPositionX}
          onMenuItemClick={tab?.onMenuItemClick}
          onActiveClick={onActiveTabClick}
          onClick={onSwitchTab}
          clickArg={tab.id}
          icon={tab.icon}
        />
      ))}

      <div
        className={buildClassName(styles.clipPathContainer, overlayClassName, CLIP_PATH_CONTAINER_CLASS_NAME)}
        aria-hidden
      >
        {tabs.map((tab, i) => (
          <Tab
            key={tab.title}
            title={tab.title}
            isActive={i === activeTab}
            className={buildClassName(tab?.className, i === activeTab && 'current-tab')}
            menuItems={tab?.menuItems}
            menuClassName={tab?.menuClassName}
            menuPositionX={tab?.menuPositionX}
            onActiveClick={onActiveTabClick}
            onMenuItemClick={tab?.onMenuItemClick}
            onClick={onSwitchTab}
            clickArg={tab.id}
            icon={tab.icon}
          />
        ))}
      </div>
    </div>
  );
}

export default memo(TabList);

function calculateClipPath(activeElement: HTMLElement, container: HTMLElement) {
  const { paddingTop, paddingBottom } = getComputedStyle(activeElement);
  const {
    offsetLeft,
    offsetWidth,
  } = activeElement;

  const clipLeft = offsetLeft;
  const clipRight = offsetLeft + offsetWidth;
  const rightPosition = Number(100 - (clipRight / container.offsetWidth) * 100).toFixed(3);
  const leftPosition = Number((clipLeft / container.offsetWidth) * 100).toFixed(3);

  return `inset(${parseInt(paddingTop)}px ${rightPosition}% ${parseInt(paddingBottom)}px ${leftPosition}% round 1rem)`;
}

// Scroll container to place active tab in the center
function useActiveTabCentering(activeTab: number, container?: HTMLDivElement) {
  useEffect(() => {
    if (!container) return;

    const { scrollWidth, offsetWidth, scrollLeft } = container;
    if (scrollWidth <= offsetWidth) {
      return;
    }

    const activeTabElement = container.childNodes[activeTab] as HTMLElement | null;
    if (!activeTabElement) {
      return;
    }

    const { offsetLeft: activeTabOffsetLeft, offsetWidth: activeTabOffsetWidth } = activeTabElement;
    const newLeft = activeTabOffsetLeft - (offsetWidth / 2) + (activeTabOffsetWidth / 2);

    // Prevent scrolling by only a couple of pixels, which doesn't look smooth
    if (Math.abs(newLeft - scrollLeft) < TAB_SCROLL_THRESHOLD_PX) {
      return;
    }

    void animateHorizontalScroll(container, newLeft, SCROLL_DURATION);
  }, [activeTab, container]);
}
